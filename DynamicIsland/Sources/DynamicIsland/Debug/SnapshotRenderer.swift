#if DEBUG
import AppKit
import SwiftUI

/// Debug aid: `DynamicIsland --snapshots <dir>` renders every island state to PNG and quits.
@MainActor
enum SnapshotRenderer {
    static func run(model: IslandModel, directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task {
            try? await Task.sleep(for: .seconds(3))
            render("1-closed", model, directory)
            render("2-compact", model, directory)
            model.showTrackPeek()
            render("3-peek", model, directory)
            model.showHUD(.volume)
            render("4-hud-volume", model, directory)
            model.showHUD(.brightness)
            render("5-hud-brightness", model, directory)
            model.showHUD(.outputDevice)
            render("6-hud-device", model, directory)
            model.open()
            render("7-open-media", model, directory)
            renderHero("0-hero", model, directory)
            model.select(.controls)
            render("8-open-controls", model, directory)
            model.select(.home)
            try? await Task.sleep(for: .seconds(1.5))
            render("9-open-home-empty", model, directory)
            model.home.showPreviewShortcuts()
            render("10-open-home", model, directory)
            model.close()
            model.posture.showPreview(.init(status: "bad", issue: "neckBent", title: "Lift your head",
                                            progress: 0.7, score: 42, todayGood: 0.78, headPitch: 22, airpods: true,
                                            interval: 10, lastCheck: Date().addingTimeInterval(-6), pausedUntil: nil))
            render("11-posture-compact", model, directory)
            model.posture.showPreviewAlert(.init(issue: "neckBent", title: "Lift your head",
                                                 body: "", minutes: 2))
            model.showPostureAlert()
            try? await Task.sleep(for: .seconds(0.5))
            render("12-posture-alert", model, directory)
            model.open()
            model.select(.posture)
            render("13-open-posture-bad", model, directory)
            model.posture.showPreview(.init(status: "good", issue: nil, title: "Good posture",
                                            progress: 0, score: 91, todayGood: 0.86, headPitch: 2, airpods: true,
                                            interval: 10, lastCheck: Date(), pausedUntil: nil))
            render("14-open-posture-good", model, directory)
            model.close()
            model.hub.showPreview()
            render("15-hub-compact", model, directory)
            model.hub.showPreviewAlert()
            model.showHubAlert()
            try? await Task.sleep(for: .seconds(0.5))
            render("16-hub-alert", model, directory)
            model.dismissHubAlert()
            model.open()
            model.select(.hub)
            model.hub.section = .tasks
            render("17-open-hub-tasks", model, directory)
            model.hub.section = .calendar
            render("18-open-hub-calendar", model, directory)
            model.select(.media)
            model.close()
            NSApp.terminate(nil)
        }
    }

    /// One state on a wallpaper-like background, sized to the island.
    private static func render(_ name: String, _ model: IslandModel, _ directory: URL) {
        let height = max(model.size.height + 64, 110)
        let view = ZStack(alignment: .top) {
            Wallpaper()
            IslandRootView().environment(model)
        }
        .frame(width: 640, height: height)
        write(view, scale: 2, to: directory.appendingPathComponent("\(name).png"))
    }

    /// The open island hanging over a menu bar.
    private static func renderHero(_ name: String, _ model: IslandModel, _ directory: URL) {
        let view = ZStack(alignment: .top) {
            Wallpaper()
            MenuBar(height: model.notch.height)
            IslandRootView().environment(model)
        }
        .frame(width: 1000, height: 240)
        write(view, scale: 2, to: directory.appendingPathComponent("\(name).png"))
    }

    private static func write(_ view: some View, scale: CGFloat, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}

private struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.24, blue: 0.62), Color(red: 0.46, green: 0.3, blue: 0.8),
                                    Color(red: 0.93, green: 0.56, blue: 0.68)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.28), .clear], center: .init(x: 0.7, y: 0.9),
                           startRadius: 0, endRadius: 520)
        }
    }
}

private struct MenuBar: View {
    var height: CGFloat

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "apple.logo").font(.system(size: 15, weight: .medium))
            Text("Finder").fontWeight(.bold)
            ForEach(["File", "Edit"], id: \.self) { Text($0) }
            Spacer()
            HStack(spacing: 18) {
                Image(systemName: "wifi")
                Image(systemName: "switch.2")
                Text("Sat 9:41")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .frame(height: height)
    }
}
#endif
