import AppKit
import Foundation

/// Keeps the island in sync with Acord Hub: tasks, calendar, approvals and content, plus
/// notifications derived from what changes between refreshes.
@MainActor @Observable
final class AcordHubService {
    enum Status: Equatable {
        case notConfigured, loading, ready, failed(String)
    }

    let settings: HubSettings

    private(set) var status: Status = .notConfigured
    private(set) var lastUpdated: Date?
    private(set) var tasks: [HubTask] = []
    private(set) var events: [HubEvent] = []
    private(set) var approvals: [HubApproval] = []
    private(set) var posts: [HubPost] = []
    private(set) var team: [HubMember] = []
    private(set) var projects: [HubProject] = []
    private(set) var clientNames: [String: String] = [:]
    private(set) var notifications: [HubNotification] = []
    private(set) var latestAlert: HubNotification?
    /// How many notifications arrived together with `latestAlert`.
    private(set) var latestAlertBatch = 0
    /// Ticks every 30 seconds so countdowns and "due today" stay current without a refresh.
    private(set) var now = Date()
    var section: HubSection = .tasks

    @ObservationIgnored var onAlert: ((HubNotification) -> Void)?
    @ObservationIgnored private let client = AcordHubClient()
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var clockTimer: Timer?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var lastDirectoryLoad = Date.distantPast
    @ObservationIgnored private var knownTaskIDs: Set<String>?
    @ObservationIgnored private var approvalStatuses: [String: String]?
    @ObservationIgnored private var firedKeys: [String]
    @ObservationIgnored private var firedKeySet: Set<String>
    @ObservationIgnored private let defaults = UserDefaults.standard

    private static let firedKeysKey = "hub.firedNotificationKeys"
    private static let feedKey = "hub.notificationFeed"
    private static let baselineKey = "hub.didBaseline"
    private static let maxFeed = 80
    private static let maxFiredKeys = 1500

    init(settings: HubSettings) {
        self.settings = settings
        let keys = UserDefaults.standard.stringArray(forKey: Self.firedKeysKey) ?? []
        firedKeys = keys
        firedKeySet = Set(keys)
        if let data = UserDefaults.standard.data(forKey: Self.feedKey),
           let feed = try? JSONDecoder().decode([HubNotification].self, from: data) {
            notifications = feed
        }
        section = settings.visibleSections.first ?? .tasks
    }

    func start() {
        settings.onConnectionChange = { [weak self] in self?.reconnect() }
        settings.onIntervalChange = { [weak self] in self?.scheduleRefreshTimer() }
        scheduleRefreshTimer()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.now = Date()
                self.evaluateTimedNotifications()
            }
        }
        refresh(force: true)
    }

    func stop() {
        refreshTimer?.invalidate()
        clockTimer?.invalidate()
        refreshTask?.cancel()
    }

    // MARK: Derived data

    var isConfigured: Bool { settings.isConfigured }
    var me: HubMember? { team.first { $0.id == settings.memberID } }
    var unreadCount: Int { notifications.lazy.filter { !$0.isRead }.count }

    /// Tasks after the user's scope, status, priority and horizon filters, most urgent first.
    var visibleTasks: [HubTask] {
        let now = self.now
        let statuses = Set(settings.taskStatuses.map(\.rawValue))
        let horizon = settings.taskHorizonDays
        let today = Calendar.current.startOfDay(for: now)
        return scopedTasks
            .filter { statuses.contains($0.status) && $0.priority >= settings.minimumPriority }
            .filter { task in
                guard let due = task.dueDay else { return settings.showUndatedTasks }
                guard horizon > 0, let limit = Calendar.current.date(byAdding: .day, value: horizon, to: today) else { return true }
                return due <= limit
            }
            .sorted { a, b in
                if settings.sortByPriority, a.priority != b.priority { return a.priority > b.priority }
                switch (a.dueDay, b.dueDay) {
                case let (x?, y?) where x != y: return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.priority > b.priority
                }
            }
    }

    var visibleEvents: [HubEvent] {
        let now = self.now
        let limit = Calendar.current.date(byAdding: .day, value: settings.calendarDays, to: Calendar.current.startOfDay(for: now)) ?? now
        return events
            .filter { ($0.end ?? $0.start) >= (($0.isAllDay) ? Calendar.current.startOfDay(for: now) : now) && $0.start < limit }
            .sorted { $0.start < $1.start }
    }

    var visibleApprovals: [HubApproval] {
        approvals
            .filter { !settings.pendingApprovalsOnly || $0.isPending }
            .sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
    }

    var visiblePosts: [HubPost] {
        let now = self.now
        let limit = Calendar.current.date(byAdding: .day, value: settings.contentDays, to: Calendar.current.startOfDay(for: now)) ?? now
        return posts
            .filter { $0.status == "SCHEDULED" || (settings.includeDraftPosts && $0.status == "DRAFT") }
            .filter { post in
                guard let date = post.date else { return settings.includeDraftPosts }
                return date >= Calendar.current.startOfDay(for: now) && date < limit
            }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    func count(for section: HubSection) -> Int {
        switch section {
        case .tasks: visibleTasks.count
        case .calendar: visibleEvents.count
        case .approvals: visibleApprovals.count
        case .content: visiblePosts.count
        case .notifications: unreadCount
        }
    }

    var overdueCount: Int { visibleTasks.filter { $0.isOverdue(now: now) }.count }

    /// The next meeting, post or the overdue pile, shown next to the notch while the island is closed.
    var liveItem: HubLiveItem? {
        guard settings.showLiveActivity, lastUpdated != nil else { return nil }
        let now = self.now
        let lead = TimeInterval(settings.liveLeadMinutes * 60)
        if let ongoing = events.first(where: { $0.isOngoing(now: now) }) {
            return HubLiveItem(kind: .ongoingEvent, title: ongoing.title, date: ongoing.end)
        }
        if let next = events.filter({ !$0.isAllDay && $0.start > now && $0.start.timeIntervalSince(now) <= lead })
            .min(by: { $0.start < $1.start }) {
            return HubLiveItem(kind: .event, title: next.title, date: next.start)
        }
        if let post = posts.filter({ $0.status == "SCHEDULED" && ($0.date.map { $0 > now && $0.timeIntervalSince(now) <= lead } ?? false) })
            .min(by: { ($0.date ?? now) < ($1.date ?? now) }) {
            return HubLiveItem(kind: .post, title: post.title, date: post.date)
        }
        if settings.liveShowsOverdue, overdueCount > 0 {
            return HubLiveItem(kind: .overdue, title: "Overdue", count: overdueCount)
        }
        return nil
    }

    func clientName(for task: HubTask) -> String? {
        guard settings.showClientNames else { return nil }
        if let id = task.clientID, let name = clientNames[id] { return name }
        if let id = task.projectID, let project = projects.first(where: { $0.id == id }) { return project.clientName ?? project.name }
        return nil
    }

    func memberName(_ id: String?) -> String? {
        guard let id else { return nil }
        return team.first { $0.id == id }?.name.split(separator: " ").first.map(String.init)
    }

    private var scopedTasks: [HubTask] {
        let me = settings.memberID
        guard !me.isEmpty else { return tasks }
        switch settings.taskScope {
        case .all: return tasks
        case .mine: return tasks.filter { $0.assigneeID == me }
        case .unassignedAndMine: return tasks.filter { $0.assigneeID == me || $0.assigneeID == nil }
        }
    }

    // MARK: Refresh

    /// Refreshes unless that happened in the last 20 seconds (or `force` is set).
    func refresh(force: Bool = false) {
        guard settings.isConfigured else {
            status = .notConfigured
            return
        }
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < 20 { return }
        guard refreshTask == nil else { return }
        if lastUpdated == nil || status == .notConfigured { status = .loading }
        refreshTask = Task { [weak self] in
            await self?.performRefresh()
            if !Task.isCancelled { self?.refreshTask = nil }
        }
    }

    private func reconnect() {
        refreshTask?.cancel()
        refreshTask = nil
        tasks = []; events = []; approvals = []; posts = []; team = []; projects = []; clientNames = [:]
        knownTaskIDs = nil
        approvalStatuses = nil
        lastUpdated = nil
        lastDirectoryLoad = .distantPast
        refresh(force: true)
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: settings.refreshMinutes * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(force: true) }
        }
        refreshTimer?.tolerance = 10
    }

    private func performRefresh() async {
        guard let endpoint = settings.endpoint else { return }
        await client.configure(.init(endpoint: endpoint, token: settings.token))

        let today = Calendar.current.startOfDay(for: Date())
        let from = HubDate.dayString(today)
        let to = HubDate.dayString(Calendar.current.date(byAdding: .day, value: 31, to: today) ?? today)
        let client = self.client

        do {
            try await client.connect()
            async let todo = client.call("list_tasks", ["status": .string("TODO")])
            async let doing = client.call("list_tasks", ["status": .string("IN_PROGRESS")])
            async let unclear = Self.attempt { try await client.call("list_tasks", ["status": .string("UNCLEAR")]) }
            async let calendar = Self.attempt {
                try await client.call("list_calendar_events", ["from": .string(from), "to": .string(to), "limit": .int(300)])
            }
            async let approvals = Self.attempt { try await client.call("list_approvals", ["limit": .int(100)]) }
            async let content = Self.attempt {
                try await client.call("list_content_posts", ["from": .string(from), "to": .string(to), "limit": .int(200)])
            }
            let needsDirectory = Date().timeIntervalSince(lastDirectoryLoad) > 30 * 60
            async let team = Self.attempt(if: needsDirectory) { try await client.call("list_team") }
            async let projects = Self.attempt(if: needsDirectory) { try await client.call("list_projects") }
            async let clients = Self.attempt(if: needsDirectory) {
                try await client.call("list_clients", ["include_archived": .bool(true)])
            }

            let todoData = try await todo
            let doingData = try await doing
            var taskData = [todoData, doingData]
            let unclearData = await unclear
            if let unclearData { taskData.append(unclearData) }
            let newTasks = taskData.flatMap { HubJSON.list($0, key: "tasks").compactMap { HubTask($0) } }
            let calendarData = await calendar
            let approvalData = await approvals
            let contentData = await content
            let teamData = await team
            let projectData = await projects
            let clientData = await clients
            guard !Task.isCancelled else { return }

            tasks = Self.unique(newTasks)
            if let calendarData { events = HubJSON.list(calendarData, key: "events").compactMap { HubEvent($0) } }
            if let approvalData { self.approvals = HubJSON.list(approvalData, key: "approvals").compactMap { HubApproval($0) } }
            if let contentData { posts = HubJSON.list(contentData, key: "posts").compactMap { HubPost($0) } }
            if let teamData {
                self.team = HubJSON.list(teamData, key: "team").compactMap { HubMember($0) }
                lastDirectoryLoad = Date()
            }
            if let projectData { self.projects = HubJSON.list(projectData, key: "projects").compactMap { HubProject($0) } }
            if let clientData {
                var names: [String: String] = [:]
                for json in HubJSON.list(clientData, key: "clients") {
                    if let id = json.string("id"), let name = json.string("name") { names[id] = name }
                }
                clientNames = names
            }

            now = Date()
            lastUpdated = now
            status = .ready
            evaluateNotifications(approvalsMissing: approvalData == nil)
        } catch {
            guard !Task.isCancelled else { return }
            status = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Runs an optional request; a section that fails keeps showing its previous data.
    private nonisolated static func attempt(if enabled: Bool = true, _ work: @Sendable () async throws -> Data) async -> Data? {
        guard enabled else { return nil }
        return try? await work()
    }

    private static func unique(_ tasks: [HubTask]) -> [HubTask] {
        var seen = Set<String>()
        return tasks.filter { seen.insert($0.id).inserted }
    }

    // MARK: Actions

    /// Creates a task in the Hub. Assigns it to the user unless `assigneeID` says otherwise.
    func createTask(title: String, dueDate: Date?, projectID: String?, assigneeID: String?) async throws {
        var arguments: [String: HubArgument] = ["title": .string(title)]
        if let dueDate { arguments["due_date"] = .string(HubDate.dayString(dueDate)) }
        if let projectID, !projectID.isEmpty { arguments["project_id"] = .string(projectID) }
        if let assigneeID, !assigneeID.isEmpty { arguments["assignee"] = .string(assigneeID) }
        if let endpoint = settings.endpoint {
            await client.configure(.init(endpoint: endpoint, token: settings.token))
        }
        let data = try await client.call("create_task", arguments)
        // The task we just made shouldn't announce itself as new.
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let created = (object["task"] as? [String: Any]) ?? object
            if let id = created["id"] as? String { knownTaskIDs?.insert(id) }
        }
        refresh(force: true)
    }

    /// Checks the connection from the settings window.
    func testConnection() async -> String {
        guard let endpoint = settings.endpoint else { return "Enter a valid server address" }
        guard !settings.token.isEmpty else { return "Enter a token" }
        await client.configure(.init(endpoint: endpoint, token: settings.token))
        do {
            let data = try await client.call("list_team")
            team = HubJSON.list(data, key: "team").compactMap { HubMember($0) }
            lastDirectoryLoad = Date()
            refresh(force: true)
            return "Connected – \(team.count) team members"
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func openWeb(_ section: HubSection? = nil) {
        var address = settings.webURL.trimmingCharacters(in: .whitespaces)
        if let section {
            let path = settings.path(for: section).trimmingCharacters(in: .whitespaces)
            if !path.isEmpty {
                if address.hasSuffix("/") { address.removeLast() }
                address += path.hasPrefix("/") ? path : "/" + path
            }
        }
        guard let url = URL(string: address), url.scheme != nil else { return }
        NSWorkspace.shared.open(url)
    }

    /// Shows a sample alert so the user can see their alert settings in action.
    func sendTestAlert() {
        let alert = HubNotification(id: "test-\(UUID().uuidString)", kind: .eventSoon, title: "Test from Acord Hub",
                                    detail: "This is how notifications look in the notch", date: Date(),
                                    section: HubSection.notifications.rawValue)
        latestAlert = alert
        latestAlertBatch = 1
        if settings.alertSound { NSSound(named: NSSound.Name(settings.alertSoundName))?.play() }
        onAlert?(alert)
    }

    func markRead(_ notification: HubNotification) {
        guard let index = notifications.firstIndex(where: { $0.id == notification.id }), !notifications[index].isRead else { return }
        notifications[index].isRead = true
        saveFeed()
    }

    func markAllRead() {
        guard unreadCount > 0 else { return }
        for index in notifications.indices { notifications[index].isRead = true }
        saveFeed()
    }

    func clearNotifications() {
        notifications = []
        saveFeed()
    }

    // MARK: Notifications

    /// Compares this refresh with the last one. The very first run only records what exists, so
    /// a fresh install doesn't announce every overdue task at once.
    private func evaluateNotifications(approvalsMissing: Bool) {
        let isFirstRun = !defaults.bool(forKey: Self.baselineKey)
        var fresh: [HubNotification] = []
        let now = self.now

        let relevant = scopedTasks.filter { Set(settings.taskStatuses.map(\.rawValue)).contains($0.status) }
        if let known = knownTaskIDs, settings.notifyNewTask {
            for task in relevant where !known.contains(task.id) {
                let from = clientName(for: task).map { " · \($0)" } ?? ""
                fresh.append(.init(id: "new-\(task.id)", kind: .newTask, title: task.title,
                                   detail: "New task" + from, date: now, section: HubSection.tasks.rawValue))
            }
        }
        knownTaskIDs = Set(tasks.map(\.id))

        if !approvalsMissing {
            let statuses = Dictionary(approvals.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
            if let previous = approvalStatuses, settings.notifyApprovals {
                for approval in approvals {
                    let old = previous[approval.id]
                    guard old != approval.status else { continue }
                    var parts = [approval.statusTitle]
                    if old == nil { parts.insert("New approval", at: 0) }
                    if let client = approval.clientName { parts.append(client) }
                    let detail = parts.joined(separator: " · ")
                    fresh.append(.init(id: "approval-\(approval.id)-\(approval.status)", kind: .approval,
                                       title: approval.title, detail: detail, date: now,
                                       section: HubSection.approvals.rawValue))
                }
            }
            approvalStatuses = statuses
        }

        fresh += timedNotifications(now: now)

        if isFirstRun {
            remember(fresh.map(\.id))
            defaults.set(true, forKey: Self.baselineKey)
            return
        }
        deliver(fresh)
    }

    /// Deadlines and things about to start; checked on every clock tick as well as on refresh.
    private func evaluateTimedNotifications() {
        guard status == .ready, defaults.bool(forKey: Self.baselineKey) else { return }
        deliver(timedNotifications(now: now))
    }

    private func timedNotifications(now: Date) -> [HubNotification] {
        var result: [HubNotification] = []
        let relevant = scopedTasks.filter { Set(settings.taskStatuses.map(\.rawValue)).contains($0.status) }

        for task in relevant {
            guard let days = task.daysLeft(now: now), let due = task.dueDay else { continue }
            let client = clientName(for: task).map { " · \($0)" } ?? ""
            if days < 0 {
                guard settings.notifyOverdue else { continue }
                result.append(.init(id: "overdue-\(task.id)-\(HubDate.dayString(due))", kind: .overdue, title: task.title,
                                    detail: "Overdue since \(Self.dayName(due, now: now))" + client, date: now,
                                    section: HubSection.tasks.rawValue))
            } else if settings.notifyDueSoon, days <= settings.dueSoonDays {
                result.append(.init(id: "due-\(task.id)-\(HubDate.dayString(due))", kind: .dueSoon, title: task.title,
                                    detail: "Due \(Self.dayName(due, now: now))" + client, date: now,
                                    section: HubSection.tasks.rawValue))
            }
        }

        if settings.notifyEventSoon {
            let lead = TimeInterval(settings.eventLeadMinutes * 60)
            for event in events where !event.isAllDay && event.start > now && event.start.timeIntervalSince(now) <= lead {
                let minutes = max(Int((event.start.timeIntervalSince(now) / 60).rounded()), 1)
                result.append(.init(id: "event-\(event.id)-\(Int(event.start.timeIntervalSince1970))", kind: .eventSoon,
                                    title: event.title,
                                    detail: "Starts in \(minutes) min" + (event.location.map { " · \($0)" } ?? ""),
                                    date: now, section: HubSection.calendar.rawValue))
            }
        }

        if settings.notifyPostSoon {
            let lead = TimeInterval(settings.postLeadMinutes * 60)
            for post in posts where post.status == "SCHEDULED" {
                guard let date = post.date, date > now, date.timeIntervalSince(now) <= lead else { continue }
                let minutes = max(Int((date.timeIntervalSince(now) / 60).rounded()), 1)
                result.append(.init(id: "post-\(post.id)-\(Int(date.timeIntervalSince1970))", kind: .postSoon,
                                    title: post.title,
                                    detail: "\(post.platformTitle) post goes out in \(minutes) min", date: now,
                                    section: HubSection.content.rawValue))
            }
        }
        return result
    }

    private func deliver(_ candidates: [HubNotification]) {
        let fresh = candidates.filter { !firedKeySet.contains($0.id) }
        guard !fresh.isEmpty else { return }
        remember(fresh.map(\.id))

        notifications.insert(contentsOf: fresh, at: 0)
        if notifications.count > Self.maxFeed { notifications.removeLast(notifications.count - Self.maxFeed) }
        saveFeed()

        guard settings.alertsInIsland, settings.alertsAllowed(at: now) else { return }
        let order: [HubNotification.Kind] = [.eventSoon, .postSoon, .approval, .newTask, .dueSoon, .overdue, .created]
        let top = fresh.min { (order.firstIndex(of: $0.kind) ?? 9) < (order.firstIndex(of: $1.kind) ?? 9) } ?? fresh[0]
        latestAlert = top
        latestAlertBatch = fresh.count
        if settings.alertSound { NSSound(named: NSSound.Name(settings.alertSoundName))?.play() }
        onAlert?(top)
    }

    private func remember(_ keys: [String]) {
        for key in keys where firedKeySet.insert(key).inserted { firedKeys.append(key) }
        if firedKeys.count > Self.maxFiredKeys {
            firedKeys.removeFirst(firedKeys.count - Self.maxFiredKeys)
            firedKeySet = Set(firedKeys)
        }
        defaults.set(firedKeys, forKey: Self.firedKeysKey)
    }

    private func saveFeed() {
        if let data = try? JSONEncoder().encode(notifications) { defaults.set(data, forKey: Self.feedKey) }
    }

    static func dayName(_ day: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "today" }
        if calendar.isDateInTomorrow(day) { return "tomorrow" }
        if calendar.isDateInYesterday(day) { return "yesterday" }
        let formatter = DateFormatter()
        let days = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day ?? 99)
        formatter.setLocalizedDateFormatFromTemplate(days < 7 ? "EEEE" : "d MMM")
        return formatter.string(from: day)
    }

    // MARK: Preview

    #if DEBUG
    func showPreview() {
        let today = Calendar.current.startOfDay(for: Date())
        func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: today)! }
        let me: String? = settings.memberID.isEmpty ? nil : settings.memberID
        tasks = [
            HubTask(id: "1", title: "Send offer to Charlie AK", detail: nil, status: "TODO", priority: .dangerous,
                    dueDay: day(-1), assigneeID: me, clientID: nil, projectID: nil),
            HubTask(id: "2", title: "Moodboard for the spring campaign", detail: nil, status: "IN_PROGRESS", priority: .high,
                    dueDay: day(0), assigneeID: me, clientID: nil, projectID: nil),
            HubTask(id: "3", title: "Script for the seminar ad", detail: nil, status: "TODO", priority: .medium,
                    dueDay: day(2), assigneeID: me, clientID: nil, projectID: nil),
            HubTask(id: "4", title: "Monthly report", detail: nil, status: "TODO", priority: .low,
                    dueDay: nil, assigneeID: me, clientID: nil, projectID: nil),
        ]
        events = [HubEvent(id: "e", title: "Status meeting", start: Date().addingTimeInterval(12 * 60), end: nil,
                           isAllDay: false, clientName: nil, location: "Sickla")]
        status = .ready
        lastUpdated = Date()
        now = Date()
    }

    func showPreviewAlert() {
        latestAlert = HubNotification(id: "preview", kind: .eventSoon, title: "Status meeting",
                                      detail: "Starts in 10 min · Sickla", date: Date())
        latestAlertBatch = 1
    }
    #endif
}
