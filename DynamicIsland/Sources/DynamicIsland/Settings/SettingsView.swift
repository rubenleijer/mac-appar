import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(IslandModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hasAccessibility = MediaKeyInterceptor.hasPermission

    @State private var page = Page.general

    private enum Page: Hashable { case general, hub }

    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $page) {
                Text("Allmänt").tag(Page.general)
                Text("Acord Hub").tag(Page.hub)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            .padding(.top, 14)
            .padding(.bottom, 2)

            switch page {
            case .general:
                generalForm
            case .hub:
                HubSettingsView()
            }
        }
        .frame(minWidth: 460, idealWidth: 500, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
    }

    private var generalForm: some View {
        @Bindable var settings = model.settings
        return Form {
            Section {
                Toggle("Öppna vid inloggning", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                Toggle("Öppna när pekaren vilar på notchen", isOn: $settings.hoverToOpen)
                Toggle("Haptisk feedback", isOn: $settings.hapticFeedback)
            } header: {
                Text("Allmänt")
            } footer: {
                Text(settings.hoverToOpen
                     ? "Du känner ett tryck när pekaren når notchen och när ett reglage når sitt slut – bara med ett finger på styrplattan."
                     : "Klicka på notchen för att öppna ön. Du känner ett tryck när ett reglage når sitt slut.")
                    .foregroundStyle(.secondary)
            }

            Section("Live-aktiviteter") {
                Toggle("Visa vad som spelas", isOn: $settings.showLiveActivity)
                Toggle("Visa låtbyten", isOn: $settings.showTrackChanges)
                Toggle("Visa byte av ljudutgång", isOn: $settings.showDeviceChanges)
            }

            Section {
                Toggle("Visa temperatur och batteri under Ljud och skärm", isOn: $settings.showTemperature)
                Toggle("Visa temperatur och batteri bredvid notchen", isOn: $settings.showTemperatureLiveActivity)
                HStack {
                    Toggle("Varna när Macen går varm", isOn: $settings.warnWhenHot)
                    Spacer()
                    Picker("", selection: $settings.hotThreshold) {
                        ForEach([75, 80, 85, 90, 95, 100], id: \.self) { Text("vid \($0)°C").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!settings.warnWhenHot)
                }
                HStack {
                    Text(model.thermal.isAvailable ? "CPU nu: \(model.thermal.cpuText) · \(model.thermal.thermalTitle)" : "Inga temperatursensorer hittades")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } header: {
                Text("Temperatur och batteri")
            } footer: {
                Text("Läses från chipets egna sensorer med några sekunders mellanrum. Notchen visar det bara när inget annat visas där.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Visa fliken Urklippskö", isOn: $settings.showClipboardTab)
                Picker("Behåll", selection: $settings.clipboardLimit) {
                    ForEach([10, 20, 30, 50, 100], id: \.self) { Text("\($0) objekt").tag($0) }
                }
                .disabled(!settings.showClipboardTab)
            } header: {
                Text("Urklippskö")
            } footer: {
                Text("Allt du kopierar hamnar i kö i ön. Klicka på en rad för att lägga den i urklippet; med Kö på går varje ⌘V vidare till nästa (kräver Hjälpmedel). Lösenord från lösenordshanterare sparas aldrig, och bara text sparas mellan omstarter.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Visa fliken Tray", isOn: $settings.showTrayTab)
                Toggle("Öppna trayen när filer dras till notchen", isOn: $settings.openTrayOnDrag)
                    .disabled(!settings.showTrayTab)
                Picker("Ta bort objekt efter", selection: $settings.trayRetentionDays) {
                    Text("Aldrig").tag(0)
                    Text("1 dag").tag(1)
                    Text("1 vecka").tag(7)
                    Text("30 dagar").tag(30)
                }
                .disabled(!settings.showTrayTab)
                HStack {
                    Text(model.tray.items.count == 1 ? "1 objekt" : "\(model.tray.items.count) objekt").foregroundStyle(.secondary)
                    Spacer()
                    Button("Visa mapp") { model.tray.openFolder() }
                    Button("Töm trayen") { model.tray.clear() }.disabled(model.tray.items.isEmpty)
                }
            } header: {
                Text("Tray")
            } footer: {
                Text("Dra filer, bilder eller länkar till notchen för att spara dem i trayen och dra sedan ut dem i valfri app. De kopieras, så originalen kan flyttas. Borttagna objekt hamnar i papperskorgen.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Visa fliken Hem", isOn: $settings.showHomeTab)
                TextField("Mapp i Genvägar", text: $settings.homeFolderName)
                    .onSubmit { model.home.refresh() }
                    .disabled(!settings.showHomeTab)
                HStack {
                    Text(homeStatus).foregroundStyle(.secondary)
                    Spacer()
                    Button("Öppna Genvägar") { HomeService.openShortcutsApp() }
                }
            } header: {
                Text("Hem")
            } footer: {
                Text("Skapa genvägar med åtgärden Styr hem (t.ex. tänd lampor eller välj en scen) och lägg dem i den här mappen. En emoji först blir ikonen. Om genvägen ger ”på” eller ”av” visar rutan det.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Visa fliken Hållning", isOn: $settings.showPostureTab)
                Toggle("Visa hållningspåminnelser", isOn: $settings.showPostureAlerts)
                Toggle("Visa live-aktivitet vid dålig hållning", isOn: $settings.showPostureLiveActivity)
                HStack {
                    Label(model.posture.isConnected ? "Hållning körs" : "Hållning körs inte",
                          systemImage: model.posture.isConnected ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(model.posture.isConnected ? Color.green : Color.secondary)
                    Spacer()
                    Button("Öppna Hållning") { model.posture.openApp() }
                }
            } header: {
                Text("Hållning")
            } footer: {
                Text("Hållning är en följeslagarapp som håller koll på hur du sitter. När den körs syns dess påminnelser och status i ön.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Visa volymändringar i ön", isOn: $settings.showVolumeHUD)
                Toggle("Ersätt systemets volym- och ljusstyrkeruta", isOn: $settings.replaceSystemHUD)
                if settings.replaceSystemHUD && !hasAccessibility {
                    HStack {
                        Label("Kräver behörighet för Hjälpmedel", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Öppna Inställningar…") { openAccessibilitySettings() }
                    }
                }
            } header: {
                Text("Volym och ljusstyrka")
            } footer: {
                Text("Volym- och ljusstyrketangenterna visas då bara i ön. Håll ⌥⇧ för finare steg.")
                    .foregroundStyle(.secondary)
            }

            if let updates = model.updates {
                UpdatesSection(updates: updates)
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dynamic Island")
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Avsluta") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(permissionTimer) { _ in
            hasAccessibility = MediaKeyInterceptor.hasPermission
        }
        .onAppear { model.home.refresh() }
    }

    private var homeStatus: String {
        let home = model.home
        if !home.folderExists { return "Mappen hittades inte" }
        return home.shortcuts.count == 1 ? "1 genväg" : "\(home.shortcuts.count) genvägar"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func openAccessibilitySettings() {
        MediaKeyInterceptor.requestPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
final class SettingsWindowController {
    private let model: IslandModel
    private var window: NSWindow?

    init(model: IslandModel) {
        self.model = model
    }

    func show() {
        model.close()
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView().environment(model))
            // The window sets the size and the forms scroll inside it, so it never runs off the screen.
            hosting.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "Dynamic Island"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 800)
            window.setContentSize(NSSize(width: 500, height: min(720, visible.height - 60)))
            window.setFrameAutosaveName("DynamicIslandSettings")
            if !window.setFrameUsingName("DynamicIslandSettings") { window.center() }
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct UpdatesSection: View {
    let updates: UpdateService
    @Environment(IslandModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Section {
            Toggle("Sök efter uppdateringar automatiskt", isOn: $settings.autoUpdate)
            Toggle("Installera uppdateringar automatiskt", isOn: $settings.autoInstallUpdates)
                .disabled(!settings.autoUpdate)
            HStack {
                status
                Spacer()
                switch updates.state {
                case .available:
                    Button("Installera nu") { updates.install() }
                case .installing, .checking:
                    ProgressView().controlSize(.small)
                default:
                    Button("Sök nu") { Task { await updates.check() } }
                }
            }
            HStack {
                TextField("Repo", text: $settings.updateRepository)
                TextField("Gren", text: $settings.updateBranch).frame(width: 110)
            }
        } header: {
            Text("Uppdateringar")
        } footer: {
            Text("Uppdateringar byggs på den här Macen från GitHub och installeras i Program – ön startar om av sig själv. Bygge \(updates.shortCommit).")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch updates.state {
        case .idle: Text("Inte sökt än").foregroundStyle(.secondary)
        case .checking: Text("Söker…").foregroundStyle(.secondary)
        case .upToDate: Label("Senaste versionen", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .available(let message): Label("Uppdatering: \(message)", systemImage: "arrow.down.circle.fill").foregroundStyle(.blue).lineLimit(1)
        case .installing: Text("Bygger uppdateringen – ön startar om när den är klar").foregroundStyle(.secondary)
        case .failed(let message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(2)
                Button("Logg") { updates.openLog() }
            }
        }
    }
}
