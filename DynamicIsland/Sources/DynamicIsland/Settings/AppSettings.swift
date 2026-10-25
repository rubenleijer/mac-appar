import Foundation

@MainActor @Observable
final class AppSettings {
    var hoverToOpen: Bool { didSet { store(hoverToOpen, Key.hoverToOpen) } }
    var hapticFeedback: Bool { didSet { store(hapticFeedback, Key.hapticFeedback) } }
    var showLiveActivity: Bool { didSet { store(showLiveActivity, Key.showLiveActivity) } }
    var showTrackChanges: Bool { didSet { store(showTrackChanges, Key.showTrackChanges) } }
    var showVolumeHUD: Bool { didSet { store(showVolumeHUD, Key.showVolumeHUD) } }
    var showDeviceChanges: Bool { didSet { store(showDeviceChanges, Key.showDeviceChanges) } }
    var showHomeTab: Bool { didSet { store(showHomeTab, Key.showHomeTab) } }
    var showPostureTab: Bool { didSet { store(showPostureTab, Key.showPostureTab) } }
    var showPostureAlerts: Bool { didSet { store(showPostureAlerts, Key.showPostureAlerts) } }
    var showPostureLiveActivity: Bool { didSet { store(showPostureLiveActivity, Key.showPostureLiveActivity) } }
    var homeFolderName: String { didSet { defaults.set(homeFolderName, forKey: Key.homeFolderName) } }
    var showTrayTab: Bool { didSet { store(showTrayTab, Key.showTrayTab) } }
    var openTrayOnDrag: Bool { didSet { store(openTrayOnDrag, Key.openTrayOnDrag) } }
    /// Days before tray items go to the Trash; 0 keeps them.
    var trayRetentionDays: Int { didSet { defaults.set(trayRetentionDays, forKey: Key.trayRetentionDays) } }
    var replaceSystemHUD: Bool {
        didSet {
            store(replaceSystemHUD, Key.replaceSystemHUD)
            onReplaceSystemHUDChange?()
        }
    }

    @ObservationIgnored var onReplaceSystemHUDChange: (() -> Void)?

    private enum Key {
        static let hoverToOpen = "hoverToOpen"
        static let hapticFeedback = "hapticFeedback"
        static let showLiveActivity = "showLiveActivity"
        static let showTrackChanges = "showTrackChanges"
        static let showVolumeHUD = "showVolumeHUD"
        static let showDeviceChanges = "showDeviceChanges"
        static let replaceSystemHUD = "replaceSystemHUD"
        static let showHomeTab = "showHomeTab"
        static let homeFolderName = "homeFolderName"
        static let showPostureTab = "showPostureTab"
        static let showPostureAlerts = "showPostureAlerts"
        static let showPostureLiveActivity = "showPostureLiveActivity"
        static let showTrayTab = "showTrayTab"
        static let openTrayOnDrag = "openTrayOnDrag"
        static let trayRetentionDays = "trayRetentionDays"
    }

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            Key.hoverToOpen: true,
            Key.hapticFeedback: true,
            Key.showLiveActivity: true,
            Key.showTrackChanges: true,
            Key.showVolumeHUD: true,
            Key.showDeviceChanges: true,
            Key.replaceSystemHUD: false,
            Key.showHomeTab: false,
            Key.showTrayTab: true,
            Key.openTrayOnDrag: true,
            Key.trayRetentionDays: 0,
            Key.homeFolderName: "Home",
            Key.showPostureTab: true,
            Key.showPostureAlerts: true,
            Key.showPostureLiveActivity: true,
        ])
        hoverToOpen = defaults.bool(forKey: Key.hoverToOpen)
        hapticFeedback = defaults.bool(forKey: Key.hapticFeedback)
        showLiveActivity = defaults.bool(forKey: Key.showLiveActivity)
        showTrackChanges = defaults.bool(forKey: Key.showTrackChanges)
        showVolumeHUD = defaults.bool(forKey: Key.showVolumeHUD)
        showDeviceChanges = defaults.bool(forKey: Key.showDeviceChanges)
        replaceSystemHUD = defaults.bool(forKey: Key.replaceSystemHUD)
        showHomeTab = defaults.bool(forKey: Key.showHomeTab)
        showPostureTab = defaults.bool(forKey: Key.showPostureTab)
        showPostureAlerts = defaults.bool(forKey: Key.showPostureAlerts)
        showPostureLiveActivity = defaults.bool(forKey: Key.showPostureLiveActivity)
        homeFolderName = defaults.string(forKey: Key.homeFolderName) ?? "Home"
        showTrayTab = defaults.bool(forKey: Key.showTrayTab)
        openTrayOnDrag = defaults.bool(forKey: Key.openTrayOnDrag)
        trayRetentionDays = defaults.integer(forKey: Key.trayRetentionDays)
        // The tray replaced the Home tab; hide Home once for anyone who had it on.
        if !defaults.bool(forKey: "didReplaceHomeWithTray") {
            showHomeTab = false
            defaults.set(false, forKey: Key.showHomeTab)
            defaults.set(true, forKey: "didReplaceHomeWithTray")
        }
    }

    private func store(_ value: Bool, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
