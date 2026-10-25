import AppKit
import SwiftUI

/// Edits a task's title, description and checklist. Like quick add, it's a window because the
/// island can't take keyboard focus.
@MainActor
final class TaskEditorController {
    private let model: IslandModel
    private var window: NSWindow?

    init(model: IslandModel) {
        self.model = model
    }

    func show(_ task: HubTask, focusChecklist: Bool) {
        model.close()
        let view = TaskEditorView(task: task, focusChecklist: focusChecklist) { [weak self] in self?.window?.close() }
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
        window?.title = focusChecklist ? "Add to Checklist" : "Edit Task"
        if let window {
            let frame = (NotchMetrics.preferredScreen() ?? NSScreen.main)?.visibleFrame ?? .zero
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: model.metrics.centerX - size.width / 2, y: frame.maxY - size.height - 24))
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct TaskEditorView: View {
    let task: HubTask
    let focusChecklist: Bool
    let onClose: () -> Void

    private enum Field: Hashable { case title, item }

    @Environment(IslandModel.self) private var model
    @State private var title = ""
    @State private var text = ""
    @State private var newItem = ""
    @State private var added: [String] = []
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var focus: Field?

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                    .focused($focus, equals: .title)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description").foregroundStyle(.secondary)
                    TextEditor(text: $text)
                        .font(.body)
                        .frame(height: 110)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                }
            }
            Section("Checklist") {
                ForEach(model.hub.detail?.task.id == task.id ? model.hub.detail?.checklist ?? [] : []) { item in
                    Label(item.title, systemImage: item.isDone ? "checkmark.square.fill" : "square")
                        .foregroundStyle(item.isDone ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                }
                ForEach(added, id: \.self) { item in
                    Label(item, systemImage: "square").foregroundStyle(.secondary)
                }
                HStack {
                    TextField("New item", text: $newItem, prompt: Text("Add an item and press Return"))
                        .focused($focus, equals: .item)
                        .onSubmit(addItem)
                    Button("Add", action: addItem)
                        .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            HStack {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Saving…" : "Save", action: save)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            title = task.title
            text = task.detail ?? ""
            focus = focusChecklist ? .item : .title
        }
    }

    private func addItem() {
        let item = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.isEmpty, !isSaving else { return }
        isSaving = true
        error = nil
        Task {
            if await model.hub.addChecklistItem(to: task.id, title: item) {
                added.append(item)
                newItem = ""
            } else {
                error = "Couldn’t add the item"
            }
            isSaving = false
            focus = .item
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !isSaving else { return }
        isSaving = true
        error = nil
        Task {
            let pending = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
            var succeeded = await model.hub.updateText(task, title: cleanTitle, description: text)
            if succeeded, !pending.isEmpty {
                succeeded = await model.hub.addChecklistItem(to: task.id, title: pending)
            }
            isSaving = false
            if succeeded { onClose() } else { error = "Couldn’t save the task" }
        }
    }
}
