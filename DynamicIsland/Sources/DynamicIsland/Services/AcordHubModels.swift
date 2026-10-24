import Foundation

// MARK: - Records

struct HubTask: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String?
    let status: String
    let priority: HubPriority
    /// The Hub stores due dates as days; this is the start of that day, local time.
    let dueDay: Date?
    let assigneeID: String?
    let clientID: String?
    let projectID: String?

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

struct HubEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date?
    let isAllDay: Bool
    let clientName: String?
    let location: String?

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
        case "APPROVED": "Approved"
        case "PENDING", "SENT", "WAITING": "Waiting for client"
        case "CHANGES_REQUESTED", "REJECTED", "REVISION": "Changes requested"
        case "DRAFT": "Draft"
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
    enum Kind: Equatable { case event, ongoingEvent, post, overdue }
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
                  projectID: json.string("project_id", "projectId"))
    }
}

extension HubEvent {
    init?(_ json: HubJSON) {
        guard let start = json.date("start", "start_at", "starts_at", "start_time", "startTime", "date") else { return nil }
        let end = json.date("end", "end_at", "ends_at", "end_time", "endTime")
        let title = json.string("title", "summary", "name") ?? "Event"
        self.init(id: json.string("id") ?? "\(title)-\(start.date.timeIntervalSince1970)",
                  title: title,
                  start: start.date,
                  end: end?.date,
                  isAllDay: json.bool("all_day", "allDay", "is_all_day") ?? start.isDateOnly,
                  clientName: json.string("client_name", "clientName"),
                  location: json.string("location", "place"))
    }
}

extension HubApproval {
    init?(_ json: HubJSON) {
        guard let id = json.string("id") else { return nil }
        self.init(id: id,
                  title: json.string("title", "name") ?? "Approval",
                  status: (json.string("status") ?? "PENDING").uppercased(),
                  clientName: json.string("client_name", "clientName"),
                  updated: json.date("updated_at", "created_at")?.date)
    }
}

extension HubPost {
    init?(_ json: HubJSON) {
        guard let id = json.string("id") else { return nil }
        self.init(id: id,
                  title: json.string("title") ?? json.string("caption_preview") ?? "Post",
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
