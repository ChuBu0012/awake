import AppKit
import Combine
import SwiftUI

// MARK: - Login Item Manager (macOS LaunchAgent)
struct LoginItemManager {
    static let plistLabel = "app.awake.launcher"

    static var plistURL: URL {
        let libraryDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        return libraryDir.appendingPathComponent("\(plistLabel).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func isLoadedInLaunchctl() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", plistLabel]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    enum LoginItemError: LocalizedError {
        case fileWriteFailed(String)
        case launchctlFailed(action: String, status: Int32, message: String)
        case fileRemoveFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileWriteFailed(let reason):
                return "Failed to write LaunchAgent plist: \(reason)"
            case .launchctlFailed(let action, let status, let message):
                let detail = message.isEmpty ? "" : " (\(message))"
                return "launchctl \(action) failed with exit code \(status)\(detail)"
            case .fileRemoveFailed(let reason):
                return "Failed to remove LaunchAgent plist: \(reason)"
            }
        }
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Result<Void, LoginItemError> {
        let url = plistURL
        let dir = url.deletingLastPathComponent()

        if enabled {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                return .failure(.fileWriteFailed(error.localizedDescription))
            }

            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let candidates = [
                "/Applications/Awake.app/Contents/MacOS/Awake",
                "\(home)/Applications/Awake.app/Contents/MacOS/Awake",
                Bundle.main.executablePath
            ].compactMap { $0 }
            let executablePath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? (Bundle.main.executablePath ?? "/Applications/Awake.app/Contents/MacOS/Awake")

            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(plistLabel)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(executablePath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>ProcessType</key>
                <string>Interactive</string>
            </dict>
            </plist>
            """
            do {
                try plistContent.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                return .failure(.fileWriteFailed(error.localizedDescription))
            }

            // Unload previous instance if any (ignore failure on unload)
            let unloadProc = Process()
            unloadProc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            unloadProc.arguments = ["unload", url.path]
            try? unloadProc.run()
            unloadProc.waitUntilExit()

            // Load and verify
            let loadProc = Process()
            let errPipe = Pipe()
            loadProc.standardError = errPipe
            loadProc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            loadProc.arguments = ["load", "-w", url.path]
            do {
                try loadProc.run()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                loadProc.waitUntilExit()
                if loadProc.terminationStatus != 0 {
                    let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return .failure(.launchctlFailed(action: "load", status: loadProc.terminationStatus, message: errMsg))
                }
            } catch {
                return .failure(.launchctlFailed(action: "load", status: -1, message: error.localizedDescription))
            }

            guard FileManager.default.fileExists(atPath: url.path) else {
                return .failure(.fileWriteFailed("Plist file not found after creation."))
            }
            return .success(())
        } else {
            let process = Process()
            let errPipe = Pipe()
            process.standardError = errPipe
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["unload", "-w", url.path]
            try? process.run()
            process.waitUntilExit()

            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    return .failure(.fileRemoveFailed(error.localizedDescription))
                }
            }
            return .success(())
        }
    }
}

// MARK: - Settings State Model
final class AwakeSettingsModel: ObservableObject {
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case automations = "Automations"
        case diagnostics = "System Test"
        case about = "About"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .automations: return "sparkles"
            case .diagnostics: return "checkmark.shield"
            case .about: return "info.circle"
            }
        }
    }

    @Published var selectedTab: SettingsTab = .general
    @Published var startAtLogin: Bool = LoginItemManager.isEnabled
    @Published var isLaunchAgentLoaded: Bool = false
    @Published var loginItemError: String? = nil

    func checkLaunchAgentStatus() {
        let isFile = LoginItemManager.isEnabled
        let isLoaded = LoginItemManager.isLoadedInLaunchctl()
        DispatchQueue.main.async {
            self.startAtLogin = isFile
            self.isLaunchAgentLoaded = isFile && isLoaded
        }
    }

    func checkSystemStatus() {
        checkSudoersStatus()
        checkLaunchAgentStatus()
    }

    func toggleStartAtLogin(_ enabled: Bool) {
        let result = LoginItemManager.setEnabled(enabled)
        switch result {
        case .success:
            self.startAtLogin = enabled
            self.isLaunchAgentLoaded = enabled
            UserDefaults.standard.set(enabled, forKey: "startAtLogin")
            self.loginItemError = nil
        case .failure(let error):
            self.startAtLogin = LoginItemManager.isEnabled
            self.isLaunchAgentLoaded = LoginItemManager.isEnabled && LoginItemManager.isLoadedInLaunchctl()
            self.loginItemError = error.localizedDescription
        }
    }

    @Published var sudoersConfigured: Bool = false
    @Published var isCheckingSudoers: Bool = false
    @Published var pmsetOutput: String = ""
    @Published var isTestingAssertion: Bool = false
    @Published var testResultSummary: String? = nil

    // Add Rule Sheet State
    @Published var showingAddRuleSheet: Bool = false
    @Published var addRuleType: Int = 0
    @Published var newProcessName: String = ""
    @Published var newProcessDisplayName: String = ""

    // Process Presets & Live Scanner
    struct ProcessPreset: Identifiable {
        let id: String
        let name: String
        let processName: String
        let icon: String
        let description: String
        let bundleIDs: [String]
        let cliBinaries: [String]
    }

    let processPresets: [ProcessPreset] = [
        ProcessPreset(
            id: "vscode",
            name: "VS Code Agent / Task",
            processName: "Code Helper",
            icon: "chevron.left.forwardslash.chevron.right",
            description: "Background tasks, builds, agent terminals",
            bundleIDs: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"],
            cliBinaries: ["code"]
        ),
        ProcessPreset(
            id: "docker",
            name: "Docker & OrbStack",
            processName: "docker",
            icon: "shippingbox",
            description: "Containers, local dev environments",
            bundleIDs: ["com.docker.docker", "dev.kdrag0n.MacVirt"],
            cliBinaries: ["docker", "orbctl"]
        ),
        ProcessPreset(
            id: "node",
            name: "Node.js Server",
            processName: "node",
            icon: "network",
            description: "Vite, Next.js, Express servers",
            bundleIDs: [],
            cliBinaries: ["node", "npm", "pnpm", "yarn", "bun"]
        ),
        ProcessPreset(
            id: "python",
            name: "Python / Data Science",
            processName: "python3",
            icon: "terminal",
            description: "Scripts, ML models, servers",
            bundleIDs: ["org.python.python"],
            cliBinaries: ["python3", "python"]
        ),
        ProcessPreset(
            id: "xcode",
            name: "Xcode / Swift Compiler",
            processName: "swift-frontend",
            icon: "hammer",
            description: "Swift builds, compilation",
            bundleIDs: ["com.apple.dt.Xcode"],
            cliBinaries: ["swift", "xcodebuild"]
        ),
        ProcessPreset(
            id: "cursor",
            name: "Cursor Agent",
            processName: "Cursor Helper",
            icon: "cpu",
            description: "Cursor background tasks",
            bundleIDs: ["com.todesktop.230313mzl4w4u92", "com.cursor.Cursor"],
            cliBinaries: ["cursor"]
        ),
        ProcessPreset(
            id: "claude",
            name: "Claude Desktop",
            processName: "Claude Helper",
            icon: "bubble.left.and.bubble.right",
            description: "Claude background tasks",
            bundleIDs: ["com.anthropic.claude-desktop"],
            cliBinaries: []
        ),
        ProcessPreset(
            id: "blender",
            name: "Blender 3D Render",
            processName: "blender",
            icon: "cube",
            description: "Rendering, simulation",
            bundleIDs: ["org.blenderfoundation.blender"],
            cliBinaries: ["blender"]
        ),
        ProcessPreset(
            id: "terminal",
            name: "Terminal / Shell",
            processName: "Terminal",
            icon: "terminal.fill",
            description: "Active Terminal sessions",
            bundleIDs: ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable"],
            cliBinaries: []
        )
    ]

    static func isBinaryInstalled(_ binary: String) -> Bool {
        let fm = FileManager.default
        var searchPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        searchPaths.append("\(home)/.cargo/bin")
        searchPaths.append("\(home)/.orbstack/bin")
        searchPaths.append("\(home)/.local/bin")
        searchPaths.append("\(home)/.bun/bin")

        let nvmBase = "\(home)/.nvm/versions/node"
        if let subdirs = try? fm.contentsOfDirectory(atPath: nvmBase) {
            for sub in subdirs {
                searchPaths.append("\(nvmBase)/\(sub)/bin")
            }
        }
        let pyBase = "/Library/Frameworks/Python.framework/Versions"
        if let subdirs = try? fm.contentsOfDirectory(atPath: pyBase) {
            for sub in subdirs {
                searchPaths.append("\(pyBase)/\(sub)/bin")
            }
        }

        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            searchPaths.append(contentsOf: pathEnv.components(separatedBy: ":"))
        }

        for dir in searchPaths {
            let fullPath = "\(dir)/\(binary)"
            if fm.isExecutableFile(atPath: fullPath) {
                return true
            }
        }
        return false
    }

    static func isPresetInstalled(_ preset: ProcessPreset) -> Bool {
        for bid in preset.bundleIDs {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil {
                return true
            }
        }
        for bin in preset.cliBinaries {
            if isBinaryInstalled(bin) {
                return true
            }
        }
        return false
    }

    var availablePresets: [ProcessPreset] {
        processPresets.filter { Self.isPresetInstalled($0) }
    }

    @Published var runningProcesses: [String] = []

    func scanRunningProcesses() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-u", NSUserName(), "-o", "comm="]
            process.standardOutput = pipe
            try? process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let output = String(data: data, encoding: .utf8) ?? ""
            let rawNames = output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .compactMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0).lastPathComponent }
                .filter { name in
                    !name.isEmpty &&
                    !name.starts(with: "com.apple.") &&
                    !["ps", "login", "zsh", "bash", "sh", "launchd", "which"].contains(name)
                }

            let unique = Array(Set(rawNames)).sorted()
            DispatchQueue.main.async {
                self?.runningProcesses = unique
            }
        }
    }

    init() {
        let isConfigured = LoginItemManager.isEnabled
        self.startAtLogin = isConfigured || (UserDefaults.standard.object(forKey: "startAtLogin") as? Bool ?? false)
    }

    func checkSudoersStatus() {
        guard !isCheckingSudoers else { return }
        isCheckingSudoers = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let readProc = Process()
            let pipe = Pipe()
            readProc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            readProc.arguments = ["-g"]
            readProc.standardOutput = pipe
            readProc.standardError = pipe
            try? readProc.run()
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            readProc.waitUntilExit()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            var baseline = "0"
            for line in output.components(separatedBy: .newlines) {
                let parts = line.split(whereSeparator: \.isWhitespace)
                if parts.count >= 2 && parts[0] == "SleepDisabled" {
                    baseline = String(parts[1])
                    break
                }
            }

            let sudoProc = Process()
            sudoProc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            sudoProc.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", baseline]
            try? sudoProc.run()
            sudoProc.waitUntilExit()
            let configured = (sudoProc.terminationStatus == 0)

            DispatchQueue.main.async {
                self?.isCheckingSudoers = false
                self?.sudoersConfigured = configured
            }
        }
    }

    func inspectAssertions() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-g", "assertions"]
            process.standardOutput = pipe
            process.standardError = pipe
            try? process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? "Unable to read pmset assertions."

            DispatchQueue.main.async {
                self?.pmsetOutput = text
            }
        }
    }

    func runSelfTest(model: AwakePopoverModel) {
        isTestingAssertion = true
        testResultSummary = "Testing sleep lock with macOS…"

        let wasActive = model.status?.active == true

        let inspectAssertions: () -> Void = { [weak self] in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                process.arguments = ["-g", "assertions"]
                process.standardOutput = pipe
                process.standardError = pipe
                try? process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""

                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.pmsetOutput = output
                    let hasCaffeinate = output.contains("caffeinate")
                    let hasIdleSleep = output.contains("PreventUserIdleSystemSleep")

                    if hasCaffeinate || hasIdleSleep {
                        self.testResultSummary = "✅ All systems normal. Your Mac won't sleep while Awake is active."
                    } else {
                        self.testResultSummary = "Sleep lock check completed. View details below."
                    }

                    if !wasActive {
                        model.performAction(["off"]) {
                            self.isTestingAssertion = false
                        }
                    } else {
                        self.isTestingAssertion = false
                    }
                }
            }
        }

        if !wasActive {
            model.performAction(["on", "3600"]) {
                inspectAssertions()
            }
        } else {
            inspectAssertions()
        }
    }

    func configureSudoersOnce() {
        PermissionManager.configureSudoers { [weak self] result in
            switch result {
            case .success:
                self?.checkSudoersStatus()
                self?.testResultSummary = "✅ Sudoers configured successfully."
            case .failure(let error):
                self?.testResultSummary = "⚠️ \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Utilities
struct AppKitUtils {
    static func appIcon() -> NSImage {
        if let icon = NSImage(named: NSImage.applicationIconName) {
            return icon
        }
        let fallback = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
        return fallback ?? NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Awake")!
    }
}
