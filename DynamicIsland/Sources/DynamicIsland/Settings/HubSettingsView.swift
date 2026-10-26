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
                Toggle("Visa Acord Hub-fliken", isOn: $settings.showTab)
                TextField("MCP-server", text: $settings.serverURL, prompt: Text("https://hub.acordmedia.com/api/mcp"))
                SecureField("Token", text: $settings.token, prompt: Text("Hubbens MCP-token"))
                TextField("Webbadress", text: $settings.webURL, prompt: Text("https://hub.acordmedia.com"))
                Picker("Du är", selection: $settings.memberID) {
                    Text("Inte vald").tag("")
                    ForEach(hub.team) { member in Text(member.name).tag(member.id) }
                    if !settings.memberID.isEmpty && !hub.team.contains(where: { $0.id == settings.memberID }) {
                        Text("Sparad medlem").tag(settings.memberID)
                    }
                }
                .disabled(hub.team.isEmpty)
                HStack {
                    statusLabel
                    Spacer()
                    Button(isTesting ? "Testar…" : "Testa anslutningen") {
                        isTesting = true
                        Task {
                            testResult = await hub.testConnection()
                            isTesting = false
                        }
                    }
                    .disabled(isTesting)
                }
            } header: {
                Text("Anslutning")
            } footer: {
                Text("Ön läser Hubben via samma MCP-verktyg som Claude använder. Token sparas i nyckelringen. Välj dig själv under ”Du är” så vet ön vilka uppgifter som är dina.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    switch hub.calendarConnection {
                    case .connected:
                        Label("Google Kalender är kopplad", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .notConnected(let message, _):
                        Label(message, systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    case .unknown:
                        Label("Välj dig själv under ”Du är” för att se dina möten", systemImage: "circle.dashed")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(hub.calendarConnection == .connected ? "Koppla om…" : "Koppla…") { hub.connectCalendar() }
                }
                HStack {
                    Label(hub.hubTimeTools == true ? "Tiden loggas i Acord Hub" : "Tiden sparas på den här Macen tills Hubben har timerverktygen",
                          systemImage: hub.hubTimeTools == true ? "clock.badge.checkmark.fill" : "clock")
                        .foregroundStyle(hub.hubTimeTools == true ? Color.green : Color.secondary)
                    Spacer()
                    Button("Logg") { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/Logs/Dynamic Island Hub.log")) }
                }
            } header: {
                Text("Kalender och tid")
            } footer: {
                Text("Dina Google-möten kommer via Hubben – koppla Google där en gång så syns de i kalendern, live-aktiviteten och påminnelser.")
                    .foregroundStyle(.secondary)
            }

            Section("Beteende") {
                Picker("Uppdatera var", selection: $settings.refreshMinutes) {
                    Text("30 sekunder").tag(0.5)
                    ForEach([1.0, 2, 5, 10, 15, 30], id: \.self) { Text("\(Int($0)) min").tag($0) }
                }
                Picker("När ön öppnas, visa", selection: $settings.startTab) {
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
                Toggle("Visa antal på sektionsknapparna", isOn: $settings.showCounts)
                Toggle("Visa kundnamn", isOn: $settings.showClientNames)
            } header: {
                Text("Sektioner")
            } footer: {
                Text("Slå av och på sektioner och ändra ordning. Den första visas när du öppnar fliken.")
                    .foregroundStyle(.secondary)
            }

            // MARK: Tasks
            Section("Uppgifter") {
                Picker("Visa", selection: $settings.taskScope) {
                    ForEach(HubTaskScope.allCases) { Text($0.title).tag($0) }
                }
                ForEach(HubTaskStatus.allCases) { status in
                    Toggle(status.title, isOn: Binding(get: { settings.taskStatuses.contains(status) },
                                                       set: { on in
                                                           if on { _ = settings.taskStatuses.insert(status) }
                                                           else { _ = settings.taskStatuses.remove(status) }
                                                       }))
                }
                Picker("Lägsta prioritet", selection: $settings.minimumPriority) {
                    ForEach(HubPriority.allCases) { Text($0.title).tag($0) }
                }
                Picker("Datum", selection: $settings.taskHorizonDays) {
                    Text("När som helst").tag(0)
                    Text("Idag").tag(1)
                    ForEach([3, 7, 14, 30], id: \.self) { Text("Inom \($0) dagar").tag($0) }
                }
                Toggle("Ta med försenade uppgifter", isOn: $settings.includeOverdue)
                    .disabled(settings.taskHorizonDays == 0)
                Toggle("Ta med uppgifter utan datum", isOn: $settings.showUndatedTasks)
                    .disabled(settings.taskHorizonDays != 0)
                Toggle("Fråga innan en uppgift markeras som klar", isOn: $settings.confirmComplete)
                Toggle("En startad timer flyttar uppgiften till Pågår", isOn: $settings.timerStartsTask)
                Toggle("Sortera på prioritet före datum", isOn: $settings.sortByPriority)
            }

            // MARK: Calendar, approvals, content
            Section("Kalender, godkännanden och innehåll") {
                Stepper("Kalender: kommande \(settings.calendarDays) dagar", value: $settings.calendarDays, in: 1...31)
                Toggle("Bara godkännanden som inte är godkända än", isOn: $settings.pendingApprovalsOnly)
                Stepper("Innehåll: kommande \(settings.contentDays) dagar", value: $settings.contentDays, in: 1...31)
                Toggle("Ta med utkast", isOn: $settings.includeDraftPosts)
            }

            // MARK: Notifications
            Section {
                Toggle("Ny uppgift till mig", isOn: $settings.notifyNewTask)
                HStack {
                    Toggle("Uppgift ska vara klar", isOn: $settings.notifyDueSoon)
                    Spacer()
                    Picker("", selection: $settings.dueSoonDays) {
                        Text("samma dag").tag(0)
                        Text("1 dag innan").tag(1)
                        Text("2 dagar innan").tag(2)
                        Text("3 dagar innan").tag(3)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!settings.notifyDueSoon)
                }
                Toggle("Uppgift försenad", isOn: $settings.notifyOverdue)
                HStack {
                    Toggle("Möte börjar", isOn: $settings.notifyEventSoon)
                    Spacer()
                    minutesPicker($settings.eventLeadMinutes, [5, 10, 15, 30, 60], suffix: "innan")
                        .disabled(!settings.notifyEventSoon)
                }
                Toggle("Godkännande begärt eller besvarat", isOn: $settings.notifyApprovals)
                HStack {
                    Toggle("Inlägg publiceras", isOn: $settings.notifyPostSoon)
                    Spacer()
                    minutesPicker($settings.postLeadMinutes, [15, 30, 60, 120], suffix: "innan")
                        .disabled(!settings.notifyPostSoon)
                }
            } header: {
                Text("Notiser")
            } footer: {
                Text("Hubben har inget eget notisflöde, så ön märker ändringar mellan uppdateringarna. Allt hamnar under Notiser, och varje sak aviseras bara en gång.")
                    .foregroundStyle(.secondary)
            }

            Section("Aviseringar") {
                Toggle("Visa notiser i notchen", isOn: $settings.alertsInIsland)
                Picker("Visa aviseringar i", selection: $settings.alertSeconds) {
                    ForEach([3.0, 6, 10, 15], id: \.self) { Text("\(Int($0)) sekunder").tag($0) }
                }
                .disabled(!settings.alertsInIsland)
                HStack {
                    Toggle("Spela ett ljud", isOn: $settings.alertSound)
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
                Toggle("Stör ej", isOn: $settings.doNotDisturb)
                HStack {
                    Toggle("Bara under arbetstid", isOn: $settings.workHoursOnly)
                    Spacer()
                    hourPicker($settings.workStartHour)
                    Text("–")
                    hourPicker($settings.workEndHour)
                }
                Toggle("Bara vardagar", isOn: $settings.workdaysOnly)
                HStack {
                    Spacer()
                    Button("Skicka testavisering") { hub.sendTestAlert() }
                }
            }

            // MARK: Live activity
            Section {
                Toggle("Visa vad som är på gång bredvid notchen", isOn: $settings.showLiveActivity)
                Picker("Från", selection: $settings.liveLeadMinutes) {
                    ForEach([5, 10, 15, 30, 60, 120], id: \.self) { Text("\($0) min innan").tag($0) }
                }
                .disabled(!settings.showLiveActivity)
                Toggle("Möten går före musik", isOn: $settings.livePriorityOverMusic)
                    .disabled(!settings.showLiveActivity)
                Toggle("Visa annars antal försenade uppgifter", isOn: $settings.liveShowsOverdue)
                    .disabled(!settings.showLiveActivity)
            } header: {
                Text("Live-aktivitet")
            } footer: {
                Text("Kommande och pågående möten och schemalagda inlägg, med nedräkning, medan ön är stängd.")
                    .foregroundStyle(.secondary)
            }

            // MARK: Advanced
            Section {
                DisclosureGroup("Länkar in i Hubben", isExpanded: $showsAdvanced) {
                    TextField("Uppgifter", text: $settings.tasksPath, prompt: Text("/tasks/{id}"))
                    TextField("Kalender", text: $settings.calendarPath, prompt: Text("/calendar"))
                    TextField("Godkännanden", text: $settings.approvalsPath, prompt: Text("/approvals"))
                    TextField("Innehåll", text: $settings.contentPath, prompt: Text("/planner"))
                }
                HStack {
                    Button("Rensa notiser") { hub.clearNotifications() }
                    Spacer()
                    Button("Återställ Acord Hub-inställningar", role: .destructive) { settings.resetToDefaults() }
                }
            } header: {
                Text("Avancerat")
            } footer: {
                Text("Sökvägarna läggs till webbadressen när du klickar på ↗. Skriv {id} där uppgiftens id ska stå för att öppna en uppgift direkt, t.ex. /tasks/{id}. Lämna tomt för att öppna startsidan.")
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
                Label("Inte ansluten", systemImage: "circle.dashed").foregroundStyle(.secondary)
            case .loading:
                Label("Ansluter…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
            case .ready:
                Label("Ansluten", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
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
