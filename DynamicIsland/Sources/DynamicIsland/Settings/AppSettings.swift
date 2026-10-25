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
    var showTemperature: Bool { didSet { store(showTemperature, Key.showTemperature) } }
    var showTemperatureLiveActivity: Bool { didSet { store(showTemperatureLiveActivity, Key.showTemperatureLiveActivity) } }
    var warnWhenHot: Bool { didSet { store(warnWhenHot, Key.warnWhenHot) } }
    var hotThreshold: Int { didSet { defaults.set(hotThreshold, forKey: Key.hotThreshold) } }
    var autoUpdate: Bool { didSet { store(autoUpdate, Key.autoUpdate) } }
    var autoInstallUpdates: Bool { didSet { store(autoInstallUpdates, Key.autoInstallUpdates) } }
    var updateRepository: String { didSet { defaults.set(updateRepository, forKey: Key.updateRepository) } }
    var updateBranch: String { didSet { defaults.set(updateBranch, forKey: Key.updateBranch) } }
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
        static let showTemperature = "showTemperature"
        static let showTemperatureLiveActivity = "showTemperatureLiveActivity"
        static let warnWhenHot = "warnWhenHot"
        static let hotThreshold = "hotThreshold"
        static let autoUpdate = "autoUpdate"
        static let autoInstallUpdates = "autoInstallUpdates"
        static let updateRepository = "updateRepository"
        static let updateBranch = "updateBranch"
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
            Key.showTemperature: true,
            Key.showTemperatureLiveActivity: false,
            Key.warnWhenHot: true,
            Key.hotThreshold: 90,
            Key.autoUpdate: true,
            Key.autoInstallUpdates: true,
            Key.updateRepository: "rubenleijer/mac-appar",
            Key.updateBranch: "acord-hub",
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
        showTemperature = defaults.bool(forKey: Key.showTemperature)
        showTemperatureLiveActivity = defaults.bool(forKey: Key.showTemperatureLiveActivity)
        warnWhenHot = defaults.bool(forKey: Key.warnWhenHot)
        hotThreshold = max(defaults.integer(forKey: Key.hotThreshold), 60)
        autoUpdate = defaults.bool(forKey: Key.autoUpdate)
        autoInstallUpdates = defaults.bool(forKey: Key.autoInstallUpdates)
        updateRepository = defaults.string(forKey: Key.updateRepository) ?? "rubenleijer/mac-appar"
        updateBranch = defaults.string(forKey: Key.updateBranch) ?? "acord-hub"
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
