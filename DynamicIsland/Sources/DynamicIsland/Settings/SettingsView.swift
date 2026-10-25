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
                Text("General").tag(Page.general)
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
                    .frame(width: 460, height: 620)
            }
        }
    }

    private var generalForm: some View {
        @Bindable var settings = model.settings
        return Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                Toggle("Open when the pointer rests on the notch", isOn: $settings.hoverToOpen)
                Toggle("Haptic feedback", isOn: $settings.hapticFeedback)
            } header: {
                Text("General")
            } footer: {
                Text(settings.hoverToOpen
                     ? "You feel a tap when the pointer reaches the notch and when a slider hits its end – only with a finger on the trackpad."
                     : "Click the notch to open the island. You feel a tap when a slider hits its end.")
                    .foregroundStyle(.secondary)
            }

            Section("Live activities") {
                Toggle("Show what’s playing", isOn: $settings.showLiveActivity)
                Toggle("Show track changes", isOn: $settings.showTrackChanges)
                Toggle("Show audio output changes", isOn: $settings.showDeviceChanges)
            }

            Section {
                Toggle("Show Tray tab", isOn: $settings.showTrayTab)
                Toggle("Open the tray when dragging files to the notch", isOn: $settings.openTrayOnDrag)
                    .disabled(!settings.showTrayTab)
                Picker("Remove items after", selection: $settings.trayRetentionDays) {
                    Text("Never").tag(0)
                    Text("1 day").tag(1)
                    Text("1 week").tag(7)
                    Text("30 days").tag(30)
                }
                .disabled(!settings.showTrayTab)
                HStack {
                    Text(model.tray.items.count == 1 ? "1 item" : "\(model.tray.items.count) items").foregroundStyle(.secondary)
                    Spacer()
                    Button("Show Folder") { model.tray.openFolder() }
                    Button("Empty Tray") { model.tray.clear() }.disabled(model.tray.items.isEmpty)
                }
            } header: {
                Text("Tray")
            } footer: {
                Text("Drag files, images or links onto the notch to keep them in the tray, then drag them out into any app. Items are copied, so the originals can move. Removed items go to the Trash.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show Home tab", isOn: $settings.showHomeTab)
                TextField("Shortcuts folder", text: $settings.homeFolderName)
                    .onSubmit { model.home.refresh() }
                    .disabled(!settings.showHomeTab)
                HStack {
                    Text(homeStatus).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Shortcuts") { HomeService.openShortcutsApp() }
                }
            } header: {
                Text("Home")
            } footer: {
                Text("Create shortcuts with the Control Home action (for example, turn on lights or set a scene) and put them in this folder. A leading emoji becomes the tile’s icon. If a shortcut outputs “on” or “off”, its tile shows that state.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show Posture tab", isOn: $settings.showPostureTab)
                Toggle("Show posture reminders", isOn: $settings.showPostureAlerts)
                Toggle("Show a live activity for poor posture", isOn: $settings.showPostureLiveActivity)
                HStack {
                    Label(model.posture.isConnected ? "Posture is running" : "Posture is not running",
                          systemImage: model.posture.isConnected ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(model.posture.isConnected ? Color.green : Color.secondary)
                    Spacer()
                    Button("Open Posture") { model.posture.openApp() }
                }
            } header: {
                Text("Posture")
            } footer: {
                Text("Posture is a companion app that watches how you sit. While it runs, its reminders and status appear in the island.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show volume changes in the island", isOn: $settings.showVolumeHUD)
                Toggle("Replace the system volume and brightness HUD", isOn: $settings.replaceSystemHUD)
                if settings.replaceSystemHUD && !hasAccessibility {
                    HStack {
                        Label("Requires Accessibility permission", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Settings…") { openAccessibilitySettings() }
                    }
                }
            } header: {
                Text("Volume and brightness")
            } footer: {
                Text("The volume and brightness keys then show only in the island. Hold ⌥⇧ for finer steps.")
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
                    Button("Quit") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(permissionTimer) { _ in
            hasAccessibility = MediaKeyInterceptor.hasPermission
        }
        .onAppear { model.home.refresh() }
    }

    private var homeStatus: String {
        let home = model.home
        if !home.folderExists { return "Folder not found" }
        return home.shortcuts.count == 1 ? "1 shortcut" : "\(home.shortcuts.count) shortcuts"
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
            hosting.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: hosting)
            window.title = "Dynamic Island"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
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
            Toggle("Check for updates automatically", isOn: $settings.autoUpdate)
            Toggle("Install updates automatically", isOn: $settings.autoInstallUpdates)
                .disabled(!settings.autoUpdate)
            HStack {
                status
                Spacer()
                switch updates.state {
                case .available:
                    Button("Install Now") { updates.install() }
                case .installing, .checking:
                    ProgressView().controlSize(.small)
                default:
                    Button("Check Now") { Task { await updates.check() } }
                }
            }
            HStack {
                TextField("Repository", text: $settings.updateRepository)
                TextField("Branch", text: $settings.updateBranch).frame(width: 110)
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("Updates are built on this Mac from GitHub and installed in Applications – the island relaunches by itself. Build \(updates.shortCommit).")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch updates.state {
        case .idle: Text("Not checked yet").foregroundStyle(.secondary)
        case .checking: Text("Checking…").foregroundStyle(.secondary)
        case .upToDate: Label("Up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .available(let message): Label("Update: \(message)", systemImage: "arrow.down.circle.fill").foregroundStyle(.blue).lineLimit(1)
        case .installing: Text("Building the update – the island restarts when it’s done").foregroundStyle(.secondary)
        case .failed(let message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(2)
                Button("Log") { updates.openLog() }
            }
        }
    }
}
