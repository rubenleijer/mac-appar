import SwiftUI

// MARK: - Figure

/// The seated figure from the Posture app, facing right. `slouch` animates from upright (0) to slouched (1).
struct PostureFigure: Shape {
    var slouch: Double

    var animatableData: Double {
        get { slouch }
        set { slouch = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - size / 2, y: rect.midY - size / 2)
        let t = CGFloat(min(max(slouch, 0), 1))

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * size, y: origin.y + y * size) }
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint { point(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t) }

        let shoulder = mix(CGPoint(x: 0.40, y: 0.34), CGPoint(x: 0.55, y: 0.44))
        let spine = mix(CGPoint(x: 0.36, y: 0.52), CGPoint(x: 0.24, y: 0.56))
        let head = mix(CGPoint(x: 0.44, y: 0.15), CGPoint(x: 0.72, y: 0.29))
        let elbow = mix(CGPoint(x: 0.44, y: 0.55), CGPoint(x: 0.56, y: 0.62))
        let hand = mix(CGPoint(x: 0.66, y: 0.52), CGPoint(x: 0.76, y: 0.60))
        let lineWidth = 0.085 * size
        let radius = 0.10 * size

        var lines = Path()
        lines.move(to: point(0.74, 0.97))
        lines.addLine(to: point(0.74, 0.72))
        lines.addLine(to: point(0.36, 0.72))
        lines.addQuadCurve(to: shoulder, control: spine)
        let dx = head.x - shoulder.x, dy = head.y - shoulder.y
        let length = max(hypot(dx, dy), 0.001)
        let gap = radius * 1.25 + lineWidth / 2
        if length > gap {
            lines.move(to: shoulder)
            lines.addLine(to: CGPoint(x: head.x - dx / length * gap, y: head.y - dy / length * gap))
        }
        lines.move(to: shoulder)
        lines.addLine(to: elbow)
        lines.addLine(to: hand)

        var path = lines.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        path.addEllipse(in: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2))
        return path
    }
}

extension PostureService.State {
    var color: Color {
        switch status {
        case "good": .green
        case "bad": .orange
        case "uncertain": .yellow
        case "paused": .indigo
        default: .white.opacity(0.5)
        }
    }

    var slouch: Double {
        switch status {
        case "bad": 0.85
        case "uncertain": 0.35
        default: 0
        }
    }
}

/// The figure inside a ring of today's good posture.
private struct PostureRing: View {
    var fraction: Double
    var slouch: Double
    var color: Color
    var size: CGFloat
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(fraction, 0), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            PostureFigure(slouch: slouch)
                .fill(color)
                .padding(size * 0.23)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: slouch)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: fraction)
    }
}

// MARK: - Tab

struct PostureTab: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let posture = model.posture
        if let state = posture.state {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    PostureRing(fraction: state.todayGood, slouch: state.slouch, color: state.color, size: 74, lineWidth: 5)
                        .overlay(alignment: .bottom) {
                            Text("\(Int((state.todayGood * 100).rounded())) %")
                                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.7))
                                .offset(y: 13)
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(detail(state, now: context.date))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.55))
                                .monospacedDigit()
                        }
                        if state.isBad {
                            ReminderBar(progress: state.progress)
                                .frame(height: 5)
                                .padding(.top, 5)
                        }
                    }
                    Spacer(minLength: 0)
                    if let pitch = state.headPitch, state.airpods {
                        VStack(spacing: 3) {
                            Image(systemName: "airpods.pro")
                                .font(.system(size: 15, weight: .medium))
                            Text(neckText(pitch))
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .contentTransition(.numericText())
                        }
                        .foregroundStyle(state.isNeckBent ? Color.orange : Color.white.opacity(0.75))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state.isNeckBent)
                        .help("Nackvinkel från AirPods – högst \(Int(state.neckLimit.rounded()))° nedåt")
                    }
                }
                HStack(spacing: 8) {
                    // Only a pause the user chose can be resumed; lock screen and calls resume by themselves.
                    if state.isPaused && state.pausedUntil != nil {
                        CapsuleButton(title: "Fortsätt") { posture.send(.resume) }
                    } else {
                        CapsuleButton(title: "Pausa 30 min") { posture.send(.pause30) }
                    }
                    CapsuleButton(title: "Kolla nu") { posture.send(.check) }
                        .disabled(state.isPaused)
                    Spacer(minLength: 0)
                    CapsuleButton(title: "Öppna Hållning") { posture.openApp() }
                }
            }
            .padding(.top, 6)
        } else {
            Text("Hållning körs inte")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, minHeight: 100)
        }
    }

    private func detail(_ state: PostureService.State, now: Date) -> String {
        if state.isPaused {
            // Posture's on/off switch pauses with no end date.
            if let until = state.pausedUntil, until.timeIntervalSinceNow < 7 * 24 * 3600 {
                return "Pausad till \(until.formatted(date: .omitted, time: .shortened))"
            }
            return "Pausad"
        }
        guard let lastCheck = state.lastCheck else { return "Ingen koll än" }
        let seconds = max(Int(now.timeIntervalSince(lastCheck)), 0)
        if seconds < 5 { return "Kollade nyss" }
        if seconds < 60 { return "Kollade för \(seconds) s sedan" }
        return "Kollade för \(seconds / 60) min sedan"
    }

    private func neckText(_ pitch: Double) -> String {
        let degrees = Int(abs(pitch).rounded())
        return degrees < 3 ? "Nivå" : "\(degrees)° \(pitch > 0 ? "down" : "up")"
    }
}

private struct ReminderBar: View {
    var progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule()
                    .fill(.orange)
                    .frame(width: geometry.size.width * CGFloat(min(max(progress, 0), 1)))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
    }
}

// MARK: - Live activities

/// Shown for a few seconds when the Posture app sends a reminder.
struct PostureAlertView: View {
    @Environment(IslandModel.self) private var model
    @State private var bounce = false

    var body: some View {
        let alert = model.posture.latestAlert
        VStack(spacing: 0) {
            Color.clear.frame(height: model.notch.height)
            HStack(spacing: 12) {
                PostureFigure(slouch: bounce ? 0 : 0.85)
                    .fill(.orange)
                    .frame(width: 38, height: 38)
                    .animation(.spring(response: 0.7, dampingFraction: 0.5).delay(0.35), value: bounce)
                VStack(alignment: .leading, spacing: 1) {
                    Text(alert?.title ?? "Dålig hållning")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(alert?.issue == "neckBent" ? "Böjd nacke i \(alert?.minutes ?? 2) min"
                                                     : "Dålig hållning i \(alert?.minutes ?? 3) min")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "figure.stand")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white, .orange)
                    .symbolEffect(.bounce, value: bounce)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .padding(.horizontal, model.earRadius)
        .onAppear { bounce = true }
    }
}

/// The figure in orange to the left of the notch, the progress towards a reminder to the right.
struct CompactPostureView: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let notch = model.notch
        let size = notch.height - 10
        let inset = (notch.height - size) / 2
        let progress = model.posture.state?.progress ?? 0

        HStack(spacing: 0) {
            PostureFigure(slouch: 0.85)
                .fill(.orange)
                .frame(width: size, height: size)
                .padding(.leading, inset + 1)
            Spacer(minLength: 0)
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                    .stroke(.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: size - 8, height: size - 8)
            .padding(.trailing, inset + 5)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
        }
        .padding(.horizontal, model.earRadius)
        .frame(height: notch.height)
    }
}
