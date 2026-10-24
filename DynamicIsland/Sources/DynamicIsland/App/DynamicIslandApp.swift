import AppKit

@main
enum DynamicIslandApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: IslandModel?
    private var islandWindow: IslandWindowController?
    private var settingsWindow: SettingsWindowController?
    private var quickAddWindow: QuickAddTaskController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let media = NowPlayingService()
        let audio = AudioService()
        let settings = AppSettings()
        let home = HomeService(settings: settings)
        let posture = PostureService()
        let hub = AcordHubService(settings: HubSettings())
        let model = IslandModel(media: media, audio: audio, brightness: BrightnessService(), home: home,
                                posture: posture, hub: hub, settings: settings)
        let settingsWindow = SettingsWindowController(model: model)
        model.onOpenSettings = { [weak settingsWindow] in settingsWindow?.show() }
        let quickAddWindow = QuickAddTaskController(model: model)
        model.onQuickAddTask = { [weak quickAddWindow] in quickAddWindow?.show() }

        let islandWindow = IslandWindowController(model: model)
        islandWindow.show()
        media.start()
        audio.start()
        home.refresh()
        posture.start()
        #if DEBUG
        let isRenderingSnapshots = CommandLine.arguments.contains("--snapshots")
        #else
        let isRenderingSnapshots = false
        #endif
        if !isRenderingSnapshots { hub.start() }

        self.model = model
        self.islandWindow = islandWindow
        self.settingsWindow = settingsWindow
        self.quickAddWindow = quickAddWindow

        #if DEBUG
        if let flag = CommandLine.arguments.firstIndex(of: "--snapshots"), flag + 1 < CommandLine.arguments.count {
            SnapshotRenderer.run(model: model, directory: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
        }
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launching the app again (e.g. from Finder) opens the settings.
        settingsWindow?.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.media.stop()
        model?.posture.stop()
        model?.hub.stop()
    }
}
