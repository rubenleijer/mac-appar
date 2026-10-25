import Foundation
import IOKit
import IOKit.ps

/// Chip, battery and SSD temperatures on Apple silicon, from the same HID temperature sensors
/// Activity Monitor-style tools read (IOHIDEventSystemClient, private but needs no permission).
@MainActor @Observable
final class ThermalService {
    struct Reading: Equatable {
        /// Hottest CPU/GPU die sensor.
        var cpu: Double?
        var gpu: Double?
        var battery: Double?
        var ssd: Double?
        var thermalState: ProcessInfo.ThermalState
    }

    struct Battery: Equatable {
        var percent: Int
        var isCharging: Bool
        var isOnPower: Bool
        /// Minutes until empty (on battery) or full (charging), when macOS knows.
        var minutesLeft: Int?

        var symbol: String {
            if isCharging { return "battery.100percent.bolt" }
            switch percent {
            case ..<13: return "battery.0percent"
            case ..<38: return "battery.25percent"
            case ..<63: return "battery.50percent"
            case ..<88: return "battery.75percent"
            default: return "battery.100percent"
            }
        }

        var timeText: String? {
            guard let minutesLeft, minutesLeft > 0 else { return nil }
            let text = minutesLeft >= 60 ? "\(minutesLeft / 60) h \(minutesLeft % 60) min" : "\(minutesLeft) min"
            return isCharging ? "\(text) to full" : "\(text) left"
        }
    }

    private(set) var reading: Reading?
    /// Nil on a Mac without a battery.
    private(set) var battery: Battery?
    private(set) var isAvailable = false
    /// The last few CPU readings, for the little graph.
    private(set) var history: [Double] = []

    @ObservationIgnored var onHot: (() -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wasHot = false
    @ObservationIgnored private let sensors = HIDTemperatureSensors()
    @ObservationIgnored private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 1
    }

    func stop() {
        timer?.invalidate()
    }

    var cpuText: String { reading?.cpu.map { "\(Int($0.rounded()))°" } ?? "–" }

    var thermalTitle: String {
        switch reading?.thermalState ?? .nominal {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Very hot"
        @unknown default: "Unknown"
        }
    }

    private func refresh() {
        let next = Self.readBattery()
        if next != battery { battery = next }
        let sensors = self.sensors
        Task.detached(priority: .utility) {
            let values = sensors.read()
            await MainActor.run { self.apply(values) }
        }
    }

    /// The internal battery, from IOKit's power sources (public API).
    private static func readBattery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let onPower = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = charging ? description[kIOPSTimeToFullChargeKey] as? Int : description[kIOPSTimeToEmptyKey] as? Int
            return Battery(percent: Int((Double(current) / Double(maximum) * 100).rounded()),
                           isCharging: charging, isOnPower: onPower, minutesLeft: minutes)
        }
        return nil
    }

    private func apply(_ values: [(name: String, value: Double)]) {
        func hottest(_ match: (String) -> Bool) -> Double? {
            values.filter { match($0.name.lowercased()) && $0.value > 5 && $0.value < 130 }.map(\.value).max()
        }
        let cpu = hottest { $0.contains("tdie") || $0.contains("acc mtr") || $0.contains("pacc") || $0.contains("eacc") }
            ?? hottest { $0.contains("soc") || $0.contains("tdev") }
        let gpu = hottest { $0.contains("gpu") }
        let battery = hottest { $0.contains("battery") || $0.contains("gas gauge") }
        let ssd = hottest { $0.contains("nand") }
        let next = Reading(cpu: cpu, gpu: gpu, battery: battery, ssd: ssd,
                           thermalState: ProcessInfo.processInfo.thermalState)
        isAvailable = cpu != nil
        if next != reading { reading = next }
        if let cpu {
            history.append(cpu)
            if history.count > 40 { history.removeFirst(history.count - 40) }
        }

        let hot = (cpu ?? 0) >= Double(settings.hotThreshold) || next.thermalState == .serious || next.thermalState == .critical
        if hot && !wasHot && settings.warnWhenHot { onHot?() }
        // A little hysteresis, so a chip hovering at the limit doesn't warn every few seconds.
        if hot { wasHot = true } else if (cpu ?? 0) < Double(settings.hotThreshold) - 8 { wasHot = false }
    }
}

/// Reads every temperature sensor the HID event system exposes. Thread-safe to call off main.
final class HIDTemperatureSensors: @unchecked Sendable {
    // Plain pointers in, CF objects out – the shapes C-convention function types accept.
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (UnsafeMutableRawPointer, CFDictionary) -> Void
    private typealias CopyServices = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (UnsafeMutableRawPointer, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEvent = @convention(c) (UnsafeMutableRawPointer, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloat = @convention(c) (UnsafeMutableRawPointer, Int32) -> Double

    private let lock = NSLock()
    private var client: AnyObject?
    private var copyServices: CopyServices?
    private var copyProperty: CopyProperty?
    private var copyEvent: CopyEvent?
    private var getFloat: GetFloat?

    private static let temperatureEvent: Int64 = 15 // kIOHIDEventTypeTemperature

    init() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let create = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let setMatching = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let services = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let property = dlsym(handle, "IOHIDServiceClientCopyProperty"),
              let event = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let float = dlsym(handle, "IOHIDEventGetFloatValue") else { return }
        copyServices = unsafeBitCast(services, to: CopyServices.self)
        copyProperty = unsafeBitCast(property, to: CopyProperty.self)
        copyEvent = unsafeBitCast(event, to: CopyEvent.self)
        getFloat = unsafeBitCast(float, to: GetFloat.self)
        guard let made = unsafeBitCast(create, to: Create.self)(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        // Apple's vendor page / temperature usage: the chip's thermal sensors.
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        unsafeBitCast(setMatching, to: SetMatching.self)(Unmanaged.passUnretained(made).toOpaque(), matching)
        client = made
    }

    func read() -> [(name: String, value: Double)] {
        lock.lock()
        defer { lock.unlock() }
        guard let client, let copyServices, let copyProperty, let copyEvent, let getFloat,
              let services = copyServices(Unmanaged.passUnretained(client).toOpaque())?.takeRetainedValue() as? [AnyObject]
        else { return [] }
        var result: [(String, Double)] = []
        for service in services {
            let servicePointer = Unmanaged.passUnretained(service).toOpaque()
            guard let name = copyProperty(servicePointer, "Product" as CFString)?.takeRetainedValue() as? String,
                  let event = copyEvent(servicePointer, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { continue }
            let value = getFloat(Unmanaged.passUnretained(event).toOpaque(), Int32(Self.temperatureEvent << 16))
            if value.isFinite { result.append((name, value)) }
        }
        return result
    }
}
