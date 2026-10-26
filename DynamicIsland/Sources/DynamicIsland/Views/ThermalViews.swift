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
        .help("Temperaturen uppdateras med några sekunders mellanrum")
    }

    private func otherSensors(_ reading: ThermalService.Reading?) -> String {
        guard let reading else { return "Läser sensorer…" }
        var parts: [String] = []
        if let gpu = reading.gpu { parts.append("GPU \(Int(gpu.rounded()))°") }
        if let battery = reading.battery { parts.append("Batteri \(Int(battery.rounded()))°") }
        if let ssd = reading.ssd { parts.append("SSD \(Int(ssd.rounded()))°") }
        return parts.isEmpty ? "Apple silicon-sensorer" : parts.joined(separator: "  ·  ")
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

/// Beside the notch: temperature on the left, battery on the right, on the camera's line.
struct CompactThermalView: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let thermal = model.thermal
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                temperature
                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            .frame(width: model.thermalSideWidth)

            Color.clear.frame(width: model.notch.width)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if let battery = thermal.battery { batteryLabel(battery) }
            }
            .padding(.trailing, 12)
            .frame(width: model.thermalSideWidth)
        }
        .padding(.horizontal, model.earRadius)
        .frame(height: model.notch.height)
        .animation(.easeInOut(duration: 0.4), value: thermal.reading?.cpu)
        .animation(.easeInOut(duration: 0.4), value: thermal.battery)
    }

    private var temperature: some View {
        let thermal = model.thermal
        return HStack(spacing: 3) {
            Image(systemName: "thermometer.medium").font(.system(size: 11, weight: .semibold))
            Text(thermal.cpuText)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .foregroundStyle(ThermalService.color(for: thermal.reading?.cpu, threshold: model.settings.hotThreshold))
        .lineLimit(1)
        .fixedSize()
        .help("CPU-temperatur")
    }

    private func batteryLabel(_ battery: ThermalService.Battery) -> some View {
        HStack(spacing: 3) {
            Text("\(battery.percent)%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText())
                .lineLimit(1)
            Image(systemName: battery.symbol).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(BatteryBadge.color(battery))
        .fixedSize()
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
            Text(battery.timeText ?? (battery.isOnPower ? (battery.isCharging ? "Laddar" : "På ström") : "På batteri"))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .fixedSize()
        .help(battery.isCharging ? "Laddar" : (battery.isOnPower ? "Ansluten till ström" : "På batteri"))
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
                    Text("Din Mac går varm")
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
