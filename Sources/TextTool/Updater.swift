import AppKit
import CryptoKit
import Foundation

/// Self-updater. Reads a small JSON feed published in the GitHub repo (`updates/latest.json`),
/// downloads the release zip, verifies it, swaps the app bundle in place and relaunches.
@MainActor
final class Updater: ObservableObject {
    struct Release: Decodable, Equatable {
        let version: String
        let build: Int
        let url: URL
        let sha256: String
        let notes: String?
        let minimumSystemVersion: String?
    }

    enum State: Equatable {
        case idle
        case checking
        case installing
    }

    enum UpdateError: LocalizedError {
        case badFeed
        case checksumMismatch
        case invalidBundle
        case notWritable(String)
        case tool(String)

        var errorDescription: String? {
            switch self {
            case .badFeed: return "The update information couldn't be read."
            case .checksumMismatch: return "The downloaded update was damaged. Please try again."
            case .invalidBundle: return "The downloaded update isn't a valid Text Tool app."
            case .notWritable(let path): return "Text Tool can't replace itself at \(path). Move it to your Applications folder and try again."
            case .tool(let message): return message
            }
        }
    }

    @Published private(set) var availableUpdate: Release?
    @Published private(set) var state: State = .idle

    @Published var automaticallyChecks: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyChecks, forKey: Self.autoCheckKey)
            scheduleAutomaticChecks()
        }
    }

    private static let autoCheckKey = "automaticallyChecksForUpdates"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private var timer: Timer?

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    let currentBuild = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    private let feedURL = (Bundle.main.object(forInfoDictionaryKey: "TTUpdateFeedURL") as? String).flatMap(URL.init(string:))

    init() {
        UserDefaults.standard.register(defaults: [Self.autoCheckKey: true])
        automaticallyChecks = UserDefaults.standard.bool(forKey: Self.autoCheckKey)
    }

    // MARK: - Checking

    /// Checks shortly after launch (if a day has passed) and then once a day.
    func scheduleAutomaticChecks() {
        timer?.invalidate()
        timer = nil
        guard automaticallyChecks else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        let sinceLast = Date().timeIntervalSince1970 - last
        let firstDelay = max(10, Self.checkInterval - sinceLast)
        timer = Timer.scheduledTimer(withTimeInterval: firstDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.check(userInitiated: false) }
                self.timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        Task { await self.check(userInitiated: false) }
                    }
                }
            }
        }
    }

    /// Fetches the feed. When `userInitiated`, the result (including "up to date" and errors) is shown in an alert.
    func check(userInitiated: Bool) async {
        guard state == .idle else { return }
        state = .checking
        defer { if state == .checking { state = .idle } }

        do {
            let release = try await fetchLatest()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            if release.build > currentBuild, isSupported(release) {
                availableUpdate = release
                if userInitiated { state = .idle; offerInstall(release) }
            } else {
                availableUpdate = nil
                if userInitiated { showAlert(title: "You're up to date", message: "Text Tool \(currentVersion) is the latest version.") }
            }
        } catch {
            if userInitiated { showAlert(title: "Couldn't check for updates", message: error.localizedDescription) }
        }
    }

    private func fetchLatest() async throws -> Release {
        guard let feedURL else { throw UpdateError.badFeed }
        var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        request.setValue("TextTool/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data),
              release.url.scheme == "https" else { throw UpdateError.badFeed }
        return release
    }

    private func isSupported(_ release: Release) -> Bool {
        guard let minimum = release.minimumSystemVersion else { return true }
        let parts = minimum.split(separator: ".").compactMap { Int($0) }
        let required = OperatingSystemVersion(majorVersion: parts.first ?? 0,
                                              minorVersion: parts.count > 1 ? parts[1] : 0,
                                              patchVersion: parts.count > 2 ? parts[2] : 0)
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(required)
    }

    // MARK: - Installing

    private func offerInstall(_ release: Release) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Text Tool \(release.version) is available"
        var info = "You have version \(currentVersion)."
        if let notes = release.notes, !notes.isEmpty { info += "\n\n" + notes }
        alert.informativeText = info
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await install(release) }
        }
    }

    /// Downloads, verifies and installs the release, then relaunches into it.
    func install(_ release: Release) async {
        guard state == .idle else { return }
        state = .installing
        do {
            let newApp = try await downloadAndVerify(release)
            try replaceAndRelaunch(with: newApp)
        } catch {
            state = .idle
            showAlert(title: "Update failed", message: error.localizedDescription)
        }
    }

    private func downloadAndVerify(_ release: Release) async throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("TextToolUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let (downloaded, response) = try await URLSession.shared.download(from: release.url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.badFeed }
        let zip = work.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: downloaded, to: zip)

        let digest = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        guard digest == release.sha256.lowercased() else { throw UpdateError.checksumMismatch }

        let unzipped = work.appendingPathComponent("unzipped")
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, unzipped.path])
        guard let app = try FileManager.default.contentsOfDirectory(at: unzipped, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }),
              let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier else { throw UpdateError.invalidBundle }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        return app
    }

    /// Hands off to a tiny shell script that waits for this process to quit, swaps the
    /// bundle (keeping the old one until the new one is in place), and opens the new app.
    private func replaceAndRelaunch(with newApp: URL) throws {
        let current = Bundle.main.bundleURL
        let parent = current.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else { throw UpdateError.notWritable(parent.path) }

        let backup = parent.appendingPathComponent(".TextTool-previous-\(UUID().uuidString).app")
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        /bin/mv "$1" "$3" || exit 1
        if /bin/mv "$2" "$1"; then /bin/rm -rf "$3"; else /bin/mv "$3" "$1"; fi
        /usr/bin/open "$1"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", current.path, newApp.path, backup.path]
        try process.run()
        NSApp.terminate(nil)
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw tool.hasSuffix("codesign") ? UpdateError.invalidBundle : UpdateError.tool(message.isEmpty ? "\(tool) failed." : message)
        }
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
