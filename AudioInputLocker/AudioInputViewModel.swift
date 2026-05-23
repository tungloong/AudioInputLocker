import AppKit
import ApplicationServices
import Combine
import CoreAudio
import Foundation
import SwiftUI

struct InputLockSectionState: Equatable {
    var isEnabled: Bool
    var rows: [InputLockRowState]
}

struct InputLockRowState: Identifiable, Equatable {
    enum Role: Equatable {
        case current
        case locked
        case candidate
        case released
    }

    let id: String
    let role: Role
    let uid: String?
    let deviceName: String
    let isLocked: Bool
    let isOnline: Bool
    let isCurrent: Bool
    let lockAnimationDeadline: Date?
    let lockAnimationDuration: TimeInterval?
    let countdownDeadline: Date?
    let countdownDuration: TimeInterval?

    var isActionable: Bool {
        uid != nil && lockAnimationDeadline == nil && (isOnline || isLocked)
    }
}

@MainActor
final class AudioInputViewModel: ObservableObject {
    @Published private(set) var devices: [InputDevice] = []
    @Published var currentVolume: Double = 0
    @Published private(set) var volumeIsEnabled = false
    @Published private(set) var inputLockIsEnabled = true
    @Published private(set) var inputLockSectionState = InputLockSectionState(isEnabled: true, rows: [])
    @Published private(set) var errorMessage: String?

    var hasDevices: Bool {
        !devices.isEmpty
    }

    func menuDidOpen() {
        PreferredInputHUD.shared.dismissForMenuOpening()
    }

    private struct PendingLockChoice {
        let previousUID: String
        let previousName: String
        let currentUID: String
        let currentName: String
        let relockDeadline: Date?
    }

    private struct ReleasedLockRow {
        let uid: String
        let name: String
        let wasOnline: Bool
    }

    private struct PendingLockAnimation {
        let uid: String
        let previous: ReleasedLockRow?
        let deadline: Date
    }

    private enum DefaultsKey {
        static let preferredUID = "preferredInputDeviceUID"
        static let preferredName = "preferredInputDeviceName"
        static let inputLockEnabled = "inputLockEnabled"
    }

    private enum LockTiming {
        static let lockAnimationDuration: TimeInterval = 0.5
        static let manualChoiceDuration: TimeInterval = 5
        static let releasedRowDuration: TimeInterval = 2
    }

    private let audioManager = CoreAudioInputManager()
    private let volumeWriteQueue = DispatchQueue(label: "AudioInputLocker.VolumeWrite", qos: .userInitiated)

    private var volumeWriteWorkItem: DispatchWorkItem?
    private var pendingManualSelectionUID: String?
    private var pendingSwitchBackUID: String?
    private var pendingLockChoice: PendingLockChoice?
    private var manualRelockWorkItem: DispatchWorkItem?
    private var releasedLockRow: ReleasedLockRow?
    private var releasedRowWorkItem: DispatchWorkItem?
    private var pendingLockAnimation: PendingLockAnimation?
    private var lockAnimationWorkItem: DispatchWorkItem?
    private var suppressVolumeEchoUntil = Date.distantPast
    private var debugHUDObserver: NSObjectProtocol?

    private var currentDevice: InputDevice? {
        devices.first(where: \.isDefault)
    }

    private var storedPreferredUID: String? {
        get { UserDefaults.standard.string(forKey: DefaultsKey.preferredUID) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: DefaultsKey.preferredUID)
            } else {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.preferredUID)
            }
        }
    }

    private var storedPreferredName: String? {
        get { UserDefaults.standard.string(forKey: DefaultsKey.preferredName) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: DefaultsKey.preferredName)
            } else {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.preferredName)
            }
        }
    }

    init() {
        inputLockIsEnabled = UserDefaults.standard.object(forKey: DefaultsKey.inputLockEnabled) as? Bool ?? true
        refresh()
        audioManager.startMonitoring { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleAudioChange()
            }
        }

        #if DEBUG
        installDebugHUDTrigger()
        #endif
    }

    deinit {
        volumeWriteWorkItem?.cancel()
        manualRelockWorkItem?.cancel()
        releasedRowWorkItem?.cancel()
        lockAnimationWorkItem?.cancel()
        audioManager.stopMonitoring()

        #if DEBUG
        if let debugHUDObserver {
            DistributedNotificationCenter.default().removeObserver(debugHUDObserver)
        }
        #endif
    }

    func select(_ device: InputDevice) {
        if device.isDefault {
            return
        }

        let previousLockedUID = storedPreferredUID
        let previousLockedName = storedPreferredName
        let lockedDeviceIsOnline = previousLockedUID.map { uid in devices.contains { $0.uid == uid } } ?? false

        if inputLockIsEnabled,
           let lockedUID = previousLockedUID,
           lockedUID != device.uid,
           let lockedName = previousLockedName {
            let deadline = lockedDeviceIsOnline ? Date().addingTimeInterval(LockTiming.manualChoiceDuration) : nil
            pendingLockChoice = PendingLockChoice(
                previousUID: lockedUID,
                previousName: lockedName,
                currentUID: device.uid,
                currentName: device.displayName,
                relockDeadline: deadline
            )

            if let deadline {
                scheduleManualRelock(at: deadline)
            } else {
                cancelManualRelock()
            }
        } else {
            pendingLockChoice = nil
            cancelManualRelock()
            cancelLockAnimation()
        }

        pendingManualSelectionUID = device.uid

        do {
            try audioManager.setDefaultInputDevice(device.id)
            errorMessage = nil
            refresh()
        } catch {
            storedPreferredUID = previousLockedUID
            storedPreferredName = previousLockedName
            pendingManualSelectionUID = nil
            pendingLockChoice = nil
            cancelManualRelock()
            errorMessage = error.localizedDescription
            refresh()
        }
    }

    func setCurrentVolume(_ volume: Double) {
        let clampedVolume = min(max(volume, 0), 1)
        currentVolume = clampedVolume
        suppressVolumeEchoUntil = Date().addingTimeInterval(0.25)

        guard volumeIsEnabled,
              let deviceID = currentDevice?.id else {
            return
        }

        volumeWriteWorkItem?.cancel()

        let workItem = DispatchWorkItem { [audioManager, weak self] in
            let result = Result {
                try audioManager.setInputVolume(Float(clampedVolume), for: deviceID)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.handleVolumeWriteResult(result)
            }
        }

        volumeWriteWorkItem = workItem
        volumeWriteQueue.asyncAfter(deadline: .now() + 0.045, execute: workItem)
    }

    func setInputLockEnabled(_ isEnabled: Bool) {
        guard inputLockIsEnabled != isEnabled else { return }
        inputLockIsEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: DefaultsKey.inputLockEnabled)

        if !isEnabled {
            pendingLockChoice = nil
            cancelManualRelock()
            releasedLockRow = nil
            releasedRowWorkItem?.cancel()
            releasedRowWorkItem = nil
            cancelLockAnimation()
        } else {
            enforceStoredInputLockIfNeeded()
        }

        updateInputLockState()
    }

    func toggleInputLockRow(_ row: InputLockRowState) {
        guard inputLockIsEnabled,
              row.isActionable,
              let uid = row.uid else {
            return
        }

        if row.isLocked {
            unlockInput(row)
        } else if let device = devices.first(where: { $0.uid == uid }) {
            beginLockAnimation(for: device, replacing: storedPreferredSnapshot())
        }
    }

    func openSoundSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Sound-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.sound"
        ]

        for urlString in urls {
            guard let url = URL(string: urlString),
                  NSWorkspace.shared.open(url) else {
                continue
            }
            return
        }
    }

    private func refresh() {
        do {
            applyLoadedDevices(try audioManager.loadInputDevices())
            enforceStoredInputLockIfNeeded()
            errorMessage = nil
        } catch {
            devices = []
            currentVolume = 0
            volumeIsEnabled = false
            inputLockSectionState = InputLockSectionState(isEnabled: inputLockIsEnabled, rows: [])
            audioManager.monitorVolume(for: nil)
            errorMessage = error.localizedDescription
        }
    }

    private func handleAudioChange() {
        if shouldIgnoreVolumeEcho() {
            return
        }

        do {
            let loadedDevices = try audioManager.loadInputDevices()
            let current = loadedDevices.first(where: \.isDefault)

            if let pendingManualSelectionUID,
               current?.uid == pendingManualSelectionUID {
                self.pendingManualSelectionUID = nil
                applyLoadedDevices(loadedDevices)
                return
            }

            if let pendingSwitchBackUID,
               current?.uid == pendingSwitchBackUID {
                self.pendingSwitchBackUID = nil
                applyLoadedDevices(loadedDevices)
                return
            }

            if let choice = pendingLockChoice {
                if current?.uid == choice.previousUID {
                    pendingLockChoice = nil
                    cancelManualRelock()
                }

                applyLoadedDevices(loadedDevices)
                errorMessage = nil
                return
            }

            if inputLockIsEnabled,
               let preferredUID = storedPreferredUID,
               let preferredDevice = loadedDevices.first(where: { $0.uid == preferredUID }),
               let current,
               current.uid != preferredUID {
                applyLoadedDevices(loadedDevices)
                switchBack(to: preferredDevice, from: current)
                return
            }

            applyLoadedDevices(loadedDevices)
            errorMessage = nil
        } catch {
            pendingManualSelectionUID = nil
            pendingSwitchBackUID = nil
            pendingLockChoice = nil
            cancelManualRelock()
            cancelLockAnimation()
            devices = []
            currentVolume = 0
            volumeIsEnabled = false
            inputLockSectionState = InputLockSectionState(isEnabled: inputLockIsEnabled, rows: [])
            audioManager.monitorVolume(for: nil)
            errorMessage = error.localizedDescription
        }
    }

    private func shouldIgnoreVolumeEcho() -> Bool {
        guard Date() < suppressVolumeEchoUntil,
              let currentDevice else {
            return false
        }

        return (try? audioManager.defaultInputDeviceID()) == currentDevice.id
    }

    private func applyLoadedDevices(_ loadedDevices: [InputDevice]) {
        devices = loadedDevices

        if let current = loadedDevices.first(where: \.isDefault) {
            currentVolume = Double(current.inputVolume ?? 0)
            volumeIsEnabled = current.supportsInputVolume
            audioManager.monitorVolume(for: current.id)
        } else {
            currentVolume = 0
            volumeIsEnabled = false
            audioManager.monitorVolume(for: nil)
        }

        updateInputLockState()
    }

    private func updateInputLockState() {
        guard inputLockIsEnabled else {
            inputLockSectionState = InputLockSectionState(isEnabled: false, rows: [])
            return
        }

        var rows: [InputLockRowState] = []

        if let releasedLockRow {
            rows.append(
                InputLockRowState(
                    id: "released:\(releasedLockRow.uid)",
                    role: .released,
                    uid: releasedLockRow.uid,
                    deviceName: releasedLockRow.name,
                    isLocked: false,
                    isOnline: releasedLockRow.wasOnline,
                    isCurrent: currentDevice?.uid == releasedLockRow.uid,
                    lockAnimationDeadline: pendingLockAnimation?.uid == releasedLockRow.uid ? pendingLockAnimation?.deadline : nil,
                    lockAnimationDuration: pendingLockAnimation?.uid == releasedLockRow.uid ? LockTiming.lockAnimationDuration : nil,
                    countdownDeadline: nil,
                    countdownDuration: nil
                )
            )
        }

        if let lockedUID = storedPreferredUID,
           let lockedName = storedPreferredName {
            let lockedDevice = devices.first(where: { $0.uid == lockedUID })
            let countdownDeadline = pendingLockChoice?.previousUID == lockedUID
                ? pendingLockChoice?.relockDeadline
                : nil

            if !rows.contains(where: { $0.uid == lockedUID }) {
                rows.append(
                    InputLockRowState(
                        id: "locked:\(lockedUID)",
                        role: .locked,
                        uid: lockedUID,
                        deviceName: lockedDevice?.displayName ?? lockedName,
                        isLocked: true,
                        isOnline: lockedDevice != nil,
                        isCurrent: currentDevice?.uid == lockedUID,
                        lockAnimationDeadline: nil,
                        lockAnimationDuration: nil,
                        countdownDeadline: countdownDeadline,
                        countdownDuration: countdownDeadline == nil ? nil : LockTiming.manualChoiceDuration
                    )
                )
            }
        }

        if let choice = pendingLockChoice,
           let current = currentDevice,
           current.uid == choice.currentUID,
           !rows.contains(where: { $0.uid == current.uid }) {
            rows.append(
                InputLockRowState(
                    id: "candidate:\(current.uid)",
                    role: .candidate,
                    uid: current.uid,
                    deviceName: current.displayName,
                    isLocked: false,
                    isOnline: true,
                    isCurrent: true,
                    lockAnimationDeadline: pendingLockAnimation?.uid == current.uid ? pendingLockAnimation?.deadline : nil,
                    lockAnimationDuration: pendingLockAnimation?.uid == current.uid ? LockTiming.lockAnimationDuration : nil,
                    countdownDeadline: nil,
                    countdownDuration: nil
                )
            )
        } else if let preferredUID = storedPreferredUID,
                  devices.first(where: { $0.uid == preferredUID }) == nil,
                  let current = currentDevice,
                  !rows.contains(where: { $0.uid == current.uid }) {
            rows.append(currentUnlockedRow(current))
        } else if storedPreferredUID == nil,
                  let current = currentDevice,
                  !rows.contains(where: { $0.uid == current.uid }) {
            rows.append(currentUnlockedRow(current))
        }

        inputLockSectionState = InputLockSectionState(isEnabled: true, rows: rows)
    }

    private func setStoredPreferredInput(_ device: InputDevice) {
        storedPreferredUID = device.uid
        storedPreferredName = device.displayName
    }

    private func clearStoredPreferredInput() {
        storedPreferredUID = nil
        storedPreferredName = nil
    }

    private func currentUnlockedRow(_ device: InputDevice) -> InputLockRowState {
        InputLockRowState(
            id: "current:\(device.uid)",
            role: .current,
            uid: device.uid,
            deviceName: device.displayName,
            isLocked: false,
            isOnline: true,
            isCurrent: true,
            lockAnimationDeadline: pendingLockAnimation?.uid == device.uid ? pendingLockAnimation?.deadline : nil,
            lockAnimationDuration: pendingLockAnimation?.uid == device.uid ? LockTiming.lockAnimationDuration : nil,
            countdownDeadline: nil,
            countdownDuration: nil
        )
    }

    private func storedPreferredSnapshot() -> ReleasedLockRow? {
        guard let uid = storedPreferredUID,
              let name = storedPreferredName else {
            return nil
        }

        return ReleasedLockRow(
            uid: uid,
            name: devices.first(where: { $0.uid == uid })?.displayName ?? name,
            wasOnline: devices.contains { $0.uid == uid }
        )
    }

    private func lockInput(_ device: InputDevice, replacing previous: ReleasedLockRow?) {
        let shouldSwitchToLockedDevice = currentDevice?.uid != device.uid

        if let previous,
           previous.uid != device.uid {
            showReleasedLockRow(previous)
        } else {
            releasedLockRow = nil
            releasedRowWorkItem?.cancel()
            releasedRowWorkItem = nil
        }

        setStoredPreferredInput(device)
        pendingLockChoice = nil
        cancelManualRelock()

        if shouldSwitchToLockedDevice {
            pendingSwitchBackUID = device.uid

            do {
                try audioManager.setDefaultInputDevice(device.id)
                errorMessage = nil
            } catch {
                pendingSwitchBackUID = nil
                errorMessage = error.localizedDescription
            }
        }

        updateInputLockState()
    }

    private func beginLockAnimation(for device: InputDevice, replacing previous: ReleasedLockRow?) {
        let deadline = Date().addingTimeInterval(LockTiming.lockAnimationDuration)
        pendingLockAnimation = PendingLockAnimation(
            uid: device.uid,
            previous: previous,
            deadline: deadline
        )
        lockAnimationWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishLockAnimation(for: device.uid)
            }
        }

        lockAnimationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + LockTiming.lockAnimationDuration, execute: workItem)
        updateInputLockState()
    }

    private func finishLockAnimation(for uid: String) {
        guard let animation = pendingLockAnimation,
              animation.uid == uid else {
            return
        }

        pendingLockAnimation = nil
        lockAnimationWorkItem = nil

        guard let device = devices.first(where: { $0.uid == uid }) else {
            updateInputLockState()
            return
        }

        lockInput(device, replacing: animation.previous)
    }

    private func unlockInput(_ row: InputLockRowState) {
        guard storedPreferredUID == row.uid else { return }

        let shouldShowReleasedRow = row.role != .current || row.isCurrent == false
        let releasedRow = ReleasedLockRow(
            uid: row.uid ?? "",
            name: row.deviceName,
            wasOnline: row.isOnline
        )

        clearStoredPreferredInput()
        pendingLockChoice = nil
        cancelManualRelock()
        cancelLockAnimation()

        if shouldShowReleasedRow {
            showReleasedLockRow(releasedRow)
        } else {
            releasedLockRow = nil
            releasedRowWorkItem?.cancel()
            releasedRowWorkItem = nil
        }

        updateInputLockState()
    }

    private func showReleasedLockRow(_ row: ReleasedLockRow) {
        releasedLockRow = row
        releasedRowWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.releasedLockRow?.uid == row.uid else {
                    return
                }

                self.releasedLockRow = nil
                self.updateInputLockState()
            }
        }
        releasedRowWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + LockTiming.releasedRowDuration, execute: workItem)
    }

    private func scheduleManualRelock(at deadline: Date) {
        manualRelockWorkItem?.cancel()

        let delay = max(deadline.timeIntervalSinceNow, 0)
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.relockStoredInputAfterManualWindow()
            }
        }

        manualRelockWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelManualRelock() {
        manualRelockWorkItem?.cancel()
        manualRelockWorkItem = nil
    }

    private func cancelLockAnimation() {
        lockAnimationWorkItem?.cancel()
        lockAnimationWorkItem = nil
        pendingLockAnimation = nil
    }

    private func relockStoredInputAfterManualWindow() {
        guard inputLockIsEnabled,
              let choice = pendingLockChoice,
              storedPreferredUID == choice.previousUID,
              let lockedDevice = devices.first(where: { $0.uid == choice.previousUID }) else {
            pendingLockChoice = nil
            updateInputLockState()
            return
        }

        pendingLockChoice = nil
        pendingSwitchBackUID = lockedDevice.uid

        do {
            try audioManager.setDefaultInputDevice(lockedDevice.id)
            errorMessage = nil
        } catch {
            pendingSwitchBackUID = nil
            errorMessage = error.localizedDescription
        }

        refresh()
    }

    private func switchBack(to preferredDevice: InputDevice, from currentDevice: InputDevice) {
        pendingSwitchBackUID = preferredDevice.uid

        do {
            try audioManager.setDefaultInputDevice(preferredDevice.id)
            errorMessage = nil
            PreferredInputHUD.shared.show(
                deviceName: preferredDevice.displayName,
                detail: NSLocalizedString("Currently Locked", comment: "HUD lock status"),
                stackBelowNativeHUD: currentDevice.mayTriggerNativeRouteHUD,
                unlock: { [weak self] in
                    self?.unlockInputFromHUD()
                },
                lock: { [weak self] in
                    self?.lockInputFromHUD(deviceUID: preferredDevice.uid)
                }
            )
        } catch {
            pendingSwitchBackUID = nil
            errorMessage = error.localizedDescription
        }
    }

    private func unlockInputFromHUD() {
        clearStoredPreferredInput()
        pendingLockChoice = nil
        pendingSwitchBackUID = nil
        cancelManualRelock()
        cancelLockAnimation()
        updateInputLockState()
    }

    private func lockInputFromHUD(deviceUID: String) {
        guard let device = devices.first(where: { $0.uid == deviceUID }) else {
            return
        }

        lockInput(device, replacing: nil)
    }

    private func enforceStoredInputLockIfNeeded() {
        guard inputLockIsEnabled,
              pendingLockChoice == nil,
              pendingManualSelectionUID == nil,
              pendingSwitchBackUID == nil,
              let preferredUID = storedPreferredUID,
              let preferredDevice = devices.first(where: { $0.uid == preferredUID }),
              let currentDevice,
              currentDevice.uid != preferredUID else {
            return
        }

        switchBack(to: preferredDevice, from: currentDevice)
    }

    private func handleVolumeWriteResult(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            errorMessage = nil
        case let .failure(error):
            errorMessage = error.localizedDescription
            refresh()
        }
    }

    #if DEBUG
    private func installDebugHUDTrigger() {
        debugHUDObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AudioInputLocker.ShowPreferredInputHUD"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let deviceName = notification.userInfo?["deviceName"] as? String
            let detail = notification.userInfo?["detail"] as? String

            Task { @MainActor [weak self] in
                let device = self?.currentDevice

                PreferredInputHUD.shared.show(
                    deviceName: deviceName ?? device?.displayName ?? "Wireless Mic Rx",
                    detail: detail ?? NSLocalizedString("Currently Locked", comment: "HUD lock status"),
                    stackBelowNativeHUD: false,
                    unlock: { [weak self] in
                        self?.unlockInputFromHUD()
                    },
                    lock: { [weak self] in
                        guard let uid = self?.currentDevice?.uid else { return }
                        self?.lockInputFromHUD(deviceUID: uid)
                    }
                )
            }
        }
    }
    #endif
}

@MainActor
private final class PreferredInputHUD {
    static let shared = PreferredInputHUD()

    private var panel: PreferredInputHUDPanel?
    private var hideWorkItem: DispatchWorkItem?
    private var pendingShowWorkItem: DispatchWorkItem?
    private var stackBelowNativeHUD = false
    private var isPointerInside = false
    private var unlockAction: (() -> Void)?
    private var lockAction: (() -> Void)?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    private enum Layout {
        static let standaloneGapBelowMenuBar: CGFloat = 12
        static let stackedGapBelowNativeCapsule: CGFloat = 5
        static let screenEdgeInset: CGFloat = 6
        static let topScreenEdgeInset: CGFloat = 0
    }

    private enum Timing {
        static let initialVisibleDuration: TimeInterval = 4.2
        static let hoverExitVisibleDuration: TimeInterval = 0.8
        static let unlockConfirmationDuration: TimeInterval = 1.4
    }

    func show(
        deviceName: String,
        detail: String,
        stackBelowNativeHUD: Bool,
        unlock: @escaping () -> Void,
        lock: @escaping () -> Void
    ) {
        pendingShowWorkItem?.cancel()
        hideWorkItem?.cancel()
        self.stackBelowNativeHUD = stackBelowNativeHUD
        isPointerInside = false
        unlockAction = unlock
        lockAction = lock

        let workItem = DispatchWorkItem { [weak self] in
            self?.showNow(deviceName: deviceName, detail: detail)
        }
        pendingShowWorkItem = workItem

        let delay: TimeInterval = stackBelowNativeHUD ? 0.18 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func showNow(deviceName: String, detail: String) {
        let panel = panel ?? makePanel()
        let rootView = PreferredInputHUDView(
            deviceName: deviceName,
            detail: detail,
            hoverChanged: { [weak self] isHovered in
                self?.setPointerInside(isHovered)
            },
            close: { [weak self] in
                self?.hide()
            },
            unlock: { [weak self] in
                self?.unlock()
            },
            lock: { [weak self] in
                self?.lock()
            }
        )

        panel.contentView = PreferredInputHUDHostingView(rootView: rootView)
        panel.appearance = nil
        panel.setFrame(frameForHUD(), display: true)
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel
        startMouseTracking()
        updatePanelMouseInteractivity()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        scheduleHide(after: Timing.initialVisibleDuration)
    }

    func dismissForMenuOpening() {
        pendingShowWorkItem?.cancel()
        pendingShowWorkItem = nil
        hide()
    }

    private func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        stopMouseTracking()

        guard let panel,
              panel.isVisible else {
            return
        }

        panel.ignoresMouseEvents = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            guard let panel,
                  panel.alphaValue == 0 else {
                return
            }
            panel.orderOut(nil)
        }
    }

    private func startMouseTracking() {
        stopMouseTracking()

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged]
        ) { [weak self] event in
            self?.updatePanelMouseInteractivity()
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePanelMouseInteractivity()
            }
        }
    }

    private func stopMouseTracking() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func updatePanelMouseInteractivity() {
        guard let panel,
              panel.isVisible else {
            return
        }

        let point = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let acceptsMouse = PreferredInputHUDView.interactiveFrame.contains(point)
        panel.ignoresMouseEvents = !acceptsMouse

        if acceptsMouse {
            if !isPointerInside {
                setPointerInside(true)
            }
        } else if isPointerInside {
            setPointerInside(false)
        }
    }

    private func unlock() {
        unlockAction?()
        hideWorkItem?.cancel()
        hideWorkItem = nil

        if !isPointerInside {
            scheduleHide(after: Timing.unlockConfirmationDuration)
        }
    }

    private func lock() {
        lockAction?()
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func setPointerInside(_ isInside: Bool) {
        isPointerInside = isInside

        if isInside {
            hideWorkItem?.cancel()
            hideWorkItem = nil
        } else {
            scheduleHide(after: Timing.hoverExitVisibleDuration)
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  !self.isPointerInside else {
                return
            }

            self.hide()
        }

        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func makePanel() -> PreferredInputHUDPanel {
        PreferredInputHUDPanel(contentSize: PreferredInputHUDView.windowSize)
    }

    private func frameForHUD() -> NSRect {
        let screen = screenForHUD()
        let screenFrame = screen.frame
        let fallbackAnchor = NSRect(
            x: screen.visibleFrame.maxX - 190,
            y: screen.visibleFrame.maxY,
            width: 32,
            height: screenFrame.maxY - screen.visibleFrame.maxY
        )

        let anchor: NSRect
        if stackBelowNativeHUD,
           let nativeHUDFrame = nativeRouteHUDFrame(on: screenFrame) {
            let nativeCapsuleFrame = nativeCapsuleFrame(from: nativeHUDFrame)
            return frame(
                capsuleMidX: nativeCapsuleFrame.midX,
                capsuleTopY: nativeCapsuleFrame.minY - Layout.stackedGapBelowNativeCapsule,
                on: screenFrame
            )
        } else {
            anchor = statusItemFrame() ?? fallbackAnchor
        }

        return frame(
            capsuleMidX: anchor.midX,
            capsuleTopY: screen.visibleFrame.maxY - Layout.standaloneGapBelowMenuBar,
            on: screenFrame
        )
    }

    private func frame(capsuleMidX: CGFloat, capsuleTopY: CGFloat, on screenFrame: NSRect) -> NSRect {
        let size = PreferredInputHUDView.windowSize
        let visualFrame = PreferredInputHUDView.visualCapsuleFrame

        var x = capsuleMidX - visualFrame.midX
        var y = capsuleTopY - visualFrame.maxY

        x = min(max(x, screenFrame.minX + Layout.screenEdgeInset), screenFrame.maxX - size.width - Layout.screenEdgeInset)
        y = min(max(y, screenFrame.minY + Layout.screenEdgeInset), screenFrame.maxY - size.height - Layout.topScreenEdgeInset)

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func nativeCapsuleFrame(from windowFrame: NSRect) -> NSRect {
        let capsuleSize = PreferredInputHUDView.capsuleSize
        let xInset = max((windowFrame.width - capsuleSize.width) / 2, 0)
        let yInset = max((windowFrame.height - capsuleSize.height) / 2, 0)

        return NSRect(
            x: windowFrame.minX + xInset,
            y: windowFrame.minY + yInset,
            width: min(capsuleSize.width, windowFrame.width),
            height: min(capsuleSize.height, windowFrame.height)
        )
    }

    private func screenForHUD() -> NSScreen {
        if let statusItemFrame = statusItemFrame(),
           let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -8, dy: -8).contains(NSPoint(x: statusItemFrame.midX, y: statusItemFrame.midY)) }) {
            return screen
        }

        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    private func nativeRouteHUDFrame(on screenFrame: NSRect) -> NSRect? {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let frames = windows.compactMap { windowInfo -> NSRect? in
            guard windowInfo[kCGWindowOwnerName as String] as? String == "Control Center",
                  (windowInfo[kCGWindowName as String] as? String ?? "").isEmpty,
                  let layer = windowInfo[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue >= 2000,
                  let alpha = windowInfo[kCGWindowAlpha as String] as? NSNumber,
                  alpha.doubleValue > 0.02,
                  let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let frame = Self.nsRect(fromCGWindowBounds: bounds),
                  (260...560).contains(frame.width),
                  (70...190).contains(frame.height),
                  screenFrame.contains(NSPoint(x: frame.midX, y: frame.midY)) else {
                return nil
            }

            return frame
        }

        return frames.min { $0.minY > $1.minY }
    }

    private func statusItemFrame() -> NSRect? {
        statusItemFrameFromAccessibility() ?? statusItemFrameFromWindowList()
    }

    private func statusItemFrameFromAccessibility() -> NSRect? {
        let appElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var menuBarValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(appElement, kAXExtrasMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBarValue,
              CFGetTypeID(menuBarValue) == AXUIElementGetTypeID() else {
            return nil
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBarValue as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement],
              !children.isEmpty else {
            return nil
        }

        let preferredTitle = "music.microphone"
        let child = children.first {
            axString($0, attribute: kAXTitleAttribute as CFString) == preferredTitle
                || axString($0, attribute: kAXDescriptionAttribute as CFString) == preferredTitle
        } ?? children[0]

        guard let frame = axFrame(child),
              isStatusItemFrame(frame) else {
            return nil
        }

        return frame
    }

    private func statusItemFrameFromWindowList() -> NSRect? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        return windows.compactMap { windowInfo -> NSRect? in
            guard windowInfo[kCGWindowOwnerName as String] as? String == "Control Center",
                  windowInfo[kCGWindowName as String] as? String == bundleIdentifier,
                  let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any] else {
                return nil
            }

            return Self.nsRect(fromCGWindowBounds: bounds)
        }
        .first(where: isStatusItemFrame)
    }

    private func axString(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func axFrame(_ element: AXUIElement) -> NSRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return Self.nsRect(fromTopLeftX: position.x, y: position.y, width: size.width, height: size.height)
    }

    private func isStatusItemFrame(_ frame: NSRect) -> Bool {
        guard frame.width > 0,
              frame.height > 0 else {
            return false
        }

        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.contains { screen in
            screen.frame.insetBy(dx: -8, dy: -8).contains(center)
                && frame.maxY > screen.frame.maxY - 90
                && frame.minY <= screen.frame.maxY + 8
        }
    }

    private static func nsRect(fromCGWindowBounds bounds: [String: Any]) -> NSRect? {
        guard let x = cgFloat(bounds["X"]),
              let y = cgFloat(bounds["Y"]),
              let width = cgFloat(bounds["Width"]),
              let height = cgFloat(bounds["Height"]) else {
            return nil
        }

        return nsRect(fromTopLeftX: x, y: y, width: width, height: height)
    }

    private static func nsRect(fromTopLeftX x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
        let primaryScreenMaxY = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
            ?? NSScreen.screens.map(\.frame.maxY).max()
            ?? 0
        return NSRect(x: x, y: primaryScreenMaxY - y - height, width: width, height: height)
    }

    private static func cgFloat(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber {
            return CGFloat(truncating: number)
        }

        if let value = value as? CGFloat {
            return value
        }

        return nil
    }
}

private final class PreferredInputHUDPanel: NSPanel {
    init(contentSize: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
            .transient
        ]
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct PreferredInputHUDView: View {
    static let windowSize = NSSize(width: 360, height: 136)
    static let capsuleSize = CGSize(width: 235, height: 52)
    static let glassButtonLabelSize = CGSize(width: 225, height: 44)
    static let hudIconSize: CGFloat = 34
    static let textColumnWidth: CGFloat = 128
    static let contentLeadingInset: CGFloat = 15
    static let contentTrailingInset: CGFloat = 13
    static let visualCapsuleFrame = NSRect(
        x: (windowSize.width - capsuleSize.width) / 2,
        y: (windowSize.height - capsuleSize.height) / 2,
        width: capsuleSize.width,
        height: capsuleSize.height
    )
    static let interactiveFrame = visualCapsuleFrame.insetBy(dx: -16, dy: -12)

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovered = false
    @State private var isUnlocked = false

    let deviceName: String
    let detail: String
    let hoverChanged: (Bool) -> Void
    let close: () -> Void
    let unlock: () -> Void
    let lock: () -> Void

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        ZStack {
            capsule
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(Color.clear)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
            hoverChanged(hovering)
        }
    }

    @ViewBuilder
    private var capsule: some View {
        if #available(macOS 26.0, *) {
            ZStack {
                glassButtonCapsule
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                hudContent
                    .frame(width: Self.capsuleSize.width, height: Self.capsuleSize.height)
            }
            .frame(width: Self.capsuleSize.width, height: Self.capsuleSize.height)
            .overlay {
                capsuleRimHighlight
            }
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(alignment: .topLeading) {
                closeButton
            }
        } else {
            hudContent
                .frame(width: Self.capsuleSize.width, height: Self.capsuleSize.height)
                .background(fallbackBackground)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(isDark ? Color.white.opacity(0.15) : Color.white.opacity(0.78), lineWidth: isDark ? 0.6 : 0.7)
                }
                .shadow(color: Color.black.opacity(isDark ? 0.38 : 0.18), radius: isDark ? 13 : 16, x: 0, y: isDark ? 7.5 : 9)
                .shadow(color: Color.white.opacity(isDark ? 0.03 : 0.62), radius: 9, x: 0, y: -1.5)
                .overlay(alignment: .topLeading) {
                    closeButton
                }
        }
    }

    private var hudContent: some View {
        ZStack {
            textContent
                .frame(width: Self.textColumnWidth)

            HStack {
                PreferredInputHUDIcon(size: Self.hudIconSize)
                    .frame(width: Self.hudIconSize, height: Self.hudIconSize)

                Spacer(minLength: 0)

                lockButton
            }
            .padding(.leading, Self.contentLeadingInset)
            .padding(.trailing, Self.contentTrailingInset)
        }
    }

    private var textContent: some View {
        VStack(alignment: .center, spacing: 0) {
            MarqueeText(
                deviceName,
                font: .system(size: 13, weight: .semibold),
                foregroundColor: isDark ? Color.white : Color.black,
                height: 16,
                alignment: .center
            )
            .frame(maxWidth: .infinity, alignment: .center)

            Text(detail)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(isDark ? Color.white.opacity(0.72) : Color.black.opacity(0.60))
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var lockButton: some View {
        Button(action: toggleLockState) {
            ZStack {
                Circle()
                    .fill(lockButtonBackground)

                Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(lockButtonForeground)
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(
            isUnlocked
                ? NSLocalizedString("Lock input device", comment: "HUD lock button tooltip")
                : NSLocalizedString("Unlock input device", comment: "HUD lock button tooltip")
        )
    }

    private var capsuleRimHighlight: some View {
        ZStack {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(isDark ? 0.26 : 0.58), lineWidth: 1.05)
                .blur(radius: 0.35)
                .offset(y: -0.2)

            Capsule(style: .continuous)
                .strokeBorder(capsuleRimGradient, lineWidth: isDark ? 0.95 : 1.05)

            Capsule(style: .continuous)
                .inset(by: 1.15)
                .strokeBorder(Color.white.opacity(isDark ? 0.12 : 0.32), lineWidth: 0.55)
        }
        .allowsHitTesting(false)
    }

    private var capsuleRimGradient: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [
                    Color.white.opacity(0.42),
                    Color.white.opacity(0.24),
                    Color.white.opacity(0.10),
                    Color.black.opacity(0.16)
                ]
                : [
                    Color.white.opacity(0.96),
                    Color.white.opacity(0.82),
                    Color.white.opacity(0.34),
                    Color.black.opacity(0.07)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @available(macOS 26.0, *)
    private var glassButtonCapsule: some View {
        Button(action: {}) {
            Color.clear
                .frame(width: Self.glassButtonLabelSize.width, height: Self.glassButtonLabelSize.height)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .frame(width: Self.capsuleSize.width, height: Self.capsuleSize.height)
        .shadow(color: Color.black.opacity(isDark ? 0.26 : 0.10), radius: isDark ? 8 : 6.5, x: 0, y: isDark ? 5 : 3.5)
        .shadow(color: Color.black.opacity(isDark ? 0.14 : 0.055), radius: 1.6, x: 0, y: 0.8)
    }

    private func toggleLockState() {
        if isUnlocked {
            lock()

            withAnimation(.easeInOut(duration: 0.18)) {
                isUnlocked = false
            }
        } else {
            unlock()

            withAnimation(.easeInOut(duration: 0.18)) {
                isUnlocked = true
            }
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        if isHovered {
            Button(action: close) {
                ZStack {
                    Circle()
                        .fill(Color(nsColor: .labelColor).opacity(isDark ? 0.18 : 0.10))

                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                .frame(width: 18, height: 18)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: -4, y: -2)
            .transition(.opacity.combined(with: .scale(scale: 0.88)))
            .help(NSLocalizedString("Close", comment: "HUD close button tooltip"))
        }
    }

    private var lockButtonBackground: Color {
        if isUnlocked {
            return Color(nsColor: .labelColor).opacity(isDark ? 0.18 : 0.115)
        }

        return Color(nsColor: .systemBrown)
    }

    private var lockButtonForeground: Color {
        isUnlocked ? Color(nsColor: .secondaryLabelColor) : .white
    }

    @ViewBuilder
    private var fallbackBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(isDark ? Color(red: 0.12, green: 0.12, blue: 0.12) : Color(red: 0.94, green: 0.94, blue: 0.94))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.055),
                                    Color.black.opacity(0.10)
                                ]
                                : [
                                    Color.white.opacity(0.84),
                                    Color.white.opacity(0.58),
                                    Color.white.opacity(0.44)
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }
}

private struct MarqueeText: View {
    let text: String
    let font: Font
    let foregroundColor: Color
    let height: CGFloat
    let alignment: Alignment

    @State private var measuredTextWidth: CGFloat = 0

    private let spacing: CGFloat = 22
    private let pixelsPerSecond: CGFloat = 24

    init(_ text: String, font: Font, foregroundColor: Color, height: CGFloat, alignment: Alignment = .leading) {
        self.text = text
        self.font = font
        self.foregroundColor = foregroundColor
        self.height = height
        self.alignment = alignment
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let shouldScroll = measuredTextWidth > availableWidth

            ZStack(alignment: shouldScroll ? .leading : alignment) {
                if shouldScroll {
                    TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                        let travelDistance = measuredTextWidth + spacing
                        let duration = max(3.2, Double(travelDistance / pixelsPerSecond))
                        let progress = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: duration) / duration

                        HStack(spacing: spacing) {
                            textView
                            textView
                        }
                        .offset(x: -travelDistance * progress)
                    }
                } else {
                    textView
                }
            }
            .frame(width: availableWidth, height: height, alignment: shouldScroll ? .leading : alignment)
            .clipped()
        }
        .frame(height: height)
        .background(measurementView)
    }

    private var textView: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var measurementView: some View {
        textView
            .hidden()
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: MarqueeTextWidthPreferenceKey.self, value: proxy.size.width)
                }
            }
            .onPreferenceChange(MarqueeTextWidthPreferenceKey.self) { width in
                measuredTextWidth = width
            }
    }
}

private struct MarqueeTextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PreferredInputHUDIcon: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = NSImage(named: "HUDMicrophone") ?? NSImage(named: "HUDMicrophone.png") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "music.microphone")
                    .font(.system(size: size * 0.70, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .shadow(color: .black.opacity(0.14), radius: 1.4, x: 0.35, y: 0.9)
    }
}

private final class PreferredInputHUDHostingView: NSHostingView<PreferredInputHUDView> {
    required init(rootView: PreferredInputHUDView) {
        super.init(rootView: rootView)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard PreferredInputHUDView.interactiveFrame.contains(point) else {
            return nil
        }

        return super.hitTest(point)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configure()
    }

    private func configure() {
        frame = NSRect(origin: .zero, size: PreferredInputHUDView.windowSize)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
