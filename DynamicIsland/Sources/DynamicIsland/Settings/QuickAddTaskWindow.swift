import AppKit
import SwiftUI

/// A small window for adding a task to Acord Hub. The island itself never takes keyboard focus,
/// so typing happens here.
@MainActor
final class QuickAddTaskController {
    private let model: IslandModel
    private var window: NSWindow?

    init(model: IslandModel) {
        self.model = model
    }

    func show() {
        model.close()
        let view = QuickAddTaskView { [weak self] in self?.window?.close() }.environment(model)
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        if let window {
            window.contentViewController = hosting
        } else {
            let window = NSWindow(contentViewController: hosting)
            window.title = "Ny uppgift i Acord Hub"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.level = .floating
            self.window = window
        }
        if let window, let screen = NotchMetrics.preferredScreen() {
            let frame = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: model.metrics.centerX - size.width / 2, y: frame.maxY - size.height - 24))
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct QuickAddTaskView: View {
    enum Due: String, CaseIterable, Identifiable {
        case none, today, tomorrow, nextWeek, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: "Inget"
            case .today: "Idag"
            case .tomorrow: "Imorgon"
            case .nextWeek: "Om en vecka"
            case .custom: "Datum…"
            }
        }
    }

    let onClose: () -> Void
    @Environment(IslandModel.self) private var model
    @State private var title = ""
    @State private var due: Due = .none
    @State private var customDate = Date()
    @State private var projectID = ""
    @State private var assigneeID = ""
    @State private var priority: HubPriority = .low
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        let hub = model.hub
        Form {
            TextField("Titel", text: $title, prompt: Text("Vad behöver göras?"))
                .focused($isTitleFocused)
                .onSubmit(save)
            Picker("Datum", selection: $due) {
                ForEach(Due.allCases) { Text($0.title).tag($0) }
            }
            if due == .custom {
                DatePicker("Datum", selection: $customDate, displayedComponents: .date)
            }
            Picker("Prioritet", selection: $priority) {
                ForEach(Array(HubPriority.allCases.reversed())) { level in
                    HStack {
                        Circle().fill(level.cardColor).frame(width: 8, height: 8)
                        Text(level.swedishTitle)
                    }
                    .tag(level)
                }
            }
            .pickerStyle(.menu)
            Picker("Projekt", selection: $projectID) {
                Text("Inget projekt").tag("")
                ForEach(hub.projects) { project in
                    Text(project.clientName.map { $0 == project.name ? project.name : "\(project.name) – \($0)" } ?? project.name)
                        .tag(project.id)
                }
            }
            Picker("Ansvarig", selection: $assigneeID) {
                Text("Ingen").tag("")
                ForEach(hub.team) { member in
                    Text(member.id == hub.settings.memberID ? "\(member.name) (jag)" : member.name).tag(member.id)
                }
            }
            HStack {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                Spacer()
                Button("Avbryt", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Skapar…" : "Skapa uppgift", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            assigneeID = hub.settings.memberID
            isTitleFocused = true
        }
    }

    private var dueDate: Date? {
        let today = Calendar.current.startOfDay(for: Date())
        switch due {
        case .none: return nil
        case .today: return today
        case .tomorrow: return Calendar.current.date(byAdding: .day, value: 1, to: today)
        case .nextWeek: return Calendar.current.date(byAdding: .day, value: 7, to: today)
        case .custom: return customDate
        }
    }

    private func save() {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSaving else { return }
        isSaving = true
        error = nil
        Task {
            do {
                try await model.hub.createTask(title: text, dueDate: dueDate,
                                               projectID: projectID.isEmpty ? nil : projectID,
                                               assigneeID: assigneeID.isEmpty ? nil : assigneeID,
                                               priority: priority)
                onClose()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                isSaving = false
            }
        }
    }
}
