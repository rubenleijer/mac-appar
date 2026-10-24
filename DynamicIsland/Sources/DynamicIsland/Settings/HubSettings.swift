import Foundation
import Security

/// The sections of the Acord Hub tab, in the order the user arranged them.
enum HubSection: String, CaseIterable, Identifiable {
    case tasks, calendar, approvals, content, notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: "Tasks"
        case .calendar: "Calendar"
        case .approvals: "Approvals"
        case .content: "Content"
        case .notifications: "Notifications"
        }
    }

    var symbol: String {
        switch self {
        case .tasks: "checklist"
        case .calendar: "calendar"
        case .approvals: "checkmark.seal.fill"
        case .content: "square.and.pencil"
        case .notifications: "bell.fill"
        }
    }
}

enum HubTaskScope: String, CaseIterable, Identifiable {
    case mine, unassignedAndMine, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .mine: "Assigned to me"
        case .unassignedAndMine: "Mine and unassigned"
        case .all: "Everyone’s"
        }
    }
}

/// Task statuses in the Hub, minus DONE which the island never shows.
enum HubTaskStatus: String, CaseIterable, Identifiable {
    case todo = "TODO", inProgress = "IN_PROGRESS", unclear = "UNCLEAR"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .todo: "To do"
        case .inProgress: "In progress"
        case .unclear: "Unclear"
        }
    }
}

enum HubPriority: String, CaseIterable, Identifiable, Comparable {
    case none = "NONE", low = "LOW", medium = "MEDIUM", high = "HIGH", dangerous = "DANGEROUS"
    var id: String { rawValue }
    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    var title: String {
        switch self {
        case .none: "Any"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .dangerous: "Critical"
        }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// What the island shows when it opens.
enum IslandStartTab: String, CaseIterable, Identifiable {
    case lastUsed, media, hub
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lastUsed: "Last used tab"
        case .media: "Now Playing"
        case .hub: "Acord Hub"
        }
    }
}

/// Everything about the Acord Hub integration the user can change. The token lives in the keychain.
@MainActor @Observable
final class HubSettings {
    // Connection
    var showTab: Bool { didSet { persist(showTab, .showTab) } }
    var serverURL: String { didSet { persist(serverURL, .serverURL); onConnectionChange?() } }
    var webURL: String { didSet { persist(webURL, .webURL) } }
    var token: String { didSet { Keychain.write(token, account: "token"); onConnectionChange?() } }
    var memberID: String { didSet { persist(memberID, .memberID) } }
    var refreshMinutes: Double { didSet { persist(refreshMinutes, .refreshMinutes); onIntervalChange?() } }
    var startTab: IslandStartTab { didSet { persist(startTab.rawValue, .startTab) } }

    // Sections
    var sectionOrder: [HubSection] { didSet { persist(sectionOrder.map(\.rawValue), .sectionOrder) } }
    var hiddenSections: Set<HubSection> { didSet { persist(hiddenSections.map(\.rawValue), .hiddenSections) } }
    var showCounts: Bool { didSet { persist(showCounts, .showCounts) } }
    var showClientNames: Bool { didSet { persist(showClientNames, .showClientNames) } }

    // Tasks
    var taskScope: HubTaskScope { didSet { persist(taskScope.rawValue, .taskScope) } }
    var taskStatuses: Set<HubTaskStatus> { didSet { persist(taskStatuses.map(\.rawValue), .taskStatuses) } }
    var minimumPriority: HubPriority { didSet { persist(minimumPriority.rawValue, .minimumPriority) } }
    /// Only tasks due within this many days; 0 shows every task, including those without a date.
    var taskHorizonDays: Int { didSet { persist(taskHorizonDays, .taskHorizonDays) } }
    var showUndatedTasks: Bool { didSet { persist(showUndatedTasks, .showUndatedTasks) } }
    var sortByPriority: Bool { didSet { persist(sortByPriority, .sortByPriority) } }

    // Calendar, approvals, content
    var calendarDays: Int { didSet { persist(calendarDays, .calendarDays) } }
    var pendingApprovalsOnly: Bool { didSet { persist(pendingApprovalsOnly, .pendingApprovalsOnly) } }
    var contentDays: Int { didSet { persist(contentDays, .contentDays) } }
    var includeDraftPosts: Bool { didSet { persist(includeDraftPosts, .includeDraftPosts) } }

    // Notifications
    var notifyNewTask: Bool { didSet { persist(notifyNewTask, .notifyNewTask) } }
    var notifyDueSoon: Bool { didSet { persist(notifyDueSoon, .notifyDueSoon) } }
    var dueSoonDays: Int { didSet { persist(dueSoonDays, .dueSoonDays) } }
    var notifyOverdue: Bool { didSet { persist(notifyOverdue, .notifyOverdue) } }
    var notifyEventSoon: Bool { didSet { persist(notifyEventSoon, .notifyEventSoon) } }
    var eventLeadMinutes: Int { didSet { persist(eventLeadMinutes, .eventLeadMinutes) } }
    var notifyApprovals: Bool { didSet { persist(notifyApprovals, .notifyApprovals) } }
    var notifyPostSoon: Bool { didSet { persist(notifyPostSoon, .notifyPostSoon) } }
    var postLeadMinutes: Int { didSet { persist(postLeadMinutes, .postLeadMinutes) } }

    // How notifications appear
    var alertsInIsland: Bool { didSet { persist(alertsInIsland, .alertsInIsland) } }
    var alertSeconds: Double { didSet { persist(alertSeconds, .alertSeconds) } }
    var alertSound: Bool { didSet { persist(alertSound, .alertSound) } }
    var alertSoundName: String { didSet { persist(alertSoundName, .alertSoundName) } }
    var doNotDisturb: Bool { didSet { persist(doNotDisturb, .doNotDisturb) } }
    var workHoursOnly: Bool { didSet { persist(workHoursOnly, .workHoursOnly) } }
    var workStartHour: Int { didSet { persist(workStartHour, .workStartHour) } }
    var workEndHour: Int { didSet { persist(workEndHour, .workEndHour) } }
    var workdaysOnly: Bool { didSet { persist(workdaysOnly, .workdaysOnly) } }

    // Live activity
    var showLiveActivity: Bool { didSet { persist(showLiveActivity, .showLiveActivity) } }
    var liveLeadMinutes: Int { didSet { persist(liveLeadMinutes, .liveLeadMinutes) } }
    var liveShowsOverdue: Bool { didSet { persist(liveShowsOverdue, .liveShowsOverdue) } }
    var livePriorityOverMusic: Bool { didSet { persist(livePriorityOverMusic, .livePriorityOverMusic) } }

    // Links into the web app, appended to webURL.
    var tasksPath: String { didSet { persist(tasksPath, .tasksPath) } }
    var calendarPath: String { didSet { persist(calendarPath, .calendarPath) } }
    var approvalsPath: String { didSet { persist(approvalsPath, .approvalsPath) } }
    var contentPath: String { didSet { persist(contentPath, .contentPath) } }

    @ObservationIgnored var onConnectionChange: (() -> Void)?
    @ObservationIgnored var onIntervalChange: (() -> Void)?

    var isConfigured: Bool { endpoint != nil && !token.trimmingCharacters(in: .whitespaces).isEmpty }

    var endpoint: URL? {
        let text = serverURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: text), url.scheme == "https" || url.scheme == "http", url.host != nil else { return nil }
        return url
    }

    var visibleSections: [HubSection] { sectionOrder.filter { !hiddenSections.contains($0) } }

    func path(for section: HubSection) -> String {
        switch section {
        case .tasks: tasksPath
        case .calendar: calendarPath
        case .approvals: approvalsPath
        case .content: contentPath
        case .notifications: ""
        }
    }

    func moveSection(_ section: HubSection, by offset: Int) {
        guard let index = sectionOrder.firstIndex(of: section) else { return }
        let target = index + offset
        guard sectionOrder.indices.contains(target) else { return }
        sectionOrder.swapAt(index, target)
    }

    func setSection(_ section: HubSection, visible: Bool) {
        if visible { _ = hiddenSections.remove(section) } else { _ = hiddenSections.insert(section) }
    }

    /// Whether an alert may appear right now, given Do Not Disturb and work hours.
    func alertsAllowed(at date: Date = Date()) -> Bool {
        guard !doNotDisturb else { return false }
        let calendar = Calendar.current
        if workdaysOnly, calendar.isDateInWeekend(date) { return false }
        guard workHoursOnly else { return true }
        let hour = calendar.component(.hour, from: date)
        return workStartHour <= workEndHour ? (workStartHour..<workEndHour).contains(hour)
                                           : (hour >= workStartHour || hour < workEndHour)
    }

    func resetToDefaults() {
        for key in Key.allCases { defaults.removeObject(forKey: key.storageKey) }
        load()
    }

    // MARK: Storage

    private enum Key: String, CaseIterable {
        case showTab, serverURL, webURL, memberID, refreshMinutes, startTab
        case sectionOrder, hiddenSections, showCounts, showClientNames
        case taskScope, taskStatuses, minimumPriority, taskHorizonDays, showUndatedTasks, sortByPriority
        case calendarDays, pendingApprovalsOnly, contentDays, includeDraftPosts
        case notifyNewTask, notifyDueSoon, dueSoonDays, notifyOverdue, notifyEventSoon, eventLeadMinutes
        case notifyApprovals, notifyPostSoon, postLeadMinutes
        case alertsInIsland, alertSeconds, alertSound, alertSoundName, doNotDisturb
        case workHoursOnly, workStartHour, workEndHour, workdaysOnly
        case showLiveActivity, liveLeadMinutes, liveShowsOverdue, livePriorityOverMusic
        case tasksPath, calendarPath, approvalsPath, contentPath

        var storageKey: String { "hub." + rawValue }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var isLoading = false

    private static let defaultValues: [Key: Any] = [
        .showTab: true,
        .serverURL: "https://hub.acordmedia.com/api/mcp",
        .webURL: "https://hub.acordmedia.com",
        .memberID: "",
        .refreshMinutes: 2.0,
        .startTab: IslandStartTab.lastUsed.rawValue,
        .sectionOrder: HubSection.allCases.map(\.rawValue),
        .hiddenSections: [String](),
        .showCounts: true,
        .showClientNames: true,
        .taskScope: HubTaskScope.mine.rawValue,
        .taskStatuses: [HubTaskStatus.todo.rawValue, HubTaskStatus.inProgress.rawValue],
        .minimumPriority: HubPriority.none.rawValue,
        .taskHorizonDays: 0,
        .showUndatedTasks: true,
        .sortByPriority: false,
        .calendarDays: 7,
        .pendingApprovalsOnly: true,
        .contentDays: 7,
        .includeDraftPosts: false,
        .notifyNewTask: true,
        .notifyDueSoon: true,
        .dueSoonDays: 0,
        .notifyOverdue: true,
        .notifyEventSoon: true,
        .eventLeadMinutes: 10,
        .notifyApprovals: true,
        .notifyPostSoon: true,
        .postLeadMinutes: 30,
        .alertsInIsland: true,
        .alertSeconds: 6.0,
        .alertSound: false,
        .alertSoundName: "Glass",
        .doNotDisturb: false,
        .workHoursOnly: false,
        .workStartHour: 8,
        .workEndHour: 18,
        .workdaysOnly: false,
        .showLiveActivity: true,
        .liveLeadMinutes: 30,
        .liveShowsOverdue: false,
        .livePriorityOverMusic: true,
        .tasksPath: "",
        .calendarPath: "",
        .approvalsPath: "",
        .contentPath: "",
    ]

    init() {
        var registered: [String: Any] = [:]
        for (key, value) in Self.defaultValues { registered[key.storageKey] = value }
        defaults.register(defaults: registered)

        showTab = true; serverURL = ""; webURL = ""; token = ""; memberID = ""; refreshMinutes = 2
        startTab = .lastUsed; sectionOrder = HubSection.allCases; hiddenSections = []
        showCounts = true; showClientNames = true
        taskScope = .mine; taskStatuses = [.todo, .inProgress]; minimumPriority = .none
        taskHorizonDays = 0; showUndatedTasks = true; sortByPriority = false
        calendarDays = 7; pendingApprovalsOnly = true; contentDays = 7; includeDraftPosts = false
        notifyNewTask = true; notifyDueSoon = true; dueSoonDays = 0; notifyOverdue = true
        notifyEventSoon = true; eventLeadMinutes = 10; notifyApprovals = true
        notifyPostSoon = true; postLeadMinutes = 30
        alertsInIsland = true; alertSeconds = 6; alertSound = false; alertSoundName = "Glass"; doNotDisturb = false
        workHoursOnly = false; workStartHour = 8; workEndHour = 18; workdaysOnly = false
        showLiveActivity = true; liveLeadMinutes = 30; liveShowsOverdue = false; livePriorityOverMusic = true
        tasksPath = ""; calendarPath = ""; approvalsPath = ""; contentPath = ""
        load()
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        showTab = bool(.showTab)
        serverURL = string(.serverURL)
        webURL = string(.webURL)
        token = Keychain.read(account: "token") ?? ""
        memberID = string(.memberID)
        refreshMinutes = min(max(defaults.double(forKey: Key.refreshMinutes.storageKey), 0.5), 60)
        startTab = IslandStartTab(rawValue: string(.startTab)) ?? .lastUsed

        var order = strings(.sectionOrder).compactMap(HubSection.init(rawValue:))
        order += HubSection.allCases.filter { !order.contains($0) } // sections added in later versions
        sectionOrder = order
        hiddenSections = Set(strings(.hiddenSections).compactMap(HubSection.init(rawValue:)))
        showCounts = bool(.showCounts)
        showClientNames = bool(.showClientNames)

        taskScope = HubTaskScope(rawValue: string(.taskScope)) ?? .mine
        taskStatuses = Set(strings(.taskStatuses).compactMap(HubTaskStatus.init(rawValue:)))
        minimumPriority = HubPriority(rawValue: string(.minimumPriority)) ?? .none
        taskHorizonDays = int(.taskHorizonDays)
        showUndatedTasks = bool(.showUndatedTasks)
        sortByPriority = bool(.sortByPriority)

        calendarDays = max(int(.calendarDays), 1)
        pendingApprovalsOnly = bool(.pendingApprovalsOnly)
        contentDays = max(int(.contentDays), 1)
        includeDraftPosts = bool(.includeDraftPosts)

        notifyNewTask = bool(.notifyNewTask)
        notifyDueSoon = bool(.notifyDueSoon)
        dueSoonDays = int(.dueSoonDays)
        notifyOverdue = bool(.notifyOverdue)
        notifyEventSoon = bool(.notifyEventSoon)
        eventLeadMinutes = int(.eventLeadMinutes)
        notifyApprovals = bool(.notifyApprovals)
        notifyPostSoon = bool(.notifyPostSoon)
        postLeadMinutes = int(.postLeadMinutes)

        alertsInIsland = bool(.alertsInIsland)
        alertSeconds = defaults.double(forKey: Key.alertSeconds.storageKey)
        alertSound = bool(.alertSound)
        alertSoundName = string(.alertSoundName)
        doNotDisturb = bool(.doNotDisturb)
        workHoursOnly = bool(.workHoursOnly)
        workStartHour = int(.workStartHour)
        workEndHour = int(.workEndHour)
        workdaysOnly = bool(.workdaysOnly)

        showLiveActivity = bool(.showLiveActivity)
        liveLeadMinutes = int(.liveLeadMinutes)
        liveShowsOverdue = bool(.liveShowsOverdue)
        livePriorityOverMusic = bool(.livePriorityOverMusic)

        tasksPath = string(.tasksPath)
        calendarPath = string(.calendarPath)
        approvalsPath = string(.approvalsPath)
        contentPath = string(.contentPath)
    }

    private func bool(_ key: Key) -> Bool { defaults.bool(forKey: key.storageKey) }
    private func int(_ key: Key) -> Int { defaults.integer(forKey: key.storageKey) }
    private func string(_ key: Key) -> String { defaults.string(forKey: key.storageKey) ?? "" }
    private func strings(_ key: Key) -> [String] { defaults.stringArray(forKey: key.storageKey) ?? [] }

    private func persist(_ value: Any, _ key: Key) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key.storageKey)
    }
}

/// Minimal keychain wrapper for the Hub token.
enum Keychain {
    private static let service = "com.emresunar.DynamicIsland.acordhub"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if (read(account: account) ?? "") == value { return }
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}
