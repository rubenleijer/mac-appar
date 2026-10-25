import AppKit
import SwiftUI

/// Acord Hub inside the island: tasks, calendar, approvals, content and notifications.
struct HubTab: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let hub = model.hub
        VStack(alignment: .leading, spacing: 6) {
            // The section names give way when the island is narrow.
            ViewThatFits(in: .horizontal) {
                toolbar(showsTitles: true)
                toolbar(showsTitles: false)
            }
            .zIndex(1)
            Group {
                if !hub.isConfigured && hub.lastUpdated == nil {
                    HubSetupState()
                } else if hub.lastUpdated == nil {
                    switch hub.status {
                    case .failed(let message): HubErrorState(message: message)
                    default: HubLoadingState()
                    }
                } else {
                    sectionContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .bottom) {
                if let toast = hub.toast {
                    HubToastView(toast: toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: hub.toast)
            .animation(.spring(response: 0.38, dampingFraction: 0.85), value: hub.selectedTaskID)
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity)
        .frame(height: model.hubContentHeight - 14, alignment: .top)
    }

    private var currentSection: HubSection {
        let visible = model.hub.settings.visibleSections
        return visible.contains(model.hub.section) ? model.hub.section : (visible.first ?? .tasks)
    }

    // MARK: Toolbar

    private func toolbar(showsTitles: Bool) -> some View {
        let hub = model.hub
        return HStack(spacing: 4) {
            ForEach(hub.settings.visibleSections) { section in
                HubSectionButton(section: section,
                                 showsTitle: showsTitles,
                                 count: hub.settings.showCounts ? hub.count(for: section) : 0,
                                 isAlert: section == .tasks && hub.overdueCount > 0,
                                 isSelected: currentSection == section) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if hub.section == section || section != .tasks { hub.select(nil) }
                        hub.section = section
                    }
                }
            }
            Spacer(minLength: 4)
            if currentSection == .tasks && hub.selectedTaskID == nil {
                TodayToggle(isOn: hub.settings.showsTodayOnly) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { hub.settings.showsTodayOnly.toggle() }
                }
            }
            if case .failed(let message) = hub.status, hub.lastUpdated != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .help(message)
            }
            if currentSection == .notifications {
                Button { hub.markAllRead() } label: {
                    Image(systemName: "checkmark.circle").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(IslandButtonStyle(diameter: 24))
                .help("Mark all as read")
                .disabled(hub.unreadCount == 0)
            } else if currentSection == .tasks {
                Button { model.onQuickAddTask?() } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(IslandButtonStyle(diameter: 24))
                .help("New task")
                .disabled(!hub.isConfigured)
            }
            Button { hub.refresh(force: true) } label: {
                RefreshIcon(isSpinning: hub.status == .loading)
            }
            .buttonStyle(IslandButtonStyle(diameter: 24))
            .help(updatedText)
            .disabled(!hub.isConfigured)
            Button {
                if let task = hub.selectedTask { hub.openTask(task) } else { hub.openWeb(currentSection == .notifications ? nil : currentSection) }
            } label: {
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(IslandButtonStyle(diameter: 24))
            .help("Open Acord Hub")
        }
        .frame(height: 26)
    }

    private var updatedText: String {
        guard let date = model.hub.lastUpdated else { return "Refresh" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date())) – click to refresh"
    }

    // MARK: Sections

    @ViewBuilder
    private var sectionContent: some View {
        let hub = model.hub
        switch currentSection {
        case .tasks:
            if hub.selectedTaskID != nil {
                HubTaskDetailView()
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
            } else {
                HubList(items: hub.visibleTasks,
                        empty: ("checkmark.circle", hub.settings.showsTodayOnly ? "Nothing left for today" : "Nothing on your list")) { task in
                    HubTaskRow(task: task)
                }
                .transition(.opacity)
            }
        case .calendar:
            HubList(items: hub.visibleEvents, empty: ("calendar", "No events the next \(hub.settings.calendarDays) days")) { event in
                HubEventRow(event: event)
            }
        case .approvals:
            HubList(items: hub.visibleApprovals,
                    empty: ("checkmark.seal", hub.settings.pendingApprovalsOnly ? "No approvals waiting" : "No approvals")) { approval in
                HubApprovalRow(approval: approval)
            }
        case .content:
            HubList(items: hub.visiblePosts, empty: ("square.and.pencil", "Nothing scheduled the next \(hub.settings.contentDays) days")) { post in
                HubPostRow(post: post)
            }
        case .notifications:
            HubList(items: hub.notifications, empty: ("bell.slash", "No notifications")) { notification in
                HubNotificationRow(notification: notification)
            }
        }
    }
}

// MARK: - List

private struct HubList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let empty: (symbol: String, text: String)
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        if items.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: empty.symbol).font(.system(size: 14, weight: .medium))
                Text(empty.text).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        } else {
            IslandScroll {
                VStack(spacing: 0) {
                    ForEach(items) { item in row(item) }
                }
                // Room under the last item, so it never sits on the island's rounded bottom.
                .padding(.bottom, 10)
            }
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.94),
                                         .init(color: .black.opacity(0.2), location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
    }
}

/// A clickable row with the hover plate used elsewhere in the island.
private struct HubRow<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    var subtitleColor: Color = .white.opacity(0.5)
    var titleOpacity: Double = 1
    let action: () -> Void
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                leading().frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(titleOpacity))
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(subtitleColor)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                trailing()
            }
            .padding(.horizontal, 6)
            .frame(height: IslandLayout.hubRowHeight)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(isHovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(title)
    }
}

struct PriorityBadge: View {
    let priority: HubPriority
    var inProgress = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(color, lineWidth: 2)
                .frame(width: 16, height: 16)
            if inProgress {
                Circle().trim(from: 0, to: 0.5).fill(color).frame(width: 9, height: 9).rotationEffect(.degrees(-90))
            }
            if priority == .dangerous {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(color)
                    .opacity(inProgress ? 0 : 1)
            }
        }
        .help(priority == .none ? "No priority" : "\(priority.title) priority")
    }

    private var color: Color { priority.color }
}

extension HubPriority {
    var color: Color {
        switch self {
        case .dangerous: Color(red: 1, green: 0.36, blue: 0.34)
        case .high: .orange
        case .medium: .yellow
        case .low: .white.opacity(0.45)
        case .none: .white.opacity(0.28)
        }
    }
}

private struct HubEventRow: View {
    let event: HubEvent
    @Environment(IslandModel.self) private var model

    var body: some View {
        let now = model.hub.now
        let isNow = event.isOngoing(now: now)
        let parts = [dayText, event.clientName, event.location]
        HubRow(title: event.title,
               subtitle: parts.compactMap { $0 }.joined(separator: " · "),
               action: { model.hub.openWeb(.calendar) }) {
            VStack(spacing: 0) {
                Text(event.isAllDay ? "All" : event.start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isNow ? Color.green : Color.white)
                Text(event.isAllDay ? "day" : event.start.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .fixedSize()
        } trailing: {
            if isNow {
                Text("Now")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.green))
            } else if !event.isAllDay, event.start > now, event.start.timeIntervalSince(now) < 3 * 3600 {
                Text("in " + shortDuration(event.start.timeIntervalSince(now)))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .contextMenu {
            Button("Open in Acord Hub") { model.hub.openWeb(.calendar) }
            Button("Copy Title") { copyToPasteboard(event.title) }
        }
    }

    private var dayText: String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(event.start) ? "Today"
            : calendar.isDateInTomorrow(event.start) ? "Tomorrow"
            : event.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        guard !event.isAllDay, let end = event.end else { return day }
        return day + " – until " + end.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
    }
}

private struct HubApprovalRow: View {
    let approval: HubApproval
    @Environment(IslandModel.self) private var model

    var body: some View {
        HubRow(title: approval.title,
               subtitle: [approval.statusTitle, approval.clientName].compactMap { $0 }.joined(separator: " · "),
               action: { model.hub.openWeb(.approvals) }) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(color)
        } trailing: {
            if let updated = approval.updated {
                Text(updated.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .contextMenu {
            Button("Open in Acord Hub") { model.hub.openWeb(.approvals) }
        }
    }

    private var symbol: String {
        switch approval.status {
        case "APPROVED": "checkmark.seal.fill"
        case "CHANGES_REQUESTED", "REJECTED", "REVISION": "arrow.uturn.backward.circle.fill"
        default: "hourglass.circle.fill"
        }
    }

    private var color: Color {
        switch approval.status {
        case "APPROVED": .green
        case "CHANGES_REQUESTED", "REJECTED", "REVISION": .orange
        default: .purple
        }
    }
}

private struct HubPostRow: View {
    let post: HubPost
    @Environment(IslandModel.self) private var model

    var body: some View {
        let when = post.date.map { date in
            Calendar.current.isDateInToday(date) ? "Today " + date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute())
        }
        HubRow(title: post.title.replacingOccurrences(of: "\n", with: " "),
               subtitle: [when, post.platformTitle, post.status == "DRAFT" ? "Draft" : nil, post.clientName]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
               titleOpacity: post.status == "DRAFT" ? 0.6 : 1,
               action: { model.hub.openWeb(.content) }) {
            Image(systemName: post.platformSymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(post.platforms.first == "LINKEDIN" ? Color.blue.opacity(0.8) : Color.pink.opacity(0.7)))
        } trailing: {
            EmptyView()
        }
        .contextMenu {
            Button("Open in Acord Hub") { model.hub.openWeb(.content) }
            Button("Copy Title") { copyToPasteboard(post.title) }
        }
    }
}

private struct HubNotificationRow: View {
    let notification: HubNotification
    @Environment(IslandModel.self) private var model

    var body: some View {
        let hub = model.hub
        HubRow(title: notification.title,
               subtitle: notification.detail,
               titleOpacity: notification.isRead ? 0.6 : 1,
               action: {
                   hub.markRead(notification)
                   if let section = notification.section.flatMap(HubSection.init(rawValue:)),
                      hub.settings.visibleSections.contains(section) {
                       withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { hub.section = section }
                   }
               }) {
            Image(systemName: notification.kind.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(notification.kind.color)
        } trailing: {
            HStack(spacing: 6) {
                Text(notification.date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.4))
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
                    .opacity(notification.isRead ? 0 : 1)
            }
        }
        .contextMenu {
            Button("Mark as Read") { hub.markRead(notification) }
            Button("Mark All as Read") { hub.markAllRead() }
            Divider()
            Button("Clear All Notifications") { hub.clearNotifications() }
        }
    }
}

extension HubNotification.Kind {
    var symbol: String {
        switch self {
        case .newTask: "plus.circle.fill"
        case .dueSoon: "clock.fill"
        case .overdue: "exclamationmark.circle.fill"
        case .eventSoon: "calendar.circle.fill"
        case .approval: "checkmark.seal.fill"
        case .postSoon: "paperplane.circle.fill"
        case .created: "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .newTask: .blue
        case .dueSoon: .orange
        case .overdue: Color(red: 1, green: 0.36, blue: 0.34)
        case .eventSoon: .green
        case .approval: .purple
        case .postSoon: .pink
        case .created: .green
        }
    }
}

// MARK: - Toolbar pieces

private struct HubSectionButton: View {
    let section: HubSection
    var showsTitle = true
    let count: Int
    let isAlert: Bool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: section.symbol).font(.system(size: 10.5, weight: .semibold))
                if isSelected && showsTitle {
                    Text(section.title).font(.system(size: 11, weight: .semibold)).fixedSize()
                }
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(section == .notifications || isAlert ? Color.white : Color.white.opacity(0.6))
                        .padding(.horizontal, 4)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Capsule().fill(badgeColor))
                }
            }
            .foregroundStyle(.white.opacity(isSelected ? 1 : 0.5))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Capsule().fill(.white.opacity(isSelected ? 0.14 : (isHovering ? 0.07 : 0))))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(section.title)
    }

    private var badgeColor: Color {
        if section == .notifications { return .blue }
        if isAlert { return Color(red: 1, green: 0.36, blue: 0.34).opacity(0.9) }
        return .white.opacity(0.12)
    }
}

private struct RefreshIcon: View {
    let isSpinning: Bool
    @State private var angle = 0.0

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 11, weight: .bold))
            .rotationEffect(.degrees(angle))
            .onChange(of: isSpinning, initial: true) { _, spinning in
                if spinning {
                    withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { angle = 360 }
                } else {
                    withAnimation(.default) { angle = 0 }
                }
            }
    }
}

// MARK: - States

private struct HubSetupState: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "rectangle.connected.to.line.below")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 58, height: 58)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.1)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Connect Acord Hub")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Add the Hub’s MCP address and your token in settings to see tasks, meetings, approvals and posts here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    CapsuleButton(title: "Open Settings") { model.onOpenSettings?() }
                    CapsuleButton(title: "Open Acord Hub") { model.hub.openWeb() }
                }
                .padding(.top, 7)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }
}

private struct HubLoadingState: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading Acord Hub…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HubErrorState: View {
    let message: String
    @Environment(IslandModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            Label("Couldn’t load Acord Hub", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            HStack(spacing: 8) {
                CapsuleButton(title: "Try Again") { model.hub.refresh(force: true) }
                CapsuleButton(title: "Settings") { model.onOpenSettings?() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Helpers

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// "45s", "12m", "1h 5m", "3h".
func shortDuration(_ seconds: TimeInterval) -> String {
    let total = max(Int(seconds.rounded()), 0)
    if total < 60 { return "\(total)s" }
    let minutes = total / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 || hours >= 3 ? "\(hours)h" : "\(hours)h \(rest)m"
}

private struct TodayToggle: View {
    let isOn: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(isOn ? "Today" : "All")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.8))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(isOn ? Color.white.opacity(0.9) : Color.white.opacity(isHovering ? 0.16 : 0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isOn ? "Showing today’s and overdue tasks – click to show all" : "Showing all tasks – click to show today’s")
    }
}

private struct HubToastView: View {
    let toast: HubToast
    @Environment(IslandModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Text(toast.message)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            if toast.undo != nil {
                Button("Undo") { model.hub.performUndo() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Capsule().fill(Color(white: 0.2)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
        .padding(.bottom, 4)
    }
}
