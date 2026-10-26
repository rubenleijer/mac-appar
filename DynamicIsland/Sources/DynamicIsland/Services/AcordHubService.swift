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
    /// The task opened in the island, if any.
    private(set) var selectedTaskID: String?
    private(set) var detail: HubTaskDetail?
    private(set) var isLoadingDetail = false
    /// Tasks and checklist items with a write on its way to the Hub.
    private(set) var busyIDs: Set<String> = []
    /// A short message at the bottom of the tab, with an optional undo.
    private(set) var toast: HubToast?
    private(set) var timer: HubTimer?
    /// Time tracked with the island's timer, per task.
    private(set) var trackedTime: [String: Double] = [:]

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
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var suppressNewTasksUntil = Date.distantPast

    private static let firedKeysKey = "hub.firedNotificationKeys"
    private static let feedKey = "hub.notificationFeed"
    private static let baselineKey = "hub.didBaseline"
    private static let timerKey = "hub.timer"
    private static let trackedKey = "hub.trackedTime"
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
        if let data = UserDefaults.standard.data(forKey: Self.timerKey) {
            timer = try? JSONDecoder().decode(HubTimer.self, from: data)
        }
        trackedTime = UserDefaults.standard.dictionary(forKey: Self.trackedKey) as? [String: Double] ?? [:]
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
                guard horizon > 0 else { return task.dueDay != nil || settings.showUndatedTasks }
                guard let due = task.dueDay else { return false }
                if due < today { return settings.includeOverdue }
                guard let limit = Calendar.current.date(byAdding: .day, value: horizon, to: today) else { return true }
                return due < limit
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
        if let timer { return HubLiveItem(kind: .timer, title: timer.title, date: timer.start) }
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
            return HubLiveItem(kind: .overdue, title: "Försenad", count: overdueCount)
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
        toolNames = nil
        hubTimeTools = nil
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
            if toolNames == nil {
                do {
                    let names = Set(try await client.listTools())
                    toolNames = names
                    hubTimeTools = names.contains("start_timer")
                    HubLog.write("tools: \(names.sorted().joined(separator: ", "))")
                } catch {
                    HubLog.write("tools/list failed: \(error.localizedDescription)")
                }
            }

            let needsDirectory = Date().timeIntervalSince(lastDirectoryLoad) > 30 * 60
            async let team = Self.attempt(if: needsDirectory) { try await client.call("list_team") }
            async let projects = Self.attempt(if: needsDirectory) { try await client.call("list_projects") }
            async let clients = Self.attempt(if: needsDirectory) {
                try await client.call("list_clients", ["include_archived": .bool(true)])
            }

            var approvalsMissing = false
            if toolNames?.contains("dashboard_snapshot") == true {
                var arguments: [String: HubArgument] = ["from": .string(from), "to": .string(to)]
                if !settings.memberID.isEmpty { arguments["user_id"] = .string(settings.memberID) }
                let data = try await client.call("dashboard_snapshot", arguments)
                guard let snapshot = Self.object(data) else { throw HubError("Hubben skickade ett oläsbart svar") }
                guard !Task.isCancelled else { return }
                approvalsMissing = !apply(snapshot: snapshot)
            } else {
                approvalsMissing = try await refreshTool(by: client, from: from, to: to)
            }

            let teamData = await team
            let projectData = await projects
            let clientData = await clients
            guard !Task.isCancelled else { return }
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
            evaluateNotifications(approvalsMissing: approvalsMissing)
        } catch {
            guard !Task.isCancelled else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            HubLog.write("refresh failed: \(message)")
            status = .failed(message)
        }
    }

    /// Reads `dashboard_snapshot`: everything in one call. Returns whether approvals came through.
    @discardableResult
    private func apply(snapshot: [String: Any]) -> Bool {
        func list(_ key: String, _ inner: String) -> [HubJSON]? {
            guard let value = snapshot[key], JSONSerialization.isValidJSONObject(value) || value is [Any],
                  let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
            if let error = (value as? [String: Any])?["error"] as? String {
                HubLog.write("snapshot \(key): \(error)")
                return nil
            }
            return HubJSON.list(data, key: inner)
        }
        if let rows = list("tasks", "tasks") { tasks = Self.unique(rows.compactMap { HubTask($0) }) }
        let approvalRows = list("approvals", "approvals")
        if let approvalRows { approvals = approvalRows.compactMap { HubApproval($0) } }
        if let rows = list("posts", "posts") { posts = rows.compactMap { HubPost($0) } }
        var calendar = list("calendar_events", "events")?.compactMap { HubEvent($0) } ?? events.filter { !$0.id.hasPrefix("meeting-") }
        if let meetings = snapshot["meetings"] as? [String: Any] {
            if meetings["connected"] as? Bool == true {
                calendarConnection = .connected
                let rows = (meetings["events"] as? [[String: Any]]) ?? []
                calendar += rows.compactMap(Self.meeting)
            } else if let error = meetings["error"] as? String {
                HubLog.write("meetings: \(error)")
            } else {
                calendarConnection = .notConnected(meetings["message"] as? String ?? "Google Kalender är inte kopplad",
                                                   meetings["connect_path"] as? String ?? "/api/google/calendar/connect")
            }
        }
        events = calendar
        if snapshot.keys.contains("timer") {
            hubTimeTools = true
            let hubTimer = (snapshot["timer"] as? [String: Any]).flatMap { HubTimer(hub: $0) }
            if hubTimer != nil || timer?.isHub == true { timer = hubTimer }
            if let error = snapshot["timer_error"] as? String { HubLog.write("timer: \(error)") }
        }
        if let minutes = (snapshot["time_today_minutes"] as? NSNumber)?.doubleValue { loggedToday = minutes * 60 }
        return approvalRows != nil
    }

    /// A Google meeting row from the Hub, tagged so it can be told apart from Hub events.
    private static func meeting(_ row: [String: Any]) -> HubEvent? {
        var raw = row
        let googleID = row["id"] as? String ?? UUID().uuidString
        raw["id"] = "meeting-" + googleID
        raw["google_id"] = googleID
        return HubEvent(HubJSON(raw: raw))
    }

    /// The older Hub, without `dashboard_snapshot`: one call per list. Returns whether approvals were missing.
    private func refreshTool(by client: AcordHubClient, from: String, to: String) async throws -> Bool {
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
        let todoData = try await todo
        let doingData = try await doing
        var taskData = [todoData, doingData]
        let unclearData = await unclear
        if let unclearData { taskData.append(unclearData) }
        let calendarData = await calendar
        let approvalData = await approvals
        let contentData = await content
        tasks = Self.unique(taskData.flatMap { HubJSON.list($0, key: "tasks").compactMap { HubTask($0) } })
        if let calendarData { events = HubJSON.list(calendarData, key: "events").compactMap { HubEvent($0) } }
        if let approvalData { self.approvals = HubJSON.list(approvalData, key: "approvals").compactMap { HubApproval($0) } }
        if let contentData { posts = HubJSON.list(contentData, key: "posts").compactMap { HubPost($0) } }
        await syncHubTime()
        return approvalData == nil
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

    // MARK: Calendar

    /// First day of the three-day calendar.
    private(set) var calendarStart = Calendar.current.startOfDay(for: Date())
    /// Events fetched for days outside the refresh window (looking back, or far ahead).
    private(set) var rangeEvents: [HubEvent] = []
    private(set) var selectedEventID: String?

    var calendarDays: [Date] {
        (0..<3).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: calendarStart) }
    }

    var selectedEvent: HubEvent? {
        guard let selectedEventID else { return nil }
        return (events + rangeEvents).first { $0.id == selectedEventID }
    }

    /// Everything on a day: Google meetings and Hub events, all-day first.
    func calendarEvents(on day: Date) -> [HubEvent] {
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        var seen = Set<String>()
        return (events + rangeEvents)
            .filter { seen.insert($0.id).inserted }
            .filter { $0.start < end && $0.endDate > start }
            .sorted { $0.start < $1.start }
    }

    func moveCalendar(by days: Int) {
        let target = Calendar.current.date(byAdding: .day, value: days, to: calendarStart) ?? calendarStart
        setCalendarStart(target)
    }

    func showToday() { setCalendarStart(Date()) }

    func select(event: HubEvent?) {
        selectedEventID = event?.id
    }

    private func setCalendarStart(_ day: Date) {
        calendarStart = Calendar.current.startOfDay(for: day)
        selectedEventID = nil
        let today = Calendar.current.startOfDay(for: Date())
        let last = Calendar.current.date(byAdding: .day, value: 2, to: calendarStart) ?? calendarStart
        // The refresh covers today and the next month; other days are fetched on demand.
        if calendarStart < today || last > (Calendar.current.date(byAdding: .day, value: 30, to: today) ?? today) {
            Task { await loadCalendarRange() }
        }
    }

    private func loadCalendarRange() async {
        let from = HubDate.dayString(calendarStart)
        let to = HubDate.dayString(Calendar.current.date(byAdding: .day, value: 2, to: calendarStart) ?? calendarStart)
        var found: [HubEvent] = []
        if let data = await perform("list_calendar_events", ["from": .string(from), "to": .string(to), "limit": .int(300)],
                                    showsErrors: false) {
            found += HubJSON.list(data, key: "events").compactMap { HubEvent($0) }
        }
        if !settings.memberID.isEmpty,
           let data = await perform("list_my_meetings", ["user_id": .string(settings.memberID), "from": .string(from), "to": .string(to)],
                                    showsErrors: false),
           let rows = Self.object(data)?["events"] as? [[String: Any]] {
            found += rows.compactMap(Self.meeting)
        }
        rangeEvents = found
    }

    struct MeetingDraft {
        var title = ""
        var start = Date()
        var end = Date().addingTimeInterval(3600)
        var allDay = false
        var location = ""
        var detail = ""
        var attendees = ""
        var addMeet = false
    }

    /// Creates or changes a Google meeting. Returns an error message, or nil when it worked.
    func saveMeeting(_ draft: MeetingDraft, editing event: HubEvent?) async -> String? {
        guard !settings.memberID.isEmpty else { return "Välj dig själv under ”Du är” i inställningarna först." }
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        var arguments: [String: HubArgument] = [
            "user_id": .string(settings.memberID),
            "title": .string(draft.title.trimmingCharacters(in: .whitespaces)),
            "start": .string(iso.string(from: draft.start)),
            "end": .string(iso.string(from: draft.end)),
            "all_day": .bool(draft.allDay),
            "location": draft.location.isEmpty ? .null : .string(draft.location),
            "description": draft.detail.isEmpty ? .null : .string(draft.detail),
            "attendees": .strings(draft.attendees.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
                .map(String.init).filter { $0.contains("@") }),
            "add_meet": .bool(draft.addMeet),
        ]
        let tool: String
        if let event, let googleID = event.googleID {
            tool = "update_meeting"
            arguments["event_id"] = .string(googleID)
            if let calendar = event.calendarID { arguments["calendar_id"] = .string(calendar) }
        } else {
            tool = "create_meeting"
        }
        guard await perform(tool, arguments, showsErrors: false) != nil else {
            return "Kunde inte spara i Google Kalender. Är kalendern kopplad i Hubben?"
        }
        showToast(event == nil ? "Lade till ”\(draft.title)”" : "Sparade ”\(draft.title)”")
        await reloadCalendar()
        return nil
    }

    func deleteMeeting(_ event: HubEvent) {
        guard let googleID = event.googleID, !settings.memberID.isEmpty else { return }
        guard Self.confirm("Ta bort ”\(event.title)”?", detail: event.attendeeCount > 0 ? "Deltagarna får besked." : nil,
                           button: "Ta bort") else { return }
        var arguments: [String: HubArgument] = ["user_id": .string(settings.memberID), "event_id": .string(googleID)]
        if let calendar = event.calendarID { arguments["calendar_id"] = .string(calendar) }
        selectedEventID = nil
        events.removeAll { $0.id == event.id }
        rangeEvents.removeAll { $0.id == event.id }
        Task {
            if await perform("delete_meeting", arguments) != nil {
                showToast("Tog bort ”\(event.title)”")
            }
            await reloadCalendar()
        }
    }

    private func reloadCalendar() async {
        refresh(force: true)
        await loadCalendarRange()
    }

    // MARK: Task actions

    var selectedTask: HubTask? {
        guard let id = selectedTaskID else { return nil }
        return detail?.task ?? tasks.first { $0.id == id }
    }

    /// Opens a task inside the island (nil goes back to the list) and loads its checklist.
    func select(_ task: HubTask?) {
        selectedTaskID = task?.id
        detail = task.map { HubTaskDetail(task: $0, checklist: [], assigneeNames: []) }
        if let task { loadDetail(task.id) } else { isLoadingDetail = false }
    }

    func loadDetail(_ id: String) {
        isLoadingDetail = true
        Task {
            let data = await perform("get_task", ["task_id": .string(id)], showsErrors: false)
            guard selectedTaskID == id else { return }
            isLoadingDetail = false
            if let data, let loaded = HubTaskDetail(data) { detail = loaded }
        }
    }

    func complete(_ task: HubTask) {
        if settings.confirmComplete,
           !Self.confirm("Markera ”\(task.title)” som klar?", button: "Markera som klar") { return }
        if timer?.taskID == task.id { stopTimer() }
        if selectedTaskID == task.id { select(nil) }
        setStatus(task, "DONE", toast: "Klar: \(task.title)", undoable: true)
    }

    func toggleInProgress(_ task: HubTask) {
        setStatus(task, task.status == HubTaskStatus.inProgress.rawValue ? "TODO" : "IN_PROGRESS")
    }

    func setStatus(_ task: HubTask, _ status: String, toast message: String? = nil, undoable: Bool = false) {
        let old = task.status
        guard old != status else { return }
        updateLocal(task.id) { $0.status = status }
        if let message {
            var undo: (@MainActor () -> Void)?
            if undoable {
                undo = { [weak self] in
                    var restored = task
                    restored.status = status
                    self?.setStatus(restored, old)
                }
            }
            showToast(message, undo: undo)
        }
        write(task.id, ["status": .string(status)]) { $0.status = old }
    }

    func reschedule(_ task: HubTask, to day: Date?) {
        let old = task.dueDay
        let newDay = day.map { Calendar.current.startOfDay(for: $0) }
        updateLocal(task.id) { $0.dueDay = newDay }
        let value: HubArgument = newDay.map { HubArgument.string(HubDate.dayString($0)) } ?? HubArgument.null
        write(task.id, ["due_date": value]) { $0.dueDay = old }
        if let newDay {
            showToast("Flyttad till \(Self.dayName(newDay, now: now)): \(task.title)")
        } else {
            showToast("Datum borttaget: \(task.title)")
        }
    }

    func setPriority(_ task: HubTask, _ priority: HubPriority) {
        let old = task.priority
        updateLocal(task.id) { $0.priority = priority }
        write(task.id, ["priority": .string(priority.rawValue)]) { $0.priority = old }
    }

    /// Saves a new title and description. Returns false if the Hub refused.
    func updateText(_ task: HubTask, title: String, description: String) async -> Bool {
        var arguments: [String: HubArgument] = [:]
        if title != task.title { arguments["title"] = .string(title) }
        if description != (task.detail ?? "") { arguments["description"] = description.isEmpty ? .null : .string(description) }
        guard !arguments.isEmpty else { return true }
        arguments["task_id"] = .string(task.id)
        guard await perform("update_task", arguments, busy: task.id) != nil else { return false }
        updateLocal(task.id) {
            $0.title = title
            $0.detail = description.isEmpty ? nil : description
        }
        return true
    }

    func delete(_ task: HubTask) {
        guard Self.confirm("Ta bort ”\(task.title)”?", detail: "Den tas bort från Acord Hub för gott.", button: "Ta bort") else { return }
        if timer?.taskID == task.id { cancelTimer() }
        if selectedTaskID == task.id { select(nil) }
        let snapshot = tasks
        tasks.removeAll { $0.id == task.id }
        Task {
            if await perform("delete_task", ["task_id": .string(task.id)], busy: task.id) == nil {
                tasks = snapshot
            } else {
                showToast("Borttagen: \(task.title)")
            }
        }
    }

    func openTask(_ task: HubTask) { openWeb(.tasks, id: task.id) }

    // MARK: Checklist

    func toggle(_ item: HubChecklistItem) {
        guard let index = detail?.checklist.firstIndex(where: { $0.id == item.id }) else { return }
        let done = !item.isDone
        detail?.checklist[index].isDone = done
        Task {
            if await perform("update_checklist_item", ["item_id": .string(item.id), "done": .bool(done)], busy: item.id) == nil,
               let index = detail?.checklist.firstIndex(where: { $0.id == item.id }) {
                detail?.checklist[index].isDone = !done
            }
        }
    }

    func addChecklistItem(to taskID: String, title: String) async -> Bool {
        guard await perform("add_checklist_item", ["task_id": .string(taskID), "title": .string(title)], busy: taskID) != nil else {
            return false
        }
        if selectedTaskID == taskID { loadDetail(taskID) }
        return true
    }

    func deleteChecklistItem(_ item: HubChecklistItem) {
        detail?.checklist.removeAll { $0.id == item.id }
        Task {
            if await perform("delete_checklist_item", ["item_id": .string(item.id)], busy: item.id) == nil,
               let id = selectedTaskID {
                loadDetail(id)
            }
        }
    }

    // MARK: Timer

    /// Whether the Hub's MCP has the timer tools (`start_timer`, …). Until it does, the timer
    /// runs on this Mac only.
    private(set) var hubTimeTools: Bool?
    /// The tools the Hub's MCP server offers, read once per connection.
    @ObservationIgnored private var toolNames: Set<String>?
    /// Whether the user's Google Calendar reaches the island (through the Hub).
    private(set) var calendarConnection: CalendarConnection = .unknown

    enum CalendarConnection: Equatable {
        case unknown, connected
        /// Not connected in the Hub; the message and the Hub path that connects it.
        case notConnected(String, String)
    }

    /// Opens the Hub page that connects Google Calendar.
    func connectCalendar() {
        var path = "/api/google/calendar/connect"
        if case .notConnected(_, let hubPath) = calendarConnection { path = hubPath }
        var address = settings.webURL.trimmingCharacters(in: .whitespaces)
        if address.hasSuffix("/") { address.removeLast() }
        guard let url = URL(string: address + path) else { return }
        NSWorkspace.shared.open(url)
    }
    /// Time logged today in the Hub, from `list_time_entries`.
    private(set) var loggedToday: TimeInterval?

    private var canUseHubTime: Bool { hubTimeTools == true && !settings.memberID.isEmpty }

    func startTimer(_ task: HubTask) {
        if settings.timerStartsTask, task.status != HubTaskStatus.inProgress.rawValue { setStatus(task, "IN_PROGRESS") }
        guard canUseHubTime else {
            if timer != nil { stopTimer(silently: true) }
            timer = HubTimer(taskID: task.id, title: task.title, start: Date())
            saveTimer()
            return
        }
        let previous = timer
        timer = HubTimer(taskID: task.id, title: task.title, start: Date(), isHub: true) // show it at once
        Task {
            let data = await perform("start_timer", ["user_id": .string(settings.memberID), "task_id": .string(task.id),
                                                    "force": .bool(true)], busy: task.id)
            guard let data, let json = Self.object(data) else {
                timer = previous
                return
            }
            if let dto = json["timer"] as? [String: Any], let hubTimer = HubTimer(hub: dto) { timer = hubTimer }
            if previous != nil, previous?.taskID != task.id { refreshTimeToday() }
        }
    }

    func stopTimer(silently: Bool = false, completeTask: Bool = false) {
        guard let current = timer else { return }
        guard current.isHub == true, canUseHubTime else {
            let elapsed = current.elapsed(at: Date())
            trackedTime[current.taskID, default: 0] += elapsed
            defaults.set(trackedTime, forKey: Self.trackedKey)
            timer = nil
            saveTimer()
            if !silently { showToast("Mätte \(Self.durationText(elapsed)) på \(current.title) – bara på den här Macen") }
            return
        }
        timer = nil
        Task {
            var arguments: [String: HubArgument] = ["user_id": .string(settings.memberID)]
            if completeTask { arguments["complete_task"] = .bool(true) }
            guard let data = await perform("stop_timer", arguments, busy: current.taskID) else {
                timer = current
                return
            }
            let json = Self.object(data)
            if !silently {
                let logged = (json?["logged_ms"] as? NSNumber).map { $0.doubleValue / 1000 } ?? current.elapsed(at: Date())
                showToast("Loggade \(Self.durationText(logged)) på \(current.title)")
            }
            refreshTimeToday()
            if completeTask { refresh(force: true) }
        }
    }

    func pauseTimer() {
        guard var current = timer, !current.isPaused else { return }
        let elapsed = current.elapsed(at: Date())
        current.pausedElapsed = elapsed
        timer = current
        guard current.isHub == true, canUseHubTime else { return saveTimer() }
        Task {
            if let data = await perform("pause_timer", ["user_id": .string(settings.memberID)], busy: current.taskID) {
                if let dto = Self.object(data)?["timer"] as? [String: Any], let hubTimer = HubTimer(hub: dto) { timer = hubTimer }
                showToast("Pausad – \(Self.durationText(elapsed)) loggat")
                refreshTimeToday()
            } else {
                current.pausedElapsed = nil
                timer = current
            }
        }
    }

    func resumeTimer() {
        guard var current = timer, let elapsed = current.pausedElapsed else { return }
        current.pausedElapsed = nil
        current.start = Date().addingTimeInterval(-elapsed)
        timer = current
        guard current.isHub == true, canUseHubTime else { return saveTimer() }
        Task {
            if let data = await perform("resume_timer", ["user_id": .string(settings.memberID)], busy: current.taskID),
               let dto = Self.object(data)?["timer"] as? [String: Any], let hubTimer = HubTimer(hub: dto) {
                timer = hubTimer
            }
        }
    }

    func cancelTimer() {
        timer = nil
        saveTimer()
    }

    func toggleTimer(_ task: HubTask) {
        guard let timer, timer.taskID == task.id else { return startTimer(task) }
        if timer.isPaused { resumeTimer() } else { stopTimer() }
    }

    /// Logs time without a timer – on a task, straight into the Hub.
    func logTime(_ minutes: Int, on task: HubTask, note: String? = nil) {
        guard canUseHubTime else {
            trackedTime[task.id, default: 0] += TimeInterval(minutes * 60)
            defaults.set(trackedTime, forKey: Self.trackedKey)
            showToast("Loggade \(Self.durationText(TimeInterval(minutes * 60))) – bara på den här Macen")
            return
        }
        Task {
            var arguments: [String: HubArgument] = ["user_id": .string(settings.memberID), "task_id": .string(task.id),
                                                    "minutes": .int(minutes)]
            if let note, !note.isEmpty { arguments["note"] = .string(note) }
            guard await perform("log_time", arguments, busy: task.id) != nil else { return }
            showToast("Loggade \(Self.durationText(TimeInterval(minutes * 60))) på \(task.title)")
            refreshTimeToday()
        }
    }

    /// Time tracked on a task: the running timer here, plus anything kept on this Mac.
    func timeTracked(on id: String, now: Date) -> TimeInterval {
        var total = trackedTime[id] ?? 0
        if let timer, timer.taskID == id { total += timer.elapsed(at: now) }
        return total
    }

    /// Picks up the Hub's timer (also one started in the browser) and today's total.
    private func syncHubTime() async {
        guard !settings.memberID.isEmpty else { return }
        let me = settings.memberID
        do {
            let data = try await client.call("get_active_timer", ["user_id": .string(me)])
            hubTimeTools = true
            let dto = Self.object(data)?["timer"] as? [String: Any]
            let hubTimer = dto.flatMap { HubTimer(hub: $0) }
            // Keep a local timer if the Hub has none; otherwise the Hub decides.
            if hubTimer != nil || timer?.isHub == true { timer = hubTimer }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            if message.localizedCaseInsensitiveContains("not found") || message.localizedCaseInsensitiveContains("unknown tool") {
                hubTimeTools = false
            }
            return
        }
        if let data = try? await client.call("list_time_entries", ["user_id": .string(me)]),
           let minutes = (Self.object(data)?["total_minutes"] as? NSNumber)?.doubleValue {
            loggedToday = minutes * 60
        }
    }

    private func refreshTimeToday() {
        Task { await syncHubTime() }
    }

    private static func object(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func saveTimer() {
        if let timer, let data = try? JSONEncoder().encode(timer) {
            defaults.set(data, forKey: Self.timerKey)
        } else {
            defaults.removeObject(forKey: Self.timerKey)
        }
    }

    nonisolated static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "under en minut" }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    // MARK: Toast

    func showToast(_ message: String, undo: (@MainActor () -> Void)? = nil) {
        toast = HubToast(message: message, undo: undo)
        toastTask?.cancel()
        let seconds = undo == nil ? 3.0 : 6.0
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func performUndo() {
        let action = toast?.undo
        toast = nil
        action?()
    }

    // MARK: Writing

    private func updateLocal(_ id: String, _ change: (inout HubTask) -> Void) {
        if let index = tasks.firstIndex(where: { $0.id == id }) { change(&tasks[index]) }
        if var task = detail?.task, task.id == id {
            change(&task)
            detail?.task = task
        }
    }

    /// Sends an `update_task` and puts the old value back if the Hub refuses it.
    private func write(_ id: String, _ fields: [String: HubArgument], rollback: @escaping (inout HubTask) -> Void) {
        var arguments = fields
        arguments["task_id"] = .string(id)
        suppressNewTasksUntil = Date().addingTimeInterval(120) // a recurring task's next copy isn't news
        Task {
            if await perform("update_task", arguments, busy: id) == nil {
                updateLocal(id, rollback)
            } else if fields["status"] != nil {
                refresh(force: true)
            }
        }
    }

    @discardableResult
    private func perform(_ tool: String, _ arguments: [String: HubArgument], busy id: String? = nil,
                         showsErrors: Bool = true) async -> Data? {
        guard let endpoint = settings.endpoint else { return nil }
        if let id { busyIDs.insert(id) }
        defer { if let id { busyIDs.remove(id) } }
        await client.configure(.init(endpoint: endpoint, token: settings.token))
        do {
            return try await client.call(tool, arguments)
        } catch {
            HubLog.write("\(tool) failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            if showsErrors {
                showToast("Kunde inte spara: " + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
            }
            return nil
        }
    }

    static func confirm(_ message: String, detail: String? = nil, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        if let detail { alert.informativeText = detail }
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Avbryt")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Actions

    /// Creates a task in the Hub. Assigns it to the user unless `assigneeID` says otherwise.
    func createTask(title: String, dueDate: Date?, projectID: String?, assigneeID: String?,
                    priority: HubPriority = .low) async throws {
        var arguments: [String: HubArgument] = ["title": .string(title), "priority": .string(priority.rawValue)]
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
        guard let endpoint = settings.endpoint else { return "Ange en giltig serveradress" }
        guard !settings.token.isEmpty else { return "Ange en token" }
        await client.configure(.init(endpoint: endpoint, token: settings.token))
        do {
            let data = try await client.call("list_team")
            team = HubJSON.list(data, key: "team").compactMap { HubMember($0) }
            lastDirectoryLoad = Date()
            refresh(force: true)
            return "Ansluten – \(team.count) i teamet"
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Opens the Hub in the browser. A path containing `{id}` links straight to the item.
    func openWeb(_ section: HubSection? = nil, id: String? = nil) {
        var address = settings.webURL.trimmingCharacters(in: .whitespaces)
        if let section {
            var path = settings.path(for: section).trimmingCharacters(in: .whitespaces)
            if path.contains("{id}") {
                if let id {
                    path = path.replacingOccurrences(of: "{id}", with: id)
                } else {
                    path = path.replacingOccurrences(of: "/{id}", with: "").replacingOccurrences(of: "{id}", with: "")
                }
            }
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
        let alert = HubNotification(id: "test-\(UUID().uuidString)", kind: .eventSoon, title: "Test från Acord Hub",
                                    detail: "Så här ser notiser ut i notchen", date: Date(),
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
        if let known = knownTaskIDs, settings.notifyNewTask, Date() > suppressNewTasksUntil {
            for task in relevant where !known.contains(task.id) {
                let from = clientName(for: task).map { " · \($0)" } ?? ""
                fresh.append(.init(id: "new-\(task.id)", kind: .newTask, title: task.title,
                                   detail: "Ny uppgift" + from, date: now, section: HubSection.tasks.rawValue))
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
                    if old == nil { parts.insert("Nytt godkännande", at: 0) }
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
                                    detail: "Försenad sedan \(Self.dayName(due, now: now))" + client, date: now,
                                    section: HubSection.tasks.rawValue))
            } else if settings.notifyDueSoon, days <= settings.dueSoonDays {
                result.append(.init(id: "due-\(task.id)-\(HubDate.dayString(due))", kind: .dueSoon, title: task.title,
                                    detail: "Ska vara klar \(Self.dayName(due, now: now))" + client, date: now,
                                    section: HubSection.tasks.rawValue))
            }
        }

        if settings.notifyEventSoon {
            let lead = TimeInterval(settings.eventLeadMinutes * 60)
            for event in events where !event.isAllDay && event.start > now && event.start.timeIntervalSince(now) <= lead {
                let minutes = max(Int((event.start.timeIntervalSince(now) / 60).rounded()), 1)
                result.append(.init(id: "event-\(event.id)-\(Int(event.start.timeIntervalSince1970))", kind: .eventSoon,
                                    title: event.title,
                                    detail: "Börjar om \(minutes) min" + (event.location.map { " · \($0)" } ?? ""),
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
                                    detail: "\(post.platformTitle)-inlägg publiceras om \(minutes) min", date: now,
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

    nonisolated static func dayName(_ day: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "idag" }
        if calendar.isDateInTomorrow(day) { return "imorgon" }
        if calendar.isDateInYesterday(day) { return "igår" }
        let formatter = DateFormatter()
        let days = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day ?? 99)
        formatter.locale = Locale(identifier: "sv_SE")
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

/// A short message at the bottom of the Hub tab.
struct HubToast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var undo: (@MainActor () -> Void)?

    static func == (lhs: HubToast, rhs: HubToast) -> Bool { lhs.id == rhs.id }
}

/// Errors and connection facts, written to ~/Library/Logs/Dynamic Island Hub.log (kept short).
@MainActor
enum HubLog {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Dynamic Island Hub.log")
    private static var last = ""

    static func write(_ message: String) {
        guard message != last else { return } // a refresh every 30 s shouldn't repeat itself
        last = message
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 200_000 {
            try? FileManager.default.removeItem(at: url)
        }
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
