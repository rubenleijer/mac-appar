import AppKit
import SwiftUI

/// Book or change a Google Calendar event from the island. A window, since the island never
/// takes keyboard focus.
@MainActor
final class MeetingEditorController {
    private let model: IslandModel
    private var window: NSWindow?

    init(model: IslandModel) {
        self.model = model
    }

    func show(_ event: HubEvent?, start: Date?) {
        model.close()
        var draft = AcordHubService.MeetingDraft()
        if let event {
            draft.title = event.title
            draft.start = event.start
            // Google's all-day events end at the start of the next day.
            draft.end = event.isAllDay ? event.endDate.addingTimeInterval(-86_400) : event.endDate
            draft.allDay = event.isAllDay
            draft.location = event.location ?? ""
            draft.detail = event.detail ?? ""
        } else {
            let begin = start ?? Date()
            draft.start = begin
            draft.end = begin.addingTimeInterval(3600)
        }
        let view = MeetingEditorView(event: event, draft: draft) { [weak self] in self?.window?.close() }
            .environment(model)
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        if let window {
            window.contentViewController = hosting
        } else {
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.level = .floating
            self.window = window
        }
        window?.title = event == nil ? "Ny händelse" : "Redigera händelse"
        if let window {
            let frame = (NotchMetrics.preferredScreen() ?? NSScreen.main)?.visibleFrame ?? .zero
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: model.metrics.centerX - size.width / 2, y: frame.maxY - size.height - 24))
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct MeetingEditorView: View {
    let event: HubEvent?
    @State var draft: AcordHubService.MeetingDraft
    let onClose: () -> Void

    @Environment(IslandModel.self) private var model
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var titleFocused: Bool

    var body: some View {
        Form {
            TextField("Titel", text: $draft.title, prompt: Text("Vad händer?"))
                .focused($titleFocused)
            Toggle("Heldag", isOn: $draft.allDay)
            DatePicker("Börjar", selection: $draft.start, displayedComponents: draft.allDay ? .date : [.date, .hourAndMinute])
                .onChange(of: draft.start) { old, new in
                    // Keep the length when the start moves.
                    draft.end = new.addingTimeInterval(max(draft.end.timeIntervalSince(old), draft.allDay ? 0 : 900))
                }
            DatePicker("Slutar", selection: $draft.end, in: draft.start..., displayedComponents: draft.allDay ? .date : [.date, .hourAndMinute])
            HStack {
                Text("Längd").foregroundStyle(.secondary)
                Spacer()
                ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                    Button(minutes < 60 ? "\(minutes) min" : (minutes == 60 ? "1 h" : "1,5 h")) {
                        draft.end = draft.start.addingTimeInterval(TimeInterval(minutes * 60))
                    }
                    .controlSize(.small)
                }
            }
            .disabled(draft.allDay)
            TextField("Plats", text: $draft.location, prompt: Text("Valfritt"))
            TextField("Deltagare", text: $draft.attendees, prompt: Text("e-post, separerade med komma"))
            Toggle("Lägg till Google Meet-länk", isOn: $draft.addMeet)
                .disabled(draft.allDay)
            VStack(alignment: .leading, spacing: 4) {
                Text("Beskrivning").foregroundStyle(.secondary)
                TextEditor(text: $draft.detail)
                    .font(.body)
                    .frame(height: 70)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            }
            HStack {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                }
                Spacer()
                Button("Avbryt", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Sparar…" : (event == nil ? "Lägg till" : "Spara"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { titleFocused = true }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        var draft = self.draft
        if draft.allDay {
            // Google wants whole days: start of the first, start of the day after the last.
            draft.start = Calendar.current.startOfDay(for: draft.start)
            draft.end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: draft.end)) ?? draft.end
        }
        Task {
            if let message = await model.hub.saveMeeting(draft, editing: event) {
                error = message
                isSaving = false
            } else {
                onClose()
            }
        }
    }
}
