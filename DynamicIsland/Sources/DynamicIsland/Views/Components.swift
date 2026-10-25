import AppKit
import SwiftUI

// MARK: - Elastic slider

/// The thin media slider from iOS/macOS: it thickens under the pointer and
/// stretches like rubber when dragged past either end.
struct ElasticSlider: View {
    @Binding var value: Double
    var tint: Color = .white
    var onEditingChanged: (Bool) -> Void = { _ in }

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.hapticFeedbackEnabled) private var hapticFeedbackEnabled
    @State private var isHovering = false
    @State private var isDragging = false
    @State private var stretch: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let isActive = isEnabled && (isHovering || isDragging)
            let thickness: CGFloat = isActive ? 9 : 6
            let fraction = CGFloat(min(max(value, 0), 1))

            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(isEnabled ? 0.18 : 0.1))
                Rectangle()
                    .fill(tint.opacity(isEnabled ? (isActive ? 1 : 0.82) : 0.3))
                    .frame(width: fraction * width + max(stretch, 0))
            }
            .frame(width: width + abs(stretch), height: thickness - min(abs(stretch) / 8, 2))
            .clipShape(Capsule())
            .offset(x: min(stretch, 0))
            .frame(width: width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let x = gesture.location.x
                        let newValue = Double(min(max(x / width, 0), 1))
                        // A detent at either end, felt while the finger is still dragging.
                        if hapticFeedbackEnabled, newValue != value, newValue == 0 || newValue == 1 {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                        value = newValue
                        stretch = rubberBand(x < 0 ? x : max(x - width, 0))
                    }
                    .onEnded { _ in
                        guard isDragging else { return }
                        isDragging = false
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.5)) { stretch = 0 }
                        onEditingChanged(false)
                    }
            )
            .onHover { isHovering = $0 }
            .animation(.spring(response: 0.3, dampingFraction: 0.68), value: isActive)
        }
        .frame(height: 18)
    }

    private func rubberBand(_ overshoot: CGFloat) -> CGFloat {
        let limit: CGFloat = 12
        let magnitude = limit * (1 - 1 / (abs(overshoot) / limit * 0.55 + 1))
        return overshoot < 0 ? -magnitude : magnitude
    }
}

private struct HapticFeedbackEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var hapticFeedbackEnabled: Bool {
        get { self[HapticFeedbackEnabledKey.self] }
        set { self[HapticFeedbackEnabledKey.self] = newValue }
    }
}

// MARK: - Buttons

/// Circular icon button with the subtle hover plate and press squish used across macOS.
struct IslandButtonStyle: ButtonStyle {
    var diameter: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, diameter: diameter)
    }

    private struct StyledButton: View {
        let configuration: Configuration
        let diameter: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.3))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(.white.opacity(isHovering && isEnabled ? 0.12 : 0)))
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.84 : 1)
                .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: isHovering)
                .onHover { isHovering = $0 }
        }
    }
}

// MARK: - Equalizer

struct EqualizerView: View {
    var color: Color
    var isPlaying: Bool
    var barCount = 4
    var height: CGFloat = 14

    private static let fast: [Double] = [5.3, 7.1, 4.4, 6.2, 5.8]
    private static let slow: [Double] = [2.1, 3.3, 2.7, 1.6, 2.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.6, height: max(3, height * level(index, time)))
                }
            }
            .frame(height: height)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isPlaying)
    }

    private func level(_ index: Int, _ time: Double) -> CGFloat {
        guard isPlaying else { return 0.22 }
        let i = index % Self.fast.count
        let wave = sin(time * Self.fast[i] + Double(index) * 1.3) + sin(time * Self.slow[i] + Double(index) * 2.7)
        return CGFloat(0.3 + 0.7 * (wave + 2) / 4)
    }
}

// MARK: - Marquee

/// Single-line text that scrolls like in Music when it does not fit.
struct MarqueeText: View {
    let text: String
    var font: Font
    var color: Color = .white

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var startDate = Date()

    private let gap: CGFloat = 36
    private let speed: Double = 30
    private let pause: Double = 2.2

    var body: some View {
        let overflows = containerWidth > 0 && textWidth > containerWidth + 1
        TimelineView(.animation(minimumInterval: nil, paused: !overflows)) { context in
            let offset = overflows ? offset(at: context.date) : 0
            Text(text)
                .font(font)
                .lineLimit(1)
                .hidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    HStack(spacing: gap) {
                        label
                        if overflows { label }
                    }
                    .offset(x: offset)
                }
                .clipped()
                // The leading edge only fades while the text is moving, like in Music.
                .mask(fade(leading: offset < 0, trailing: overflows))
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { containerWidth = $0 }
        .background(alignment: .leading) {
            Text(text).font(font).fixedSize().hidden()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { textWidth = $0 }
        }
        .onChange(of: text) { startDate = Date() }
    }

    private func fade(leading: Bool, trailing: Bool) -> LinearGradient {
        LinearGradient(stops: [.init(color: leading ? .clear : .black, location: 0), .init(color: .black, location: 0.04),
                               .init(color: .black, location: 0.9), .init(color: trailing ? .clear : .black, location: 1)],
                       startPoint: .leading, endPoint: .trailing)
    }

    private var label: some View {
        Text(text).font(font).foregroundStyle(color).fixedSize()
    }

    private func offset(at date: Date) -> CGFloat {
        let distance = Double(textWidth + gap)
        let cycle = pause + distance / speed
        let t = date.timeIntervalSince(startDate).truncatingRemainder(dividingBy: cycle)
        return t < pause ? 0 : -CGFloat((t - pause) * speed)
    }
}

// MARK: - Artwork

struct ArtworkView: View {
    var image: NSImage?
    var version: Int
    var size: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
                    .id(version)
            } else {
                LinearGradient(colors: [Color(white: 0.24), Color(white: 0.14)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.35), value: version)
    }
}

// MARK: - Formatting

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "--:--" }
    let total = Int(seconds.rounded(.down))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
}

// MARK: - Scrolling

/// A scroll container for the island. SwiftUI's `ScrollView` is backed by an `NSScrollView`, which
/// swallows the first click in a window that isn't key – and the island panel is never key, so
/// every click inside a `ScrollView` was lost. This one moves its content with an offset instead,
/// fed by scroll-wheel and trackpad events, so buttons and rows inside it stay clickable.
struct IslandScroll<Content: View>: View {
    var axis: Axis = .vertical
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var viewport: CGFloat = 0
    @State private var contentLength: CGFloat = 0
    @State private var id = UUID()

    var body: some View {
        let limit = max(contentLength - viewport, 0)
        let shown = min(max(offset, 0), limit)
        ZStack(alignment: .topLeading) {
            content
                .fixedSize(horizontal: axis == .horizontal, vertical: axis == .vertical)
                .frame(maxWidth: axis == .vertical ? .infinity : nil,
                       maxHeight: axis == .horizontal ? .infinity : nil, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self, of: { axis == .vertical ? $0.size.height : $0.size.width }) {
                    contentLength = $0
                }
                .offset(x: axis == .horizontal ? -shown : 0, y: axis == .vertical ? -shown : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(Rectangle())
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
            viewport = axis == .vertical ? frame.height : frame.width
            register(frame)
        }
        .onDisappear { IslandScrollRouter.shared.remove(id) }
    }

    /// Routes scroll events that land inside `frame` (window coordinates, top-left origin) here.
    private func register(_ frame: CGRect) {
        let offset = $offset, viewport = $viewport, contentLength = $contentLength, axis = axis
        IslandScrollRouter.shared.set(id, frame: frame) { event in
            let limit = max(contentLength.wrappedValue - viewport.wrappedValue, 0)
            guard limit > 0 else { return false }
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            var delta = axis == .vertical ? event.scrollingDeltaY : event.scrollingDeltaX
            // A plain mouse wheel only scrolls vertically; let it move horizontal rows too.
            if axis == .horizontal, abs(event.scrollingDeltaX) < abs(event.scrollingDeltaY) { delta = event.scrollingDeltaY }
            let current = min(max(offset.wrappedValue, 0), limit)
            offset.wrappedValue = min(max(current - delta * scale, 0), limit)
            return true
        }
    }
}

/// Sends scroll events in the island to the `IslandScroll` under the pointer, found by position
/// (hover tracking isn't reliable in a panel that never becomes key).
@MainActor
final class IslandScrollRouter {
    static let shared = IslandScrollRouter()

    private struct Target {
        var frame: CGRect
        var handler: (NSEvent) -> Bool
    }

    private var targets: [UUID: Target] = [:]
    private var monitor: Any?

    func set(_ id: UUID, frame: CGRect, handler: @escaping (NSEvent) -> Bool) {
        targets[id] = Target(frame: frame, handler: handler)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let handled = MainActor.assumeIsolated { IslandScrollRouter.shared.route(event) }
            return handled ? nil : event
        }
    }

    func remove(_ id: UUID) {
        targets[id] = nil
    }

    private func route(_ event: NSEvent) -> Bool {
        guard let window = event.window, let content = window.contentView else { return false }
        // SwiftUI's global space has its origin at the top left of the window's content.
        let location = event.locationInWindow
        let point = CGPoint(x: location.x, y: content.bounds.height - location.y)
        // The innermost (smallest) scroller under the pointer wins.
        let hit = targets.values
            .filter { $0.frame.contains(point) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        return hit?.handler(event) ?? false
    }
}
