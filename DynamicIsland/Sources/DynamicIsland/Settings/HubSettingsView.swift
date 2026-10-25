import AppKit
import SwiftUI

/// The Acord Hub page of the settings window.
struct HubSettingsView: View {
    @Environment(IslandModel.self) private var model
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var showsAdvanced = false

    var body: some View {
        @Bindable var settings = model.hub.settings
        let hub = model.hub
        Form {
            // MARK: Connection
            Section {
                Toggle("Show Acord Hub tab", isOn: $settings.showTab)
                TextField("MCP server", text: $settings.serverURL, prompt: Text("https://hub.acordmedia.com/api/mcp"))
                SecureField("Token", text: $settings.token, prompt: Text("The Hub’s MCP token"))
                TextField("Web address", text: $settings.webURL, prompt: Text("https://hub.acordmedia.com"))
                Picker("You are", selection: $settings.memberID) {
                    Text("Not chosen").tag("")
                    ForEach(hub.team) { member in Text(member.name).tag(member.id) }
                    if !settings.memberID.isEmpty && !hub.team.contains(where: { $0.id == settings.memberID }) {
                        Text("Saved member").tag(settings.memberID)
                    }
                }
                .disabled(hub.team.isEmpty)
                HStack {
                    statusLabel
                    Spacer()
                    Button(isTesting ? "Testing…" : "Test Connection") {
                        isTesting = true
                        Task {
                            testResult = await hub.testConnection()
                            isTesting = false
                        }
                    }
                    .disabled(isTesting)
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("The island reads the Hub through the same MCP tools Claude uses, so the Hub needs no new API. The token is kept in your keychain. Pick yourself under “You are” so the island knows which tasks are yours.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    switch hub.calendarConnection {
                    case .connected:
                        Label("Google Calendar is connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .notConnected(let message, _):
                        Label(message, systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    case .unknown:
                        Label("Choose yourself under “You are” to see your meetings", systemImage: "circle.dashed")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(hub.calendarConnection == .connected ? "Reconnect…" : "Connect…") { hub.connectCalendar() }
                }
                HStack {
                    Label(hub.hubTimeTools == true ? "Time is logged in Acord Hub" : "Time is kept on this Mac until the Hub has its timer tools",
                          systemImage: hub.hubTimeTools == true ? "clock.badge.checkmark.fill" : "clock")
                        .foregroundStyle(hub.hubTimeTools == true ? Color.green : Color.secondary)
                    Spacer()
                    Button("Log") { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/Logs/Dynamic Island Hub.log")) }
                }
            } header: {
                Text("Calendar and time")
            } footer: {
                Text("Your Google meetings come through the Hub – connect Google there once and they show in the calendar, the live activity and reminders.")
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Picker("Refresh every", selection: $settings.refreshMinutes) {
                    Text("30 seconds").tag(0.5)
                    ForEach([1.0, 2, 5, 10, 15, 30], id: \.self) { Text("\(Int($0)) min").tag($0) }
                }
                Picker("When the island opens, show", selection: $settings.startTab) {
                    ForEach(IslandStartTab.allCases) { Text($0.title).tag($0) }
                }
            }

            // MARK: Sections
            Section {
                ForEach(settings.sectionOrder) { section in
                    HStack {
                        Toggle(isOn: Binding(get: { !settings.hiddenSections.contains(section) },
                                             set: { settings.setSection(section, visible: $0) })) {
                            Label(section.title, systemImage: section.symbol)
                        }
                        Spacer()
                        Button { settings.moveSection(section, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .disabled(settings.sectionOrder.first == section)
                        Button { settings.moveSection(section, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .disabled(settings.sectionOrder.last == section)
                    }
                }
                Toggle("Show counts on the section buttons", isOn: $settings.showCounts)
                Toggle("Show client names", isOn: $settings.showClientNames)
            } header: {
                Text("Sections")
            } footer: {
                Text("Turn sections on or off and reorder them. The first one is shown when you open the tab.")
                    .foregroundStyle(.secondary)
            }

            // MARK: Tasks
            Section("Tasks") {
                Picker("Show", selection: $settings.taskScope) {
                    ForEach(HubTaskScope.allCases) { Text($0.title).tag($0) }
                }
                ForEach(HubTaskStatus.allCases) { status in
                    Toggle(status.title, isOn: Binding(get: { settings.taskStatuses.contains(status) },
                                                       set: { on in
                                                           if on { _ = settings.taskStatuses.insert(status) }
                                                           else { _ = settings.taskStatuses.remove(status) }
                                                       }))
                }
                Picker("Lowest priority", selection: $settings.minimumPriority) {
                    ForEach(HubPriority.allCases) { Text($0.title).tag($0) }
                }
                Picker("Due", selection: $settings.taskHorizonDays) {
                    Text("Any time").tag(0)
                    Text("Today").tag(1)
                    ForEach([3, 7, 14, 30], id: \.self) { Text("Within \($0) days").tag($0) }
                }
                Toggle("Include overdue tasks", isOn: $settings.includeOverdue)
                    .disabled(settings.taskHorizonDays == 0)
                Toggle("Include tasks without a due date", isOn: $settings.showUndatedTasks)
                    .disabled(settings.taskHorizonDays != 0)
                Toggle("Ask before marking a task done", isOn: $settings.confirmComplete)
                Toggle("Starting a timer moves the task to In progress", isOn: $settings.timerStartsTask)
                Toggle("Sort by priority before due date", isOn: $settings.sortByPriority)
            }

            // MARK: Calendar, approvals, content
            Section("Calendar, approvals and content") {
                Stepper("Calendar: next \(settings.calendarDays) days", value: $settings.calendarDays, in: 1...31)
                Toggle("Only approvals that aren’t approved yet", isOn: $settings.pendingApprovalsOnly)
                Stepper("Content: next \(settings.contentDays) days", value: $settings.contentDays, in: 1...31)
                Toggle("Include draft posts", isOn: $settings.includeDraftPosts)
            }

            // MARK: Notifications
            Section {
                Toggle("New task for me", isOn: $settings.notifyNewTask)
                HStack {
                    Toggle("Task due", isOn: $settings.notifyDueSoon)
                    Spacer()
                    Picker("", selection: $settings.dueSoonDays) {
                        Text("on the day").tag(0)
                        Text("1 day before").tag(1)
                        Text("2 days before").tag(2)
                        Text("3 days before").tag(3)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!settings.notifyDueSoon)
                }
                Toggle("Task overdue", isOn: $settings.notifyOverdue)
                HStack {
                    Toggle("Meeting starts", isOn: $settings.notifyEventSoon)
                    Spacer()
                    minutesPicker($settings.eventLeadMinutes, [5, 10, 15, 30, 60], suffix: "before")
                        .disabled(!settings.notifyEventSoon)
                }
                Toggle("Approval requested or answered", isOn: $settings.notifyApprovals)
                HStack {
                    Toggle("Post goes out", isOn: $settings.notifyPostSoon)
                    Spacer()
                    minutesPicker($settings.postLeadMinutes, [15, 30, 60, 120], suffix: "before")
                        .disabled(!settings.notifyPostSoon)
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("The Hub has no notification feed of its own, so the island notices changes between refreshes. Everything lands in the Notifications section; each item only notifies once.")
                    .foregroundStyle(.secondary)
            }

            Section("Alerts") {
                Toggle("Show notifications in the notch", isOn: $settings.alertsInIsland)
                Picker("Keep alerts for", selection: $settings.alertSeconds) {
                    ForEach([3.0, 6, 10, 15], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                }
                .disabled(!settings.alertsInIsland)
                HStack {
                    Toggle("Play a sound", isOn: $settings.alertSound)
                    Spacer()
                    Picker("", selection: $settings.alertSoundName) {
                        ForEach(["Glass", "Ping", "Pop", "Purr", "Hero", "Submarine", "Tink", "Funk", "Bottle", "Frog"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!settings.alertSound)
                    .onChange(of: settings.alertSoundName) { _, name in NSSound(named: NSSound.Name(name))?.play() }
                }
                Toggle("Do not disturb", isOn: $settings.doNotDisturb)
                HStack {
                    Toggle("Only during work hours", isOn: $settings.workHoursOnly)
                    Spacer()
                    hourPicker($settings.workStartHour)
                    Text("–")
                    hourPicker($settings.workEndHour)
                }
                Toggle("Only on weekdays", isOn: $settings.workdaysOnly)
                HStack {
                    Spacer()
                    Button("Send Test Alert") { hub.sendTestAlert() }
                }
            }

            // MARK: Live activity
            Section {
                Toggle("Show what’s next beside the notch", isOn: $settings.showLiveActivity)
                Picker("Starting", selection: $settings.liveLeadMinutes) {
                    ForEach([5, 10, 15, 30, 60, 120], id: \.self) { Text("\($0) min before").tag($0) }
                }
                .disabled(!settings.showLiveActivity)
                Toggle("Meetings take priority over music", isOn: $settings.livePriorityOverMusic)
                    .disabled(!settings.showLiveActivity)
                Toggle("Otherwise show the number of overdue tasks", isOn: $settings.liveShowsOverdue)
                    .disabled(!settings.showLiveActivity)
            } header: {
                Text("Live activity")
            } footer: {
                Text("Upcoming and ongoing meetings and scheduled posts, with a countdown, while the island is closed.")
                    .foregroundStyle(.secondary)
            }

            // MARK: Advanced
            Section {
                DisclosureGroup("Links into the Hub", isExpanded: $showsAdvanced) {
                    TextField("Tasks", text: $settings.tasksPath, prompt: Text("/tasks/{id}"))
                    TextField("Calendar", text: $settings.calendarPath, prompt: Text("/calendar"))
                    TextField("Approvals", text: $settings.approvalsPath, prompt: Text("/approvals"))
                    TextField("Content", text: $settings.contentPath, prompt: Text("/planner"))
                }
                HStack {
                    Button("Clear Notifications") { hub.clearNotifications() }
                    Spacer()
                    Button("Reset Acord Hub Settings", role: .destructive) { settings.resetToDefaults() }
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("Paths are added to the web address when you click ↗. Put {id} where the task’s id goes to open a task directly, for example /tasks/{id}. Leave empty to open the start page.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusLabel: some View {
        let hub = model.hub
        if let testResult {
            Text(testResult).foregroundStyle(.secondary).lineLimit(2)
        } else {
            switch hub.status {
            case .notConfigured:
                Label("Not connected", systemImage: "circle.dashed").foregroundStyle(.secondary)
            case .loading:
                Label("Connecting…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
            case .ready:
                Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(2)
            }
        }
    }

    private func minutesPicker(_ selection: Binding<Int>, _ values: [Int], suffix: String) -> some View {
        Picker("", selection: selection) {
            ForEach(values, id: \.self) { minutes in
                Text(minutes >= 60 ? "\(minutes / 60) h \(suffix)" : "\(minutes) min \(suffix)").tag(minutes)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private func hourPicker(_ selection: Binding<Int>) -> some View {
        Picker("", selection: selection) {
            ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
        .disabled(!model.hub.settings.workHoursOnly)
    }
}
