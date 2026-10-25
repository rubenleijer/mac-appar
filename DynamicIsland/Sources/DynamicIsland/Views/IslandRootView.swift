import AppKit
import SwiftUI

struct IslandRootView: View {
    @Environment(IslandModel.self) private var model
    @Namespace private var namespace

    var body: some View {
        let presentation = model.presentation
        let size = model.size
        let shape = NotchShape(topRadius: model.earRadius, bottomRadius: model.bottomRadius)

        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .shadow(color: .black.opacity(presentation == .open ? 0.5 : 0), radius: 18, y: 8)
            content(for: presentation)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(shape)
        .onTapGesture {
            if presentation != .open { model.open() }
        }
        .contextMenu {
            Button("Settings…") { model.onOpenSettings?() }
            Divider()
            Button("Quit Dynamic Island") { NSApp.terminate(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(model.animation, value: presentation)
        .environment(\.colorScheme, .dark)
        .environment(\.hapticFeedbackEnabled, model.settings.hapticFeedback)
    }

    @ViewBuilder
    private func content(for presentation: IslandPresentation) -> some View {
        ZStack(alignment: .top) {
            if model.showsThermalStrip && presentation != .thermalCompact {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ThermalStrip()
                        .padding(.horizontal, model.earRadius)
                        .padding(.bottom, 2)
                }
                .transition(.opacity)
            }
            switch presentation {
            case .closed:
                Color.clear
            case .compact:
                CompactMediaView(namespace: namespace)
                    .transition(.islandContent(scale: 0.8))
            case .peek:
                PeekView(namespace: namespace)
                    .transition(.islandContent(scale: 0.85))
            case .hud(let kind):
                HUDView(kind: kind)
                    .transition(.islandContent(scale: 0.8))
            case .postureAlert:
                PostureAlertView()
                    .transition(.islandContent(scale: 0.85))
            case .postureCompact:
                CompactPostureView()
                    .transition(.islandContent(scale: 0.8))
            case .hubAlert:
                HubAlertView()
                    .transition(.islandContent(scale: 0.85))
            case .hubCompact:
                CompactHubView()
                    .transition(.islandContent(scale: 0.8))
            case .thermalAlert:
                ThermalAlertView()
                    .transition(.islandContent(scale: 0.85))
            case .thermalCompact:
                CompactThermalView()
                    .transition(.islandContent(scale: 0.8))
            case .open:
                OpenIslandView(namespace: namespace)
                    .transition(.islandContent(scale: 0.9))
            }
        }
    }
}

// MARK: - Transition

private struct BlurScaleModifier: ViewModifier {
    var blur: CGFloat
    var scale: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale, anchor: .top)
            .opacity(opacity)
    }
}

extension AnyTransition {
    /// Content dissolves through a blur while scaling from the notch, like the iPhone's Dynamic Island.
    static func islandContent(scale: CGFloat) -> AnyTransition {
        .modifier(active: BlurScaleModifier(blur: 10, scale: scale, opacity: 0),
                  identity: BlurScaleModifier(blur: 0, scale: 1, opacity: 1))
    }
}
