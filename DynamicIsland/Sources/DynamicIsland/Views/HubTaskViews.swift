import AppKit
import SwiftUI

// MARK: - Row

/// A task in the list: tick the circle to finish it, click the text to open it, hover for the timer.
struct HubTaskRow: View {
    let task: HubTask
    @Environment(IslandModel.self) private var model
    @State private var isHovering = false

    var body: some View {
        let hub = model.hub
        let isTiming = hub.timer?.taskID == task.id
        HStack(spacing: 10) {
            TaskCheckButton(task: task, isBusy: hub.busyIDs.contains(task.id)) { hub.complete(task) }
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                let due = taskDueText(task, now: hub.now)
                let parts = [due.text, hub.clientName(for: task),
                             hub.settings.taskScope == .mine ? nil : hub.memberName(task.assigneeID),
                             task.status == HubTaskStatus.inProgress.rawValue ? "In progress" : nil]
                let subtitle = parts.compactMap { $0 }.joined(separator: " · ")
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(due.color)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { hub.select(task) }

            if isTiming {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(clockText(hub.timeTracked(on: task.id, now: context.date)))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.green)
                }
            }
            if isHovering || isTiming {
                Button { hub.toggleTimer(task) } label: {
                    Image(systemName: isTiming ? "stop.fill" : "play.fill").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(IslandButtonStyle(diameter: 22))
                .help(isTiming ? "Stop the timer" : "Start a timer")
                .transition(.opacity)
            }
            if isHovering {
                Button { hub.select(task) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(IslandButtonStyle(diameter: 22))
                .help("Open")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(isHovering ? 0.08 : 0)))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .contextMenu { TaskMenuItems(task: task) }
        .help(task.title)
    }
}

/// The circle that finishes a task. Its color is the priority; it fills while the task is in progress.
private struct TaskCheckButton: View {
    let task: HubTask
    let isBusy: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView().controlSize(.mini)
                } else {
                    PriorityBadge(priority: task.priority, inProgress: task.status == HubTaskStatus.inProgress.rawValue)
                        .opacity(isHovering ? 0 : 1)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.white, .green)
                        .opacity(isHovering ? 1 : 0)
                        .scaleEffect(isHovering ? 1 : 0.6)
                }
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
        .help("Mark as done")
    }
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
        Button(hub.timer?.taskID == task.id ? "Stop Timer" : "Start Timer") { hub.toggleTimer(task) }
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
                header(task)
                meta(task)
                actions(task)
                ScrollView(.vertical) {
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
                .scrollIndicators(.never)
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
                 tint: task.priority.color) {
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
                let tracked = hub.timeTracked(on: task.id, now: context.date)
                Chip(title: isTiming ? clockText(tracked) : (tracked > 0 ? "Timer · \(clockText(tracked))" : "Start timer"),
                     symbol: isTiming ? "stop.fill" : "play.fill", tint: isTiming ? .green : .white, monospaced: true) {
                    hub.toggleTimer(task)
                }
            }
            .fixedSize()
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
