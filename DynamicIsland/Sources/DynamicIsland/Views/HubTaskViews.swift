import AppKit
import SwiftUI

// MARK: - Row

/// A task as a card, styled like the task cards in Acord Hub: a border and soft tint in the
/// priority's color, a check circle, the title, the day and client, and the assignees' initials.
struct HubTaskRow: View {
    let task: HubTask
    @Environment(IslandModel.self) private var model
    @State private var isHovering = false
    @State private var isCompleting = false

    var body: some View {
        let hub = model.hub
        let style = TaskCardStyle(task: task, now: hub.now, isDone: isCompleting)
        let isTiming = hub.timer?.taskID == task.id

        HStack(spacing: 10) {
            TaskCheckCircle(isDone: isCompleting, isBusy: hub.busyIDs.contains(task.id) && !isCompleting) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isCompleting = true }
                // Let the tick show before the card goes.
                Task {
                    try? await Task.sleep(for: .milliseconds(380))
                    hub.complete(task)
                    isCompleting = false
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(style.title)
                    .strikethrough(isCompleting, color: style.title.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
                subtitle(style: style)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .contentShape(Rectangle())
            .onTapGesture { hub.select(task) }

            HStack(spacing: 4) {
                if isTiming {
                    TimerChip(taskID: task.id) { hub.timer?.isPaused == true ? hub.resumeTimer() : hub.pauseTimer() }
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    if isHovering {
                        Button { hub.stopTimer() } label: {
                            Image(systemName: "stop.fill").font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(IslandButtonStyle(diameter: 24))
                        .help("Stop and log the time")
                        .transition(.opacity)
                    }
                } else if isHovering {
                    Button { hub.toggleTimer(task) } label: {
                        Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(IslandButtonStyle(diameter: 24))
                    .help("Start a timer")
                    .transition(.opacity)
                }
                if isHovering && !isTiming {
                    Button { LogTimeChoice.showMenu(task: task, hub: hub) } label: {
                        Image(systemName: "clock.badge.checkmark").font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(IslandButtonStyle(diameter: 24))
                    .help("Log time")
                    .transition(.opacity)
                }
                if isHovering && !isTiming {
                    Button { hub.delete(task) } label: {
                        Image(systemName: "trash").font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(IslandButtonStyle(diameter: 24))
                    .help("Delete")
                    .transition(.opacity)
                }
                // Initials give way first when the island is narrow.
                ViewThatFits(in: .horizontal) {
                    AvatarStack(names: assigneeNames)
                    AvatarStack(names: Array(assigneeNames.prefix(1)))
                    Color.clear.frame(width: 0)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity)
        .frame(height: IslandLayout.hubCardHeight - 6)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(LinearGradient(colors: [style.tint.opacity(isHovering ? 0.2 : 0.15), style.tint.opacity(0.05)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color(white: 0.09)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(style.tint.opacity(isHovering ? 0.95 : 0.7), lineWidth: 1.5)
        }
        .shadow(color: style.tint.opacity(isHovering ? 0.25 : 0), radius: 8, y: 2)
        .scaleEffect(isCompleting ? 0.98 : 1)
        .opacity(isCompleting ? 0.75 : 1)
        .padding(.vertical, 3)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isTiming)
        .contextMenu { TaskMenuItems(task: task) }
        .help(task.title)
    }

    private func subtitle(style: TaskCardStyle) -> some View {
        let hub = model.hub
        var parts: [String] = []
        if let client = hub.clientName(for: task) { parts.append(client) }
        if let minutes = task.estimateMinutes { parts.append(estimateText(minutes)) }
        if task.status == HubTaskStatus.inProgress.rawValue { parts.append("In progress") }
        return HStack(spacing: 6) {
            if let day = style.dayText {
                Text(day)
                    .foregroundStyle(style.dayColor)
                    .fontWeight(style.isLate ? .semibold : .regular)
                    .fixedSize()
            }
            if !parts.isEmpty {
                Text(parts.joined(separator: " – "))
                    .foregroundStyle(.white.opacity(0.5))
                    .truncationMode(.tail)
            }
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .frame(minWidth: 0, alignment: .leading)
    }

    private var assigneeNames: [String] {
        let hub = model.hub
        let ids = task.allAssigneeIDs
        if !ids.isEmpty { return ids.compactMap { id in hub.team.first { $0.id == id }?.name } }
        if hub.detail?.task.id == task.id { return hub.detail?.assigneeNames ?? [] }
        return []
    }
}

/// Colors for a task card. Matches the Hub: critical is purple, high red, medium orange,
/// the rest neutral, and a finished task green.
struct TaskCardStyle {
    let tint: Color
    let title: Color
    let dayText: String?
    let dayColor: Color
    let isLate: Bool

    init(task: HubTask, now: Date, isDone: Bool = false) {
        let color: Color = if isDone { .green } else { task.priority.cardColor }
        tint = color
        title = task.priority == .none || task.priority == .low ? .white : color.blended(towardsWhite: 0.55)
        let days = task.daysLeft(now: now)
        isLate = (days ?? 0) < 0
        if let due = task.dueDay {
            dayText = due.formatted(.dateTime.day().month(.abbreviated))
        } else {
            dayText = nil
        }
        dayColor = isLate ? Color(red: 1, green: 0.45, blue: 0.42) : (days == 0 ? .white.opacity(0.8) : .white.opacity(0.55))
    }
}

extension HubPriority {
    /// The card border color, as in Acord Hub.
    var cardColor: Color {
        switch self {
        case .dangerous: Color(red: 0.55, green: 0.38, blue: 1)
        case .high: Color(red: 1, green: 0.38, blue: 0.38)
        case .medium: Color(red: 1, green: 0.6, blue: 0.25)
        case .low, .none: Color(white: 0.6)
        }
    }
}

extension Color {
    /// The color moved `fraction` of the way to white (`Color.mix` needs macOS 15).
    func blended(towardsWhite fraction: CGFloat) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return Color(nsColor: base.blended(withFraction: fraction, of: .white) ?? base)
    }
}

/// The round check on the left of a card.
private struct TaskCheckCircle: View {
    let isDone: Bool
    let isBusy: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle()
                        .strokeBorder(.white.opacity(isHovering ? 0.75 : 0.35), lineWidth: 1.5)
                        .background(Circle().fill(isDone ? Color.green : Color.white.opacity(isHovering ? 0.08 : 0)))
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(isDone ? Color.white : Color.white.opacity(0.7))
                        .opacity(isDone || isHovering ? 1 : 0)
                        .scaleEffect(isDone ? 1 : 0.8)
                }
            }
            .frame(width: 22, height: 22)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy || isDone)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDone)
        .help("Mark as done")
    }
}

/// Overlapping initials, like the avatars on the Hub's cards.
private struct AvatarStack: View {
    let names: [String]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(names.prefix(3).enumerated()), id: \.offset) { index, name in
                Text(initials(name))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(color(for: name)))
                    .overlay(Circle().strokeBorder(Color(white: 0.09), lineWidth: 2))
                    .zIndex(Double(-index))
            }
        }
        .help(names.joined(separator: ", "))
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private func color(for name: String) -> Color {
        let palette: [Color] = [Color(red: 0.36, green: 0.4, blue: 0.48), Color(red: 0.52, green: 0.38, blue: 0.32),
                                Color(red: 0.35, green: 0.36, blue: 0.4), Color(red: 0.3, green: 0.45, blue: 0.42)]
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}

/// The running timer on a card: "▶ 4:05", click to stop.
private struct TimerChip: View {
    let taskID: String
    let action: () -> Void
    @Environment(IslandModel.self) private var model
    @State private var isHovering = false

    private var isPaused: Bool { model.hub.timer?.isPaused == true }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isPaused ? "play.fill" : (isHovering ? "pause.fill" : "record.circle"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isPaused ? Color.orange : (isHovering ? Color.white : Color.green))
                    .symbolEffect(.pulse, isActive: !isPaused && !isHovering)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(clockText(model.hub.timer?.elapsed(at: context.date) ?? 0))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(isHovering ? 0.2 : 0.13)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isPaused ? "Resume the timer" : "Pause the timer")
    }
}

private func estimateText(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes) min" }
    let hours = Double(minutes) / 60
    return hours == hours.rounded() ? "\(Int(hours)) h" : String(format: "%.1f h", hours)
}

/// Every task action, for context menus and the ⋯ button.
private struct TaskMenuItems: View {
    let task: HubTask
    @Environment(IslandModel.self) private var model

    var body: some View {
        let hub = model.hub
        Button("Open") { hub.select(task) }
        Button("Mark as Done") { hub.complete(task) }
        Button(task.status == HubTaskStatus.inProgress.rawValue ? "Move Back to To Do" : "Mark as In Progress") {
            hub.toggleInProgress(task)
        }
        if let timer = hub.timer, timer.taskID == task.id {
            Button(timer.isPaused ? "Resume Timer" : "Pause Timer") { timer.isPaused ? hub.resumeTimer() : hub.pauseTimer() }
            Button("Stop Timer and Log") { hub.stopTimer() }
            Button("Stop Timer and Mark as Done") { hub.stopTimer(completeTask: true) }
        } else {
            Button("Start Timer") { hub.startTimer(task) }
        }
        Menu("Log Time") {
            ForEach(LogTimeChoice.minutes, id: \.self) { minutes in
                Button(LogTimeChoice.title(minutes)) { hub.logTime(minutes, on: task) }
            }
            Divider()
            Button("Other…") { LogTimeChoice.askCustom(task: task, hub: hub) }
        }
        Divider()
        Menu("Due") {
            ForEach(DueChoice.allCases) { choice in
                Button(choice.title) { hub.reschedule(task, to: choice.date) }
            }
        }
        Menu("Priority") {
            ForEach(Array(HubPriority.allCases.reversed())) { priority in
                Button(priority == .none ? "No priority" : priority.title) { hub.setPriority(task, priority) }
            }
        }
        Button("Edit…") { model.onEditTask?(task, false) }
        Button("Add Checklist Item…") { model.onEditTask?(task, true) }
        Divider()
        Button("Open in Acord Hub") { hub.openTask(task) }
        Button("Copy Title") { copyToPasteboard(task.title) }
        Divider()
        Button("Delete…") { hub.delete(task) }
    }
}

enum DueChoice: String, CaseIterable, Identifiable {
    case today, tomorrow, nextWeek, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .nextWeek: "In a week"
        case .none: "No due date"
        }
    }
    var date: Date? {
        let today = Calendar.current.startOfDay(for: Date())
        switch self {
        case .today: return today
        case .tomorrow: return Calendar.current.date(byAdding: .day, value: 1, to: today)
        case .nextWeek: return Calendar.current.date(byAdding: .day, value: 7, to: today)
        case .none: return nil
        }
    }
}

// MARK: - Detail

/// One task opened inside the island: actions, description and checklist.
struct HubTaskDetailView: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let hub = model.hub
        if let task = hub.selectedTask {
            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 7) {
                    header(task)
                    meta(task)
                    actions(task)
                }
                .zIndex(1)
                IslandScroll {
                    VStack(alignment: .leading, spacing: 8) {
                        if let text = task.detail, !text.isEmpty {
                            Text(text)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        checklist(task)
                    }
                    .padding(.bottom, 8)
                }
            }
        } else {
            Color.clear.onAppear { hub.select(nil) }
        }
    }

    private func header(_ task: HubTask) -> some View {
        let hub = model.hub
        return HStack(spacing: 6) {
            Button { hub.select(nil) } label: {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(IslandButtonStyle(diameter: 24))
            .help("Back to the list")
            Text(task.title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .help(task.title)
            Spacer(minLength: 4)
            if hub.isLoadingDetail || hub.busyIDs.contains(task.id) {
                ProgressView().controlSize(.mini)
            }
        }
    }

    private func meta(_ task: HubTask) -> some View {
        let hub = model.hub
        let due = taskDueText(task, now: hub.now)
        return HStack(spacing: 6) {
            Chip(title: task.priority == .none ? "No priority" : task.priority.title, symbol: "flag.fill",
                 tint: task.priority.cardColor) {
                let entries: [IslandMenu.Entry] = HubPriority.allCases.reversed().map { priority in
                    IslandMenu.Entry.item(priority == .none ? "No priority" : priority.title,
                                          checked: priority == task.priority,
                                          action: { hub.setPriority(task, priority) })
                }
                IslandMenu.show(entries)
            }
            Chip(title: due.text ?? "No due date", symbol: "calendar", tint: due.text == nil ? .white.opacity(0.6) : due.color) {
                let entries: [IslandMenu.Entry] = DueChoice.allCases.map { choice in
                    IslandMenu.Entry.item(choice.title, checked: false, action: { hub.reschedule(task, to: choice.date) })
                }
                IslandMenu.show(entries)
            }
            Chip(title: task.status == HubTaskStatus.inProgress.rawValue ? "In progress" : "To do",
                 symbol: task.status == HubTaskStatus.inProgress.rawValue ? "circle.lefthalf.filled" : "circle",
                 tint: task.status == HubTaskStatus.inProgress.rawValue ? .blue : .white.opacity(0.6)) {
                hub.toggleInProgress(task)
            }
            if let client = hub.clientName(for: task) ?? hub.detail?.assigneeNames.first {
                Text(client)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
    }

    private func actions(_ task: HubTask) -> some View {
        let hub = model.hub
        let isTiming = hub.timer?.taskID == task.id
        return HStack(spacing: 6) {
            Chip(title: "Done", symbol: "checkmark", tint: .green, filled: true) { hub.complete(task) }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = hub.timer.map { $0.elapsed(at: context.date) } ?? 0
                if isTiming, let timer = hub.timer {
                    HStack(spacing: 4) {
                        Chip(title: clockText(elapsed), symbol: timer.isPaused ? "play.fill" : "pause.fill",
                             tint: timer.isPaused ? .orange : .green, monospaced: true) {
                            timer.isPaused ? hub.resumeTimer() : hub.pauseTimer()
                        }
                        Chip(title: "Stop", symbol: "stop.fill", tint: .white) { hub.stopTimer() }
                    }
                } else {
                    Chip(title: "Start timer", symbol: "play.fill", tint: .white) { hub.startTimer(task) }
                }
            }
            .fixedSize()
            Chip(title: "Log", symbol: "clock.badge.checkmark", tint: .white) { LogTimeChoice.showMenu(task: task, hub: hub) }
            Chip(title: "Edit", symbol: "pencil", tint: .white) { model.onEditTask?(task, false) }
            Chip(title: "Item", symbol: "plus", tint: .white) { model.onEditTask?(task, true) }
            Spacer(minLength: 0)
            Button { hub.openTask(task) } label: {
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(IslandButtonStyle(diameter: 24))
            .help("Open in Acord Hub")
            Button {
                IslandMenu.show([
                    .item("Copy Title", checked: false, action: { copyToPasteboard(task.title) }),
                    .separator,
                    .item("Delete…", checked: false, action: { hub.delete(task) }),
                ])
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(IslandButtonStyle(diameter: 24))
            .help("More")
        }
    }

    @ViewBuilder
    private func checklist(_ task: HubTask) -> some View {
        let hub = model.hub
        if let items = hub.detail?.checklist, !items.isEmpty {
            let done = items.filter(\.isDone).count
            VStack(alignment: .leading, spacing: 2) {
                Text("Checklist \(done)/\(items.count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.bottom, 2)
                ForEach(items) { item in
                    ChecklistRow(item: item, isBusy: hub.busyIDs.contains(item.id))
                }
            }
        } else if !hub.isLoadingDetail && (task.detail ?? "").isEmpty {
            Text("No description or checklist")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

private struct ChecklistRow: View {
    let item: HubChecklistItem
    let isBusy: Bool
    @Environment(IslandModel.self) private var model
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button { model.hub.toggle(item) } label: {
                Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(item.isDone ? Color.green : Color.white.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            Text(item.title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(item.isDone ? 0.45 : 0.9))
                .strikethrough(item.isDone, color: .white.opacity(0.45))
                .lineLimit(2)
                .onTapGesture { model.hub.toggle(item) }
            Spacer(minLength: 4)
            if isHovering {
                Button { model.hub.deleteChecklistItem(item) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(IslandButtonStyle(diameter: 18))
                .help("Remove item")
            }
        }
        .frame(minHeight: 22)
        .onHover { isHovering = $0 }
    }
}

/// A small capsule button used for task actions.
private struct Chip: View {
    let title: String
    let symbol: String
    var tint: Color = .white
    var filled = false
    var monospaced = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
                Text(title)
                    .font(monospaced ? .system(size: 11, weight: .semibold).monospacedDigit() : .system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(filled ? Color.black : tint)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(filled ? tint.opacity(isHovering ? 1 : 0.9) : Color.white.opacity(isHovering ? 0.16 : 0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

// MARK: - Helpers

func taskDueText(_ task: HubTask, now: Date) -> (text: String?, color: Color) {
    guard let days = task.daysLeft(now: now), let due = task.dueDay else { return (nil, .white.opacity(0.5)) }
    if days < 0 {
        return (days == -1 ? "Overdue since yesterday" : "Overdue \(-days) days", Color(red: 1, green: 0.42, blue: 0.4))
    }
    if days == 0 { return ("Due today", .orange) }
    return ("Due " + AcordHubService.dayName(due, now: now), .white.opacity(0.5))
}

/// "4:05" or "1:02:30".
func clockText(_ seconds: TimeInterval) -> String {
    let total = max(Int(seconds), 0)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
}

/// Pops up a native menu at the pointer. SwiftUI menus can't be styled to fit the island.
@MainActor
enum IslandMenu {
    enum Entry {
        case item(String, checked: Bool, action: @MainActor () -> Void)
        case separator
    }

    private final class Target: NSObject {
        let action: @MainActor () -> Void
        init(_ action: @escaping @MainActor () -> Void) { self.action = action }
        @objc func run() { MainActor.assumeIsolated { action() } }
    }

    static func show(_ entries: [Entry]) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case let .item(title, checked, action):
                let target = Target(action)
                let item = NSMenuItem(title: title, action: #selector(Target.run), keyEquivalent: "")
                item.target = target
                item.representedObject = target // the menu item keeps its target alive
                item.state = checked ? .on : .off
                menu.addItem(item)
            }
        }
        _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// Quick amounts for logging time on a task without a timer.
@MainActor
enum LogTimeChoice {
    static let minutes = [15, 30, 45, 60, 90, 120]

    static func title(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : (minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min")
    }

    static func showMenu(task: HubTask, hub: AcordHubService) {
        var entries: [IslandMenu.Entry] = minutes.map { amount in
            IslandMenu.Entry.item("Log " + title(amount), checked: false, action: { hub.logTime(amount, on: task) })
        }
        entries.append(.separator)
        entries.append(.item("Other…", checked: false, action: { askCustom(task: task, hub: hub) }))
        IslandMenu.show(entries)
    }

    /// Asks for minutes (or "1:30", "1.5h") and an optional note.
    static func askCustom(task: HubTask, hub: AcordHubService) {
        let alert = NSAlert()
        alert.messageText = "Log time on “\(task.title)”"
        alert.informativeText = "Minutes, or hours like 1:30 or 1.5h."
        let amount = NSTextField(string: "")
        amount.placeholderString = "30"
        let note = NSTextField(string: "")
        note.placeholderString = "Note (optional)"
        let stack = NSStackView(views: [amount, note])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 54)
        amount.frame.size.width = 260
        note.frame.size.width = 260
        alert.accessoryView = stack
        alert.addButton(withTitle: "Log")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = amount
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn, let minutes = parse(amount.stringValue) else { return }
        hub.logTime(minutes, on: task, note: note.stringValue)
    }

    static func parse(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ",", with: ".")
        if value.contains(":") {
            let parts = value.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            let total = parts[0] * 60 + parts[1]
            return total > 0 ? total : nil
        }
        if value.hasSuffix("h") || value.hasSuffix("t"), let hours = Double(value.dropLast().trimmingCharacters(in: .whitespaces)) {
            let total = Int((hours * 60).rounded())
            return total > 0 ? total : nil
        }
        let digits = value.replacingOccurrences(of: "min", with: "").replacingOccurrences(of: "m", with: "").trimmingCharacters(in: .whitespaces)
        guard let minutes = Int(digits), minutes > 0 else { return nil }
        return minutes
    }
}
