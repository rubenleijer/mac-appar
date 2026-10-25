import AudioToolbox
import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let transportType: UInt32

    var isWireless: Bool {
        transportType == kAudioDeviceTransportTypeBluetooth || transportType == kAudioDeviceTransportTypeBluetoothLE
            || transportType == kAudioDeviceTransportTypeAirPlay
    }

    var symbolName: String {
        let lowered = name.lowercased()
        switch transportType {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            if lowered.contains("airpods max") { return "airpodsmax" }
            if lowered.contains("airpods pro") { return "airpodspro" }
            if lowered.contains("airpods") { return "airpods" }
            if lowered.contains("beats") { return "beats.headphones" }
            if lowered.contains("homepod") { return "homepod.fill" }
            return lowered.contains("speaker") ? "hifispeaker.fill" : "headphones"
        case kAudioDeviceTransportTypeBuiltIn:
            return lowered.contains("head") ? "headphones" : "laptopcomputer"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "display"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt:
            return "hifispeaker.fill"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
            return "waveform"
        default:
            return "speaker.wave.2.fill"
        }
    }
}

/// System output volume, mute and output device selection via Core Audio.
@MainActor @Observable
final class AudioService {
    private(set) var volume: Double = 0
    private(set) var isMuted = false
    private(set) var canSetVolume = false
    private(set) var devices: [AudioOutputDevice] = []
    private(set) var currentDeviceID: AudioDeviceID = 0

    var currentDevice: AudioOutputDevice? { devices.first { $0.id == currentDeviceID } }

    /// Volume or mute changed by something other than this app's sliders.
    @ObservationIgnored var onExternalVolumeChange: (() -> Void)?
    @ObservationIgnored var onOutputDeviceChange: ((AudioOutputDevice) -> Void)?

    @ObservationIgnored private var ignoreChangesUntil = Date.distantPast
    @ObservationIgnored private var observedDevice: AudioDeviceID = 0
    @ObservationIgnored private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func start() {
        reloadDevices()
        updateDefaultDevice(announce: false)
        addListener(to: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            self?.updateDefaultDevice(announce: true)
        }
        addListener(to: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices) { [weak self] in
            self?.reloadDevices()
        }
    }

    // MARK: Volume

    @discardableResult
    func setVolume(_ value: Double) -> Bool {
        let value = min(max(value, 0), 1)
        ignoreChangesUntil = Date().addingTimeInterval(0.4)
        var scalar = Float32(value)
        let succeeded = Self.set(currentDeviceID, kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                 scope: kAudioDevicePropertyScopeOutput, &scalar)
        if succeeded { volume = value }
        // Like the system: dragging the volume up unmutes, down to zero mutes.
        if isMuted && value > 0 { setMuted(false) }
        return succeeded
    }

    /// Steps the volume the way the keyboard does (1/16, or 1/64 with ⌥⇧).
    /// Returns false when the device refused, so the key can go to the system instead.
    @discardableResult
    func stepVolume(by steps: Int, fine: Bool) -> Bool {
        readVolume()
        let divisions = fine ? 64.0 : 16.0
        let target = min(max(((volume * divisions).rounded() + Double(steps)) / divisions, 0), 1)
        let succeeded = setVolume(target)
        if target <= 0 { setMuted(true) }
        return succeeded || target <= 0
    }

    func setMuted(_ muted: Bool) {
        ignoreChangesUntil = Date().addingTimeInterval(0.4)
        var flag: UInt32 = muted ? 1 : 0
        if Self.set(currentDeviceID, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, &flag) {
            isMuted = muted
        }
    }

    func toggleMute() { setMuted(!isMuted) }

    // MARK: Devices

    func selectDevice(_ device: AudioOutputDevice) {
        var id = device.id
        _ = Self.set(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, &id)
    }

    private func reloadDevices() {
        devices = Self.outputDeviceIDs().compactMap { id in
            guard let name = Self.string(id, kAudioObjectPropertyName), !name.hasPrefix("CADefaultDeviceAggregate") else { return nil }
            let transport: UInt32 = Self.get(id, kAudioDevicePropertyTransportType) ?? 0
            return AudioOutputDevice(id: id, name: name, transportType: transport)
        }
        .sorted { lhs, rhs in
            let lhsBuiltIn = lhs.transportType == kAudioDeviceTransportTypeBuiltIn
            let rhsBuiltIn = rhs.transportType == kAudioDeviceTransportTypeBuiltIn
            if lhsBuiltIn != rhsBuiltIn { return lhsBuiltIn }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func updateDefaultDevice(announce: Bool) {
        let id: AudioDeviceID = Self.get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        let changed = id != currentDeviceID
        currentDeviceID = id
        if !devices.contains(where: { $0.id == id }) { reloadDevices() }
        observe(device: id)
        readVolume()
        if changed, announce, let device = currentDevice { onOutputDeviceChange?(device) }
    }

    private func readVolume() {
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        var settable: DarwinBoolean = false
        canSetVolume = AudioObjectHasProperty(currentDeviceID, &address)
            && AudioObjectIsPropertySettable(currentDeviceID, &address, &settable) == noErr && settable.boolValue
        let scalar: Float32 = Self.get(currentDeviceID, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput) ?? 0
        let mute: UInt32 = Self.get(currentDeviceID, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput) ?? 0
        volume = Double(scalar)
        isMuted = mute != 0
    }

    private func observe(device: AudioDeviceID) {
        guard device != observedDevice else { return }
        for (address, block) in deviceListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(observedDevice, &address, .main, block)
        }
        deviceListeners.removeAll()
        observedDevice = device
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            let block = addListener(to: device, selector: selector, scope: kAudioDevicePropertyScopeOutput) { [weak self] in
                guard let self else { return }
                let before = (self.volume, self.isMuted)
                self.readVolume()
                let changed = abs(before.0 - self.volume) > 0.001 || before.1 != self.isMuted
                if changed, Date() > self.ignoreChangesUntil { self.onExternalVolumeChange?() }
            }
            if let block {
                deviceListeners.append((Self.address(selector, scope: kAudioDevicePropertyScopeOutput), block))
            }
        }
    }

    @discardableResult
    private func addListener(to object: AudioObjectID, selector: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                             handler: @escaping @MainActor () -> Void) -> AudioObjectPropertyListenerBlock? {
        var address = Self.address(selector, scope: scope)
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { handler() }
        }
        return AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr ? block : nil
    }

    // MARK: Core Audio helpers

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func get<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        var address = address(selector, scope: scope)
        guard object != 0, AudioObjectHasProperty(object, &address) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }

    private static func set<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ value: inout T) -> Bool {
        var address = address(selector, scope: scope)
        guard object != 0, AudioObjectHasProperty(object, &address) else { return false }
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        } == noErr
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        guard withUnsafeMutablePointer(to: &value, {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func outputDeviceIDs() -> [AudioDeviceID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { id in
            var streams = Self.address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            var streamSize: UInt32 = 0
            let hidden: UInt32 = get(id, kAudioDevicePropertyIsHidden) ?? 0
            return hidden == 0
                && AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr
                && streamSize > 0
        }
    }
}
