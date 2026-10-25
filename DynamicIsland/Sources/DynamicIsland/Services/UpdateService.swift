import AppKit
import Foundation

/// Keeps the app up to date from GitHub. It compares the commit the app was built from with the
/// branch on GitHub and, when they differ, runs the bundled update script: fetch, build, sign,
/// install and relaunch. The current app keeps running until the new build is ready.
@MainActor @Observable
final class UpdateService {
    enum State: Equatable {
        case idle, checking, upToDate, available(String), installing, failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?
    let currentCommit = Bundle.main.object(forInfoDictionaryKey: "DIGitCommit") as? String

    /// Asked before an automatic install; returns false while the user is busy with the island.
    @ObservationIgnored var canInstallNow: () -> Bool = { true }
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var timer: Timer?

    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Dynamic Island Update.log")

    init(settings: AppSettings) {
        self.settings = settings
    }

    var shortCommit: String { currentCommit.map { String($0.prefix(7)) } ?? "unknown" }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAutomatically() }
        }
        timer?.tolerance = 120
        Task {
            try? await Task.sleep(for: .seconds(60))
            checkAutomatically()
        }
    }

    private func checkAutomatically() {
        guard settings.autoUpdate else { return }
        Task { await check(installIfAvailable: true) }
    }

    func check(installIfAvailable: Bool = false) async {
        guard state != .installing, state != .checking else { return }
        state = .checking
        let repository = settings.updateRepository.trimmingCharacters(in: .whitespaces)
        let branch = settings.updateBranch.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/commits/\(branch)") else {
            state = .failed("Invalid repository")
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sha = json["sha"] as? String else {
                state = .failed("GitHub didn’t answer (\((response as? HTTPURLResponse)?.statusCode ?? 0))")
                return
            }
            lastChecked = Date()
            if let currentCommit, currentCommit == sha {
                state = .upToDate
                return
            }
            let message = ((json["commit"] as? [String: Any])?["message"] as? String)?
                .components(separatedBy: .newlines).first ?? "New version"
            state = .available(message)
            if installIfAvailable, settings.autoInstallUpdates, canInstallNow() { install() }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Runs the update script detached, so it survives this app being replaced.
    func install() {
        guard let bundled = Bundle.main.url(forResource: "update", withExtension: "sh") else {
            state = .failed("The update script is missing from the app")
            return
        }
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("dynamic-island-update.sh")
        try? FileManager.default.removeItem(at: script)
        do {
            try FileManager.default.copyItem(at: bundled, to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        } catch {
            state = .failed("Couldn’t prepare the update: \(error.localizedDescription)")
            return
        }
        let quote = { (text: String) in "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = "nohup /bin/bash \(quote(script.path)) \(quote(settings.updateRepository)) \(quote(settings.updateBranch))"
            + " >> \(quote(Self.logURL.path)) 2>&1 &"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        do {
            try process.run()
            state = .installing
            // If this app is still running long after, the build failed; the log says why.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(15 * 60))
                if self?.state == .installing { self?.state = .failed("The update didn’t finish – see the log") }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func openLog() {
        NSWorkspace.shared.open(Self.logURL)
    }
}
