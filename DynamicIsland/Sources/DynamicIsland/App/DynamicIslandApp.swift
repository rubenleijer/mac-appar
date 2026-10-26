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
    private var taskEditor: TaskEditorController?
    private var meetingEditor: MeetingEditorController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        let media = NowPlayingService()
        let audio = AudioService()
        let settings = AppSettings()
        let home = HomeService(settings: settings)
        let posture = PostureService()
        let hub = AcordHubService(settings: HubSettings())
        let thermal = ThermalService(settings: settings)
        let clipboard = ClipboardService(settings: settings)
        let model = IslandModel(media: media, audio: audio, brightness: BrightnessService(), home: home,
                                posture: posture, hub: hub, tray: TrayService(settings: settings),
                                thermal: thermal, clipboard: clipboard, settings: settings)
        let settingsWindow = SettingsWindowController(model: model)
        model.onOpenSettings = { [weak settingsWindow] in settingsWindow?.show() }
        let quickAddWindow = QuickAddTaskController(model: model)
        model.onQuickAddTask = { [weak quickAddWindow] in quickAddWindow?.show() }
        let updates = UpdateService(settings: settings)
        updates.canInstallNow = { [weak model] in model.map { !$0.isOpen } ?? true }
        model.updates = updates
        let taskEditor = TaskEditorController(model: model)
        model.onEditTask = { [weak taskEditor] task, checklist in taskEditor?.show(task, focusChecklist: checklist) }
        let meetingEditor = MeetingEditorController(model: model)
        model.onEditMeeting = { [weak meetingEditor] event, start in meetingEditor?.show(event, start: start) }

        let islandWindow = IslandWindowController(model: model)
        islandWindow.show()
        media.start()
        audio.start()
        if settings.showHomeTab { home.refresh() }
        posture.start()
        thermal.start()
        clipboard.start()
        #if DEBUG
        let isRenderingSnapshots = CommandLine.arguments.contains("--snapshots")
        #else
        let isRenderingSnapshots = false
        #endif
        if !isRenderingSnapshots {
            hub.start()
            updates.start()
        }

        self.model = model
        self.islandWindow = islandWindow
        self.settingsWindow = settingsWindow
        self.quickAddWindow = quickAddWindow
        self.taskEditor = taskEditor
        self.meetingEditor = meetingEditor

        #if DEBUG
        if let flag = CommandLine.arguments.firstIndex(of: "--snapshots"), flag + 1 < CommandLine.arguments.count {
            SnapshotRenderer.run(model: model, directory: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
        }
        #endif
    }

    /// The app has no menu bar of its own, so without this ⌘V, ⌘C, ⌘A and ⌘Z do nothing in text
    /// fields – pasting the Hub token in settings needs it.
    private func installEditMenu() {
        let edit = NSMenu(title: "Redigera")
        edit.addItem(withTitle: "Ångra", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Gör om", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Klipp ut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopiera", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Klistra in", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Markera allt", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let window = NSMenu(title: "Fönster")
        window.addItem(withTitle: "Stäng", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let main = NSMenu()
        for submenu in [NSMenu(title: "Dynamic Island"), edit, window] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
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
        model?.thermal.stop()
        model?.clipboard.stop()
    }
}
