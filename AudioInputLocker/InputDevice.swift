import CoreAudio
import AppKit
import Foundation

struct InputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let manufacturer: String
    let modelUID: String
    let transportType: UInt32
    let inputChannels: Int
    let isDefault: Bool
    let supportsInputVolume: Bool
    let inputVolume: Float?

    var displayName: String {
        name.isEmpty ? NSLocalizedString("Unknown Input Device", comment: "Fallback input device name") : name
    }

    var secondaryText: String? {
        guard !manufacturer.isEmpty else { return nil }
        return manufacturer
    }

    var iconSystemName: String {
        DeviceIconMapper.symbol(for: self)
    }

    var mayTriggerNativeRouteHUD: Bool {
        NativeRouteHUDHeuristic.mayTrigger(for: self)
    }
}

private enum DeviceIconMapper {
    static func symbol(for device: InputDevice) -> String {
        let name = device.name

        if let symbol = appleAudioProductSymbol(for: device) {
            return symbol
        }

        if name.containsAnyCaseInsensitive(["airpods max"]) {
            return availableSymbol(["airpods.max", "airpodsmax"])
        }

        if name.containsAnyCaseInsensitive(["airpods pro"]) {
            return availableSymbol(["airpods.pro", "airpodspro"])
        }

        if name.containsAnyCaseInsensitive(["airpods"]) {
            return "airpods"
        }

        if name.containsAnyCaseInsensitive(["beats"]) {
            return "beats.headphones"
        }

        if name.containsAnyCaseInsensitive(["earpods", "earbud"]) {
            return "earpods"
        }

        if name.containsAnyCaseInsensitive(["iphone"]) || name.containsWordCaseInsensitive("phone") {
            return "iphone"
        }

        if name.containsAnyCaseInsensitive(["ipad"]) {
            return "ipad"
        }

        if name.containsAnyCaseInsensitive(["webcam", "facetime", "camera"]) {
            return "web.camera"
        }

        if name.containsAnyCaseInsensitive(["display", "monitor", "hdmi", "displayport"]) {
            return "display"
        }

        if name.containsAnyCaseInsensitive(["macbook"]) {
            return availableSymbol(["macbook", "macbook.gen2", "laptopcomputer"])
        }

        if name.containsAnyCaseInsensitive(["built-in", "internal"]) {
            return "laptopcomputer"
        }

        if name.containsAnyCaseInsensitive([
            "usb mic",
            "wireless mic",
            "yeti",
            "blue",
            "rode",
            "shure",
            "at2020",
            "scarlett",
            "dji"
        ]) {
            return "mic.fill"
        }

        return transportFallback(for: device.transportType)
    }

    private static func appleAudioProductSymbol(for device: InputDevice) -> String? {
        AppleBluetoothAudioProduct.product(for: device).map { product in
            availableSymbol(product.symbolCandidates)
        }
    }

    private static func transportFallback(for transportType: UInt32) -> String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "headphones"
        case kAudioDeviceTransportTypeUSB:
            return "mic.fill"
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI:
            return "display"
        case kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless:
            return "iphone"
        case kAudioDeviceTransportTypeVirtual:
            return "mic.badge.xmark"
        default:
            return "mic"
        }
    }

    private static func availableSymbol(_ candidates: [String]) -> String {
        candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
            ?? candidates.last
            ?? "mic"
    }
}

private enum NativeRouteHUDHeuristic {
    static func mayTrigger(for device: InputDevice) -> Bool {
        if AppleBluetoothAudioProduct.product(for: device) != nil {
            return true
        }

        switch device.transportType {
        case kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless:
            return true
        default:
            break
        }

        return device.name.containsAnyCaseInsensitive([
            "airpods",
            "beats",
            "earpods",
            "iphone",
            "ipad"
        ]) || device.name.containsWordCaseInsensitive("phone")
    }
}

private enum AppleBluetoothAudioProduct {
    case airPodsMax
    case airPodsPro
    case airPodsGen4
    case airPodsGen3
    case airPods
    case beats

    static func product(for device: InputDevice) -> AppleBluetoothAudioProduct? {
        // Apple Bluetooth audio devices expose their product ID through CoreAudio's model UID.
        guard device.manufacturer.localizedCaseInsensitiveContains("apple"),
              device.transportType == kAudioDeviceTransportTypeBluetooth
                || device.transportType == kAudioDeviceTransportTypeBluetoothLE,
              let productID = device.modelUID.appleBluetoothProductID else {
            return nil
        }

        return AppleBluetoothAudioProduct(productID: productID)
    }

    private init?(productID: UInt32) {
        switch productID {
        case 0x200A, 0x201F, 0x202D:
            self = .airPodsMax
        case 0x200E, 0x2014, 0x2024:
            self = .airPodsPro
        case 0x201B:
            self = .airPodsGen4
        case 0x2013:
            self = .airPodsGen3
        case 0x2002, 0x200F:
            self = .airPods
        case 0x2003, 0x2005, 0x2006, 0x2009, 0x200B, 0x200C, 0x200D,
             0x2010, 0x2011, 0x2012, 0x2016, 0x2017, 0x201A, 0x2025, 0x2026:
            self = .beats
        default:
            return nil
        }
    }

    var symbolCandidates: [String] {
        switch self {
        case .airPodsMax:
            return ["airpods.max", "airpodsmax"]
        case .airPodsPro:
            return ["airpods.pro", "airpodspro"]
        case .airPodsGen4:
            return ["airpods.gen4", "airpods.gen3", "airpods"]
        case .airPodsGen3:
            return ["airpods.gen3", "airpods"]
        case .airPods:
            return ["airpods"]
        case .beats:
            return ["beats.headphones"]
        }
    }
}

private extension String {
    var appleBluetoothProductID: UInt32? {
        let values = split { !$0.isHexDigit }
            .compactMap { UInt32($0, radix: 16) }

        guard values.contains(0x004C) else {
            return nil
        }

        return values.first { value in
            (0x2000...0x20FF).contains(value) || (0x2600...0x26FF).contains(value)
        }
    }

    func containsAnyCaseInsensitive(_ needles: [String]) -> Bool {
        needles.contains { localizedCaseInsensitiveContains($0) }
    }

    func containsWordCaseInsensitive(_ word: String) -> Bool {
        range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", options: [.caseInsensitive, .regularExpression]) != nil
    }
}
