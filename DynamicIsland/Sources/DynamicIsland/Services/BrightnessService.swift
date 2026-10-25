import CoreGraphics
import Foundation

/// Built-in display brightness through the private DisplayServices framework
/// (the same one the brightness keys and Control Center use).
@MainActor @Observable
final class BrightnessService {
    private(set) var brightness: Double = 0
    private(set) var isAvailable = false

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    @ObservationIgnored private var getter: GetBrightness?
    @ObservationIgnored private var setter: SetBrightness?
    @ObservationIgnored private let display: CGDirectDisplayID
    /// The value last written to the display, which trails `brightness` while a ramp runs.
    @ObservationIgnored private var applied: Double = 0
    @ObservationIgnored private var rampTimer: Timer?
    @ObservationIgnored private var rampFrom: Double = 0
    @ObservationIgnored private var rampStart = Date()
    private static let rampDuration: TimeInterval = 0.24

    init() {
        display = Self.builtInDisplay() ?? CGMainDisplayID()
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
           let get = dlsym(handle, "DisplayServicesGetBrightness"),
           let set = dlsym(handle, "DisplayServicesSetBrightness") {
            getter = unsafeBitCast(get, to: GetBrightness.self)
            setter = unsafeBitCast(set, to: SetBrightness.self)
        }
        refresh()
    }

    func refresh() {
        guard let getter else { return }
        guard rampTimer == nil else { return } // mid-ramp, `brightness` already holds the target
        var value: Float = 0
        isAvailable = getter(display, &value) == 0
        if isAvailable {
            brightness = Double(value)
            applied = brightness
        }
    }

    /// Sets the brightness at once (sliders) or eases towards it (keys).
    func setBrightness(_ value: Double, animated: Bool = false) {
        let value = min(max(value, 0), 1)
        guard setter != nil else { return }
        guard animated else {
            rampTimer?.invalidate()
            rampTimer = nil
            if apply(value) { brightness = value }
            return
        }
        rampFrom = applied
        rampStart = Date()
        brightness = value
        guard rampTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        rampTimer = timer
        tick()
    }

    func step(by steps: Int, fine: Bool) {
        refresh()
        let divisions = fine ? 64.0 : 16.0
        setBrightness(((brightness * divisions).rounded() + Double(steps)) / divisions, animated: true)
    }

    /// One frame of an ease-in-out ramp from `rampFrom` to `brightness`.
    private func tick() {
        let t = min(Date().timeIntervalSince(rampStart) / Self.rampDuration, 1)
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        apply(rampFrom + (brightness - rampFrom) * eased)
        if t >= 1 {
            rampTimer?.invalidate()
            rampTimer = nil
        }
    }

    @discardableResult
    private func apply(_ value: Double) -> Bool {
        guard let setter, setter(display, Float(value)) == 0 else { return false }
        applied = value
        return true
    }

    private static func builtInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &displays, &count)
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }
}
