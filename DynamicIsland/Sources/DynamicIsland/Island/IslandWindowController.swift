import AppKit
import SwiftUI

/// A borderless panel that floats above the menu bar, on every Space and over
/// full-screen apps, without ever activating the app.
final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Borderless windows are otherwise pushed below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class IslandWindowController {
    /// Large enough for the open island plus its shadow; the rest is transparent and click-through.
    private static let canvasSize = CGSize(width: 760, height: 440)

    private let model: IslandModel
    private let panel: IslandPanel
    private var monitors: [Any] = []

    init(model: IslandModel) {
        self.model = model
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: Self.canvasSize))

        let hostingView = IslandHostingView(rootView: IslandRootView().environment(model))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: Self.canvasSize)
        panel.contentView = hostingView

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        installMouseMonitors()
        observeHoverZone()
        #if DEBUG
        if CommandLine.arguments.contains("--trace") { trace() }
        #endif
    }

    #if DEBUG
    private func trace() {
        withObservationTracking {
            _ = model.presentation
            _ = model.media.isPlaying
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    print("presentation=\(self.model.presentation) playing=\(self.model.media.isPlaying) clickThrough=\(self.panel.ignoresMouseEvents)")
                    fflush(stdout)
                    self.trace()
                }
            }
        }
    }
    #endif

    func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    private func reposition() {
        guard let screen = NotchMetrics.preferredScreen() else { return }
        let metrics = NotchMetrics(screen: screen)
        model.metrics = metrics
        let origin = CGPoint(x: (metrics.centerX - Self.canvasSize.width / 2).rounded(),
                             y: screen.frame.maxY - Self.canvasSize.height)
        panel.setFrame(NSRect(origin: origin, size: Self.canvasSize), display: true)
    }

    private func installMouseMonitors() {
        let movement: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: movement, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: movement, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updatePointer() }
            return event
        }) {
            monitors.append(local)
        }
        // A click anywhere else (delivered to another app) closes the island.
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.hoverZone.contains(NSEvent.mouseLocation) else { return }
                self.model.close()
            }
        }) {
            monitors.append(clicks)
        }
    }

    private func updatePointer() {
        let inside = model.hoverZone.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        model.setHovering(inside)
    }

    /// Re-evaluates the pointer whenever the island changes shape under it.
    private func observeHoverZone() {
        withObservationTracking {
            _ = model.hoverZone
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.updatePointer()
                    self?.observeHoverZone()
                }
            }
        }
    }
}
