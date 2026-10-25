import SwiftUI

extension ThermalService {
    /// Green when cool, through yellow and orange, to red at the warning threshold.
    static func color(for celsius: Double?, threshold: Int) -> Color {
        guard let celsius else { return .white.opacity(0.5) }
        let limit = Double(threshold)
        if celsius >= limit { return Color(red: 1, green: 0.36, blue: 0.34) }
        if celsius >= limit - 15 { return .orange }
        if celsius >= limit - 30 { return .yellow }
        return .green
    }
}

/// In the Sound and display tab: the chip temperature, a short history, and the other sensors.
struct TemperatureRow: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let thermal = model.thermal
        let reading = thermal.reading
        let threshold = model.settings.hotThreshold
        let color = ThermalService.color(for: reading?.cpu, threshold: threshold)
        HStack(spacing: 12) {
            Image(systemName: "thermometer.medium", variableValue: min(max(((reading?.cpu ?? 30) - 30) / 70, 0), 1))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(thermal.cpuText)
                        .font(.system(size: 16, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("CPU · \(thermal.thermalTitle)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Text(otherSensors(reading))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let battery = thermal.battery {
                BatteryBadge(battery: battery)
            }
            Sparkline(values: thermal.history, color: color)
                .frame(width: 70, height: 24)
        }
        .animation(.easeInOut(duration: 0.4), value: reading?.cpu)
        .help("Temperatures update every few seconds")
    }

    private func otherSensors(_ reading: ThermalService.Reading?) -> String {
        guard let reading else { return "Reading sensors…" }
        var parts: [String] = []
        if let gpu = reading.gpu { parts.append("GPU \(Int(gpu.rounded()))°") }
        if let battery = reading.battery { parts.append("Battery \(Int(battery.rounded()))°") }
        if let ssd = reading.ssd { parts.append("SSD \(Int(ssd.rounded()))°") }
        return parts.isEmpty ? "Apple silicon sensors" : parts.joined(separator: "  ·  ")
    }
}

private struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let low = (values.min() ?? 0) - 2
            let high = (values.max() ?? 1) + 2
            let span = max(high - low, 1)
            let step = values.count > 1 ? geometry.size.width / CGFloat(values.count - 1) : 0
            Path { path in
                for (index, value) in values.enumerated() {
                    let point = CGPoint(x: CGFloat(index) * step,
                                        y: geometry.size.height * (1 - CGFloat((value - low) / span)))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .opacity(values.count > 1 ? 1 : 0)
    }
}

/// Beside the notch. With the clock: the time right against the camera on the left – as near
/// the middle as there are pixels – and temperature and battery together on the right. Without
/// it: temperature left, battery right.
struct CompactThermalView: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let thermal = model.thermal
        let showsClock = model.settings.showClockInNotch
        HStack(spacing: 0) {
            Group {
                if showsClock {
                    NotchClock()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                } else {
                    temperature
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 10)
                }
            }
            .frame(width: model.thermalSideWidth + 10)

            Spacer(minLength: model.notch.width)

            HStack(spacing: 7) {
                if showsClock { temperature }
                if let battery = thermal.battery {
                    HStack(spacing: 2) {
                        Text("\(battery.percent)%")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .contentTransition(.numericText())
                        Image(systemName: battery.symbol).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(BatteryBadge.color(battery))
                }
            }
            .frame(maxWidth: .infinity, alignment: showsClock ? .leading : .trailing)
            .padding(showsClock ? .leading : .trailing, showsClock ? 8 : 10)
            .frame(width: model.thermalSideWidth + 10)
        }
        .padding(.horizontal, model.earRadius)
        .frame(height: model.notch.height)
        .animation(.easeInOut(duration: 0.4), value: thermal.reading?.cpu)
        .animation(.easeInOut(duration: 0.4), value: thermal.battery)
    }

    private var temperature: some View {
        let thermal = model.thermal
        return Text(thermal.cpuText)
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(ThermalService.color(for: thermal.reading?.cpu, threshold: model.settings.hotThreshold))
            .contentTransition(.numericText())
            .help("CPU temperature")
    }
}

/// "17:59" in a rounded heavy face with a soft glow; the colon blinks and digits roll on change.
private struct NotchClock: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let components = Calendar.current.dateComponents([.hour, .minute, .second], from: context.date)
            let hours = String(format: "%02d", components.hour ?? 0)
            let minutes = String(format: "%02d", components.minute ?? 0)
            let tick = (components.second ?? 0) % 2 == 0
            HStack(spacing: 1) {
                digits(hours)
                Text(":")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(tick ? 0.95 : 0.25)
                    .offset(y: -1)
                    .animation(.easeInOut(duration: 0.45), value: tick)
                digits(minutes)
            }
            .shadow(color: .white.opacity(0.22), radius: 4)
            .help(context.date.formatted(date: .complete, time: .shortened))
        }
        .fixedSize()
    }

    private func digits(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
            .contentTransition(.numericText(countsDown: false))
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: text)
    }
}

/// The battery's charge with its icon, and the time left when macOS knows it.
struct BatteryBadge: View {
    let battery: ThermalService.Battery

    static func color(_ battery: ThermalService.Battery) -> Color {
        if battery.isCharging || battery.isOnPower { return .green }
        if battery.percent <= 10 { return Color(red: 1, green: 0.36, blue: 0.34) }
        if battery.percent <= 20 { return .orange }
        return .white
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: battery.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Self.color(battery))
                Text("\(battery.percent)%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            Text(battery.timeText ?? (battery.isOnPower ? (battery.isCharging ? "Charging" : "On power") : "On battery"))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .fixedSize()
        .help(battery.isCharging ? "Charging" : (battery.isOnPower ? "Connected to power" : "On battery"))
    }
}

/// Dropped out of the notch when the Mac runs hot.
struct ThermalAlertView: View {
    @Environment(IslandModel.self) private var model
    @State private var bounce = false

    var body: some View {
        let thermal = model.thermal
        VStack(spacing: 0) {
            Color.clear.frame(height: model.notch.height)
            HStack(spacing: 12) {
                Image(systemName: "thermometer.sun.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white, Color(red: 1, green: 0.36, blue: 0.34))
                    .symbolEffect(.bounce, value: bounce)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your Mac is running hot")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("CPU \(thermal.cpuText) · \(thermal.thermalTitle)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .padding(.horizontal, model.earRadius)
        .onAppear { bounce = true }
    }
}
