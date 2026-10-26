import Foundation

// MARK: - Records

struct HubTask: Identifiable, Equatable {
    let id: String
    var title: String
    var detail: String?
    var status: String
    var priority: HubPriority
    /// The Hub stores due dates as days; this is the start of that day, local time.
    var dueDay: Date?
    let assigneeID: String?
    let clientID: String?
    let projectID: String?
    /// Everyone on the task, when the Hub lists more than one assignee.
    var assigneeIDs: [String] = []
    /// The Hub's time estimate, in minutes.
    var estimateMinutes: Int?
    /// The estimate as the Hub's cards write it ("30 min", "2 h", "5 h+").
    var estimateLabel: String?

    /// All assignees, the main one first.
    var allAssigneeIDs: [String] {
        var ids = assigneeID.map { [$0] } ?? []
        for id in assigneeIDs where !ids.contains(id) { ids.append(id) }
        return ids
    }

    func isOverdue(now: Date) -> Bool {
        guard let dueDay else { return false }
        return dueDay < Calendar.current.startOfDay(for: now)
    }

    /// Whole days from today until the due day; negative when overdue.
    func daysLeft(now: Date) -> Int? {
        guard let dueDay else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: dueDay).day
    }
}

struct HubChecklistItem: Identifiable, Equatable {
    let id: String
    var title: String
    var isDone: Bool
}

/// A task with everything `get_task` adds: the checklist and the assignees' names.
struct HubTaskDetail: Equatable {
    var task: HubTask
    var checklist: [HubChecklistItem]
    var assigneeNames: [String]
}

/// A running focus timer on a task. Kept on this Mac; the Hub has no timer tool yet.
/// The running (or paused) timer. When the Hub has timer tools this mirrors its timer, so the
/// time lands in the Hub; otherwise it's kept on this Mac only.
struct HubTimer: Codable, Equatable {
    var taskID: String
    var title: String
    /// When the timer would have started had it never paused – elapsed = now − start.
    var start: Date
    /// Set while paused: the time on the clock.
    var pausedElapsed: TimeInterval?
    /// True when this is the Hub's own timer.
    var isHub: Bool?

    var isPaused: Bool { pausedElapsed != nil }

    func elapsed(at now: Date) -> TimeInterval {
        pausedElapsed ?? max(now.timeIntervalSince(start), 0)
    }
}

extension HubTimer {
    /// Reads the Hub's ActiveTimerDto (`get_active_timer`, `start_timer`, …).
    init?(hub json: [String: Any], now: Date = Date()) {
        guard let taskID = json["taskId"] as? String else { return nil }
        let elapsedMs = (json["elapsedMs"] as? NSNumber)?.doubleValue ?? 0
        let paused = json["isPaused"] as? Bool ?? false
        self.init(taskID: taskID,
                  title: json["taskTitle"] as? String ?? "Uppgift",
                  start: now.addingTimeInterval(-elapsedMs / 1000),
                  pausedElapsed: paused ? elapsedMs / 1000 : nil,
                  isHub: true)
    }
}

struct HubEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date?
    let isAllDay: Bool
    let clientName: String?
    let location: String?
    /// The video call (Meet) for a Google meeting.
    var meetLink: URL?
    /// The event in Google Calendar.
    var webLink: URL?
    /// Google's id (without the "meeting-" prefix) and calendar, for editing.
    var googleID: String?
    var calendarID: String?
    var detail: String?
    /// The calendar's colour, as hex.
    var colorHex: String?
    var attendeeCount: Int = 0

    var isMeeting: Bool { id.hasPrefix("meeting-") }

    var endDate: Date { end ?? start.addingTimeInterval(isAllDay ? 86_400 : 3600) }

    func isOngoing(now: Date) -> Bool {
        guard !isAllDay, start <= now else { return false }
        return (end ?? start.addingTimeInterval(3600)) > now
    }
}

struct HubApproval: Identifiable, Equatable {
    let id: String
    let title: String
    let status: String
    let clientName: String?
    let updated: Date?

    var isPending: Bool { !["APPROVED", "DONE", "CANCELLED", "ARCHIVED"].contains(status) }

    var statusTitle: String {
        switch status {
        case "APPROVED": "Godkänd"
        case "PENDING", "SENT", "WAITING": "Väntar på kund"
        case "CHANGES_REQUESTED", "REJECTED", "REVISION": "Ändringar önskas"
        case "DRAFT": "Utkast"
        default: status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct HubPost: Identifiable, Equatable {
    let id: String
    let title: String
    let date: Date?
    let status: String
    let platforms: [String]
    let clientName: String?

    var platformSymbol: String {
        switch platforms.first {
        case "LINKEDIN": "person.2.fill"
        case "TIKTOK": "music.note"
        case "YOUTUBE", "YOUTUBE_SHORTS": "play.rectangle.fill"
        case "INSTAGRAM", "FACEBOOK", "BOTH": "camera.fill"
        default: "square.and.pencil"
        }
    }

    var platformTitle: String {
        platforms.map { platform in
            switch platform {
            case "LINKEDIN": "LinkedIn"
            case "TIKTOK": "TikTok"
            case "YOUTUBE": "YouTube"
            case "YOUTUBE_SHORTS": "Shorts"
            case "INSTAGRAM": "Instagram"
            case "FACEBOOK": "Facebook"
            case "BOTH": "Meta"
            default: platform.capitalized
            }
        }.joined(separator: ", ")
    }
}

struct HubMember: Identifiable, Equatable {
    let id: String
    let name: String
    let email: String?
}

struct HubProject: Identifiable, Equatable {
    let id: String
    let name: String
    let clientID: String?
    let clientName: String?
}

/// Something that happened in the Hub, shown in the feed and, when allowed, as an island alert.
struct HubNotification: Identifiable, Equatable, Codable {
    enum Kind: String, Codable {
        case newTask, dueSoon, overdue, eventSoon, approval, postSoon, created
    }

    var id: String
    var kind: Kind
    var title: String
    var detail: String
    var date: Date
    var isRead = false
    /// The section to jump to when the notification is clicked.
    var section: String?
}

/// The one thing worth showing next to the notch while the island is closed.
struct HubLiveItem: Equatable {
    enum Kind: Equatable { case event, ongoingEvent, post, overdue, timer }
    var kind: Kind
    var title: String
    var date: Date?
    var count: Int = 0
}

// MARK: - Parsing

/// Lenient access to the Hub's JSON, which differs slightly between tools.
struct HubJSON {
    let raw: [String: Any]

    /// The array under `key`, or the first array in the payload, or the payload itself if it's an array.
    static func list(_ data: Data, key: String) -> [HubJSON] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let array = object as? [[String: Any]] { return array.map { HubJSON(raw: $0) } }
        guard let dictionary = object as? [String: Any] else { return [] }
        if let array = dictionary[key] as? [[String: Any]] { return array.map { HubJSON(raw: $0) } }
        for value in dictionary.values {
            if let array = value as? [[String: Any]] { return array.map { HubJSON(raw: $0) } }
        }
        return []
    }

    func string(_ keys: String...) -> String? {
        for key in keys {
            if let value = raw[key] as? String, !value.isEmpty { return value }
            if let value = raw[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }

    func bool(_ keys: String...) -> Bool? {
        for key in keys {
            if let value = raw[key] as? Bool { return value }
        }
        return nil
    }

    func strings(_ key: String) -> [String] {
        if let values = raw[key] as? [String] { return values }
        if let value = raw[key] as? String { return [value] }
        return []
    }

    /// A date under one of `keys`; also understands Google-style `{"dateTime": …}` / `{"date": …}` objects.
    func date(_ keys: String...) -> (date: Date, isDateOnly: Bool)? {
        for key in keys {
            if let text = raw[key] as? String, let parsed = HubDate.parse(text) { return parsed }
            if let nested = raw[key] as? [String: Any] {
                if let text = nested["dateTime"] as? String, let parsed = HubDate.parse(text) { return parsed }
                if let text = nested["date"] as? String, let parsed = HubDate.parse(text) { return (parsed.date, true) }
            }
        }
        return nil
    }
}

enum HubDate {
    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso = ISO8601DateFormatter()

    private static let local: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parse(_ text: String) -> (date: Date, isDateOnly: Bool)? {
        if let date = isoFractional.date(from: text) ?? iso.date(from: text) { return (date, false) }
        if let date = local.date(from: text) { return (date, false) }
        if text.count == 10, let date = day.date(from: text) { return (date, true) }
        return nil
    }

    /// "yyyy-MM-dd" in local time, the format the Hub's tools take.
    static func dayString(_ date: Date) -> String { day.string(from: date) }
}

extension HubTask {
    init?(_ json: HubJSON) {
        guard let id = json.string("id"), let title = json.string("title", "name") else { return nil }
        if json.string("archived_at") != nil { return nil }
        self.init(id: id,
                  title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                  detail: json.string("description"),
                  status: json.string("status") ?? "TODO",
                  priority: HubPriority(rawValue: json.string("priority") ?? "") ?? .none,
                  dueDay: json.date("due_date", "dueDate", "due").map { Calendar.current.startOfDay(for: $0.date) },
                  assigneeID: json.string("assignee_id", "assigneeId", "assignee"),
                  clientID: json.string("client_id", "clientId"),
                  projectID: json.string("project_id", "projectId"),
                  assigneeIDs: Self.assigneeIDs(json),
                  estimateMinutes: Self.estimate(json),
                  estimateLabel: json.string("time_estimate_label"))
    }

    private static func assigneeIDs(_ json: HubJSON) -> [String] {
        for key in ["assignee_ids", "assigneeIds", "assignees"] {
            if let ids = json.raw[key] as? [String] { return ids }
            if let people = json.raw[key] as? [[String: Any]] {
                return people.compactMap { HubJSON(raw: $0).string("id", "user_id", "userId") }
            }
        }
        return []
    }

    /// Minutes from whichever estimate field the Hub sends.
    private static func estimate(_ json: HubJSON) -> Int? {
        for key in ["time_estimate_label", "estimate_minutes", "estimated_minutes", "time_estimate_minutes", "duration_minutes", "estimate", "time_estimate", "estimated_time", "duration"] {
            if let number = json.raw[key] as? NSNumber { return number.intValue > 0 ? number.intValue : nil }
            if let text = json.raw[key] as? String, let minutes = parseDuration(text) { return minutes }
        }
        return nil
    }

    /// "30 min", "2 h", "1h 30m", "1,5 tim", "45".
    private static func parseDuration(_ text: String) -> Int? {
        let lower = text.lowercased().replacingOccurrences(of: ",", with: ".")
        if let minutes = Int(lower.trimmingCharacters(in: .whitespaces)) { return minutes > 0 ? minutes : nil }
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*(h|t|m)?"#) else { return nil }
        var total = 0.0
        for match in regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
            guard let valueRange = Range(match.range(at: 1), in: lower), let value = Double(lower[valueRange]) else { continue }
            let unit = Range(match.range(at: 2), in: lower).map { String(lower[$0]) } ?? "m"
            total += unit == "m" ? value : value * 60
        }
        return total > 0 ? Int(total.rounded()) : nil
    }
}

extension HubChecklistItem {
    init?(_ json: HubJSON) {
        guard let id = json.string("id"), let title = json.string("title", "text", "name", "content") else { return nil }
        let done = json.bool("done", "is_done", "isDone", "completed", "checked")
            ?? (json.string("completed_at", "completedAt", "done_at") != nil)
        self.init(id: id, title: title, isDone: done)
    }
}

extension HubTaskDetail {
    /// Reads `get_task`, which may wrap the task in `task` and name the checklist differently.
    init?(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let raw = (object["task"] as? [String: Any]) ?? object
        let json = HubJSON(raw: raw)
        guard let task = HubTask(json) ?? HubTask(HubJSON(raw: raw.filter { $0.key != "archived_at" })) else { return nil }
        var items: [[String: Any]] = []
        for key in ["checklist", "checklist_items", "checklistItems", "items", "subtasks", "sub_items"] {
            if let list = (raw[key] ?? object[key]) as? [[String: Any]] { items = list; break }
        }
        var names: [String] = []
        if let assignees = (raw["assignees"] ?? object["assignees"]) as? [[String: Any]] {
            names = assignees.compactMap { HubJSON(raw: $0).string("name", "username") }
        }
        self.init(task: task, checklist: items.compactMap { HubChecklistItem(HubJSON(raw: $0)) }, assigneeNames: names)
    }
}

extension HubEvent {
    init?(_ json: HubJSON) {
        guard let start = json.date("start", "start_at", "starts_at", "start_time", "startTime", "date") else { return nil }
        let end = json.date("end", "end_at", "ends_at", "end_time", "endTime")
        let title = json.string("title", "summary", "name") ?? "Händelse"
        self.init(id: json.string("id") ?? "\(title)-\(start.date.timeIntervalSince1970)",
                  title: title,
                  start: start.date,
                  end: end?.date,
                  isAllDay: json.bool("all_day", "allDay", "is_all_day") ?? start.isDateOnly,
                  clientName: json.string("client_name", "clientName"),
                  location: json.string("location", "place"),
                  meetLink: json.string("meet_link", "hangoutLink").flatMap(URL.init(string:)),
                  webLink: json.string("html_link", "htmlLink").flatMap(URL.init(string:)),
                  googleID: json.string("google_id"),
                  calendarID: json.string("calendar_id", "calendarId"),
                  detail: json.string("description", "notes"),
                  colorHex: json.string("color", "background_color"),
                  attendeeCount: Int(json.string("attendees") ?? "") ?? 0)
    }
}

extension HubApproval {
    init?(_ json: HubJSON) {
        guard let id = json.string("id") else { return nil }
        self.init(id: id,
                  title: json.string("title", "name") ?? "Godkännande",
                  status: (json.string("status") ?? "PENDING").uppercased(),
                  clientName: json.string("client_name", "clientName"),
                  updated: json.date("updated_at", "created_at")?.date)
    }
}

extension HubPost {
    init?(_ json: HubJSON) {
        guard let id = json.string("id") else { return nil }
        self.init(id: id,
                  title: json.string("title") ?? json.string("caption_preview") ?? "Inlägg",
                  date: json.date("scheduled_at", "date")?.date,
                  status: (json.string("status") ?? "DRAFT").uppercased(),
                  platforms: json.strings("platforms"),
                  clientName: json.string("client_name", "brand_name"))
    }
}

extension HubMember {
    init?(_ json: HubJSON) {
        guard let id = json.string("id"), let name = json.string("name", "username") else { return nil }
        self.init(id: id, name: name, email: json.string("email"))
    }
}

extension HubProject {
    init?(_ json: HubJSON) {
        guard let id = json.string("id"), let name = json.string("name") else { return nil }
        if json.bool("archived") == true { return nil }
        self.init(id: id, name: name, clientID: json.string("client_id"), clientName: json.string("client_name"))
    }
}
