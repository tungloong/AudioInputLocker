import CoreAudio
import Foundation

enum CoreAudioInputError: LocalizedError {
    case osStatus(OSStatus, String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .osStatus(status, operation):
            return "\(operation) failed with OSStatus \(status)."
        case let .unavailable(message):
            return message
        }
    }
}

final class CoreAudioInputManager {
    private struct ListenerRegistration {
        let objectID: AudioObjectID
        var address: AudioObjectPropertyAddress
        let queue: DispatchQueue
        let block: AudioObjectPropertyListenerBlock
    }

    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    private let listenerQueue = DispatchQueue(label: "InputSoundMenu.CoreAudioListeners")
    private var systemListeners: [ListenerRegistration] = []
    private var volumeListeners: [ListenerRegistration] = []
    private var changeHandler: (() -> Void)?

    deinit {
        stopMonitoring()
    }

    func loadInputDevices() throws -> [InputDevice] {
        let defaultDeviceID = try? defaultInputDeviceID()

        return try allDeviceIDs()
            .compactMap { deviceID -> InputDevice? in
                guard let channelCount = try? inputChannelCount(for: deviceID), channelCount > 0 else {
                    return nil
                }

                let writableVolumeElements = volumeElements(
                    for: deviceID,
                    maxChannels: channelCount,
                    requireSettable: true
                )
                let readableVolumeElements = volumeElements(
                    for: deviceID,
                    maxChannels: channelCount,
                    requireSettable: false
                )

                let isDefault = deviceID == defaultDeviceID
                let supportsInputVolume = !writableVolumeElements.isEmpty
                let inputVolume = averageVolume(
                    for: deviceID,
                    elements: supportsInputVolume ? writableVolumeElements : readableVolumeElements
                )

                return InputDevice(
                    id: deviceID,
                    uid: stringProperty(kAudioDevicePropertyDeviceUID, for: deviceID) ?? "\(deviceID)",
                    name: stringProperty(kAudioObjectPropertyName, for: deviceID) ?? "Input Device",
                    manufacturer: stringProperty(kAudioObjectPropertyManufacturer, for: deviceID) ?? "",
                    modelUID: stringProperty(kAudioDevicePropertyModelUID, for: deviceID) ?? "",
                    transportType: integerProperty(kAudioDevicePropertyTransportType, for: deviceID) ?? 0,
                    inputChannels: channelCount,
                    isDefault: isDefault,
                    supportsInputVolume: supportsInputVolume,
                    inputVolume: inputVolume
                )
            }
    }

    func defaultInputDeviceID() throws -> AudioDeviceID {
        var address = propertyAddress(
            selector: kAudioHardwarePropertyDefaultInputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        try check(
            AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &deviceID),
            "Read default input device"
        )

        guard deviceID != kAudioObjectUnknown else {
            throw CoreAudioInputError.unavailable("No default input device is available.")
        }

        return deviceID
    }

    func setDefaultInputDevice(_ deviceID: AudioDeviceID) throws {
        var address = propertyAddress(
            selector: kAudioHardwarePropertyDefaultInputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )
        var mutableDeviceID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        try check(
            AudioObjectSetPropertyData(systemObjectID, &address, 0, nil, dataSize, &mutableDeviceID),
            "Set default input device"
        )
    }

    func inputVolume(for deviceID: AudioDeviceID) throws -> Float? {
        let channels = try inputChannelCount(for: deviceID)
        let writableElements = volumeElements(for: deviceID, maxChannels: channels, requireSettable: true)
        let readableElements = volumeElements(for: deviceID, maxChannels: channels, requireSettable: false)
        return averageVolume(for: deviceID, elements: writableElements.isEmpty ? readableElements : writableElements)
    }

    func setInputVolume(_ volume: Float, for deviceID: AudioDeviceID) throws {
        let channels = try inputChannelCount(for: deviceID)
        let elements = volumeElements(for: deviceID, maxChannels: channels, requireSettable: true)

        guard !elements.isEmpty else {
            throw CoreAudioInputError.unavailable("This input device does not expose a writable input volume.")
        }

        var clampedVolume = min(max(volume, 0), 1)
        let dataSize = UInt32(MemoryLayout<Float32>.size)

        for element in elements {
            var address = propertyAddress(
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeInput,
                element: element
            )
            try check(
                AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &clampedVolume),
                "Set input volume"
            )
        }
    }

    func startMonitoring(_ onChange: @escaping () -> Void) {
        stopMonitoring()
        changeHandler = onChange

        addSystemListener(selector: kAudioHardwarePropertyDevices)
        addSystemListener(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    func stopMonitoring() {
        removeListeners(systemListeners)
        removeListeners(volumeListeners)
        systemListeners.removeAll()
        volumeListeners.removeAll()
        changeHandler = nil
    }

    func monitorVolume(for deviceID: AudioDeviceID?) {
        removeListeners(volumeListeners)
        volumeListeners.removeAll()

        guard let deviceID,
              let channels = try? inputChannelCount(for: deviceID) else {
            return
        }

        let elements = volumeElements(for: deviceID, maxChannels: channels, requireSettable: false)
        for element in elements {
            var address = propertyAddress(
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeInput,
                element: element
            )

            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.emitChange()
            }

            if AudioObjectAddPropertyListenerBlock(deviceID, &address, listenerQueue, block) == noErr {
                volumeListeners.append(
                    ListenerRegistration(
                        objectID: deviceID,
                        address: address,
                        queue: listenerQueue,
                        block: block
                    )
                )
            }
        }
    }

    private func allDeviceIDs() throws -> [AudioDeviceID] {
        var address = propertyAddress(
            selector: kAudioHardwarePropertyDevices,
            scope: kAudioObjectPropertyScopeGlobal
        )
        var dataSize: UInt32 = 0

        try check(
            AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize),
            "Read audio device list size"
        )

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var devices = [AudioDeviceID](repeating: 0, count: count)
        try devices.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw CoreAudioInputError.unavailable("Unable to allocate the audio device list.")
            }
            try check(
                AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, baseAddress),
                "Read audio device list"
            )
        }

        return devices
    }

    private func inputChannelCount(for deviceID: AudioDeviceID) throws -> Int {
        var address = propertyAddress(
            selector: kAudioDevicePropertyStreamConfiguration,
            scope: kAudioObjectPropertyScopeInput
        )
        var dataSize: UInt32 = 0

        try check(
            AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize),
            "Read input stream configuration size"
        )

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        try check(
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, rawPointer),
            "Read input stream configuration"
        )

        let audioBufferList = rawPointer.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

        return buffers.reduce(0) { total, buffer in
            total + Int(buffer.mNumberChannels)
        }
    }

    private func stringProperty(_ selector: AudioObjectPropertySelector, for objectID: AudioObjectID) -> String? {
        var address = propertyAddress(selector: selector, scope: kAudioObjectPropertyScopeGlobal)
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
        guard status == noErr, let value else { return nil }

        return value.takeRetainedValue() as String
    }

    private func integerProperty(_ selector: AudioObjectPropertySelector, for objectID: AudioObjectID) -> UInt32? {
        var address = propertyAddress(selector: selector, scope: kAudioObjectPropertyScopeGlobal)
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
        guard status == noErr else { return nil }

        return value
    }

    private func volumeElements(
        for deviceID: AudioDeviceID,
        maxChannels: Int,
        requireSettable: Bool
    ) -> [AudioObjectPropertyElement] {
        let mainElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        if hasVolumeProperty(for: deviceID, element: mainElement, requireSettable: requireSettable) {
            return [mainElement]
        }

        guard maxChannels > 0 else { return [] }

        return (1...maxChannels)
            .map(AudioObjectPropertyElement.init)
            .filter { hasVolumeProperty(for: deviceID, element: $0, requireSettable: requireSettable) }
    }

    private func hasVolumeProperty(
        for deviceID: AudioDeviceID,
        element: AudioObjectPropertyElement,
        requireSettable: Bool
    ) -> Bool {
        var address = propertyAddress(
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeInput,
            element: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return false
        }

        guard requireSettable else {
            return true
        }

        var isSettable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        return status == noErr && isSettable.boolValue
    }

    private func averageVolume(for deviceID: AudioDeviceID, elements: [AudioObjectPropertyElement]) -> Float? {
        let volumes = elements.compactMap { element -> Float? in
            var address = propertyAddress(
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeInput,
                element: element
            )
            var volume: Float32 = 0
            var dataSize = UInt32(MemoryLayout<Float32>.size)

            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &volume)
            guard status == noErr else { return nil }

            return volume
        }

        guard !volumes.isEmpty else { return nil }

        return volumes.reduce(0, +) / Float(volumes.count)
    }

    private func addSystemListener(selector: AudioObjectPropertySelector) {
        var address = propertyAddress(selector: selector, scope: kAudioObjectPropertyScopeGlobal)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.emitChange()
        }

        if AudioObjectAddPropertyListenerBlock(systemObjectID, &address, listenerQueue, block) == noErr {
            systemListeners.append(
                ListenerRegistration(
                    objectID: systemObjectID,
                    address: address,
                    queue: listenerQueue,
                    block: block
                )
            )
        }
    }

    private func removeListeners(_ listeners: [ListenerRegistration]) {
        for listener in listeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(
                listener.objectID,
                &address,
                listener.queue,
                listener.block
            )
        }
    }

    private func emitChange() {
        DispatchQueue.main.async { [weak self] in
            self?.changeHandler?()
        }
    }

    private func propertyAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            throw CoreAudioInputError.osStatus(status, operation)
        }
    }
}
