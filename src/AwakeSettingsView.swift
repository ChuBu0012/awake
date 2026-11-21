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

    // Add Rule Sheet State (Stored in ObservableObject for macro-free macOS 12+ CLI compilation)
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

    // Schedule UI State
    @Published var selectedDays: Set<String> = ["mon", "tue", "wed", "thu", "fri"]
    @Published var startHour: Int = 22
    @Published var startMinute: Int = 0
    @Published var endHour: Int = 6
    @Published var endMinute: Int = 0

    var formattedDays: String {
        let order = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        let active = order.filter { selectedDays.contains($0) }
        return active.isEmpty ? "mon,tue,wed,thu,fri" : active.joined(separator: ",")
    }

    var formattedStart: String {
        String(format: "%02d:%02d", startHour, startMinute)
    }

    var formattedEnd: String {
        String(format: "%02d:%02d", endHour, endMinute)
    }

    var scheduleSummary: String {
        let order = [("mon", "Mon"), ("tue", "Tue"), ("wed", "Wed"), ("thu", "Thu"), ("fri", "Fri"), ("sat", "Sat"), ("sun", "Sun")]
        let dayNames = order.filter { selectedDays.contains($0.0) }.map { $0.1 }.joined(separator: ", ")
        let daysDesc = dayNames.isEmpty ? "No days selected" : dayNames
        return "\(daysDesc) • \(formattedStart) – \(formattedEnd)"
    }

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

// MARK: - Native macOS Settings Window View
struct AwakeSettingsView: View {
    @ObservedObject var model: AwakePopoverModel
    @ObservedObject var settingsState: AwakeSettingsModel
    let onAddApp: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabPicker
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch settingsState.selectedTab {
                    case .general:
                        generalTabView
                    case .automations:
                        automationsTabView
                    case .diagnostics:
                        diagnosticsTabView
                    case .about:
                        aboutTabView
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 530, height: 470)
        .onAppear {
            settingsState.checkSystemStatus()
        }
        .sheet(isPresented: $settingsState.showingAddRuleSheet) {
            addRuleSheetView
        }
    }

    // MARK: - Tab Picker Bar
    private var tabPicker: some View {
        HStack(spacing: 12) {
            ForEach(AwakeSettingsModel.SettingsTab.allCases) { tab in
                Button {
                    settingsState.selectedTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                        Text(tab.rawValue)
                    }
                    .font(.subheadline.weight(settingsState.selectedTab == tab ? .semibold : .regular))
                    .foregroundColor(settingsState.selectedTab == tab ? .accentColor : .secondary)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .background(
                        settingsState.selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - General Tab
    private var generalTabView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section 1: System Status
            VStack(alignment: .leading, spacing: 8) {
                Text("System Status")
                    .font(.headline)

                HStack(spacing: 12) {
                    Image(systemName: model.status?.active == true ? "eye.fill" : "moon.zzz")
                        .font(.title2)
                        .foregroundColor(model.status?.active == true ? .green : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.status?.active == true ? "Awake is Active" : "Awake is Inactive")
                            .font(.body.weight(.medium))
                        Text(model.status?.activeReasonSummary ?? "Normal macOS sleep behavior active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    Button(model.status?.active == true ? "Turn Off" : "Turn On") {
                        model.toggleAwake()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            }

            // Section 2: Battery & Power
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Power & Startup")
                        .font(.headline)
                    Spacer()
                    Button {
                        settingsState.checkSystemStatus()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Re-check")
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Re-check LaunchAgent and sudoers status")
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Battery Guard")
                            .font(.body.weight(.medium))
                        Text("Pause sleep prevention below 20% when running on battery power")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.status?.batteryGuardEnabled == true },
                        set: { _ in model.toggleBatteryGuard() }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                .padding(12)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Start Awake at Login")
                                .font(.body.weight(.medium))
                            if settingsState.startAtLogin {
                                Text(settingsState.isLaunchAgentLoaded ? "✓ Verified (LaunchAgent)" : "Enabled")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(settingsState.isLaunchAgentLoaded ? .green : .orange)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(settingsState.isLaunchAgentLoaded ? Color.green.opacity(0.12) : Color.orange.opacity(0.12), in: Capsule())
                            }
                        }
                        Text("Automatically launch Awake in the menu bar when your Mac boots")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settingsState.startAtLogin },
                        set: { settingsState.toggleStartAtLogin($0) }
                    ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(12)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))

                if let err = settingsState.loginItemError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.primary)
                        Spacer()
                        Button("Dismiss") {
                            settingsState.loginItemError = nil
                        }
                        .buttonStyle(.plain)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            // Section 3: Hardware / Clamshell
            VStack(alignment: .leading, spacing: 8) {
                Text("Hardware & Permissions")
                    .font(.headline)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Lid-closed Support (Clamshell)")
                                .font(.body.weight(.medium))
                            Text(settingsState.sudoersConfigured ? (model.status?.lidSupportEnabled == true ? "✓ Verified (Active)" : "✓ Verified (pmset)") : "Setup Needed")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(settingsState.sudoersConfigured ? .green : .orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(settingsState.sudoersConfigured ? Color.green.opacity(0.12) : Color.orange.opacity(0.12), in: Capsule())
                        }
                        Text("Allows keeping Mac awake when closing the lid without password prompts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !settingsState.sudoersConfigured {
                        Button("Configure Once…", action: settingsState.configureSudoersOnce)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Toggle("", isOn: Binding(
                            get: { model.status?.lidSupportEnabled == true },
                            set: { _ in model.toggleLidSupport() }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(model.isBusy)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Automations Tab
    private var automationsTabView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Configured Automations")
                        .font(.headline)
                    Text("Rules that automatically keep your Mac awake")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button {
                    settingsState.showingAddRuleSheet = true
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if let rules = model.status?.rules, !rules.isEmpty {
                VStack(spacing: 8) {
                    ForEach(rules, id: \.id) { rule in
                        let isAct = rule.active == true || model.status?.requests.contains(where: { $0.id == "rule:\(rule.id)" }) == true
                        let appOpen = rule.appOpen == true || isSettingsAppOpen(for: rule)
                        let statusCol = settingsRuleStatusColor(rule, isActive: isAct, isAppOpen: appOpen)

                        HStack(spacing: 12) {
                            Image(systemName: rule.kind == "schedule" ? "calendar" : rule.kind == "app_open" ? "app.badge.checkmark" : "terminal")
                                .font(.title3)
                                .foregroundColor(isAct ? Color(red: 0.2, green: 0.78, blue: 0.35) : (rule.enabled ? .accentColor : .secondary))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name)
                                    .font(.body.weight(.medium))
                                HStack(spacing: 6) {
                                    Text(rule.kind == "schedule" ? "Weekly Schedule" : rule.kind == "app_open" ? "App is open" : "Work process")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Circle()
                                        .fill(statusCol)
                                        .frame(width: 7, height: 7)
                                        .help(settingsRuleStatusTooltip(rule, isActive: isAct, isAppOpen: appOpen))
                                }
                            }
                            Spacer()

                            Button(rule.enabled ? "Pause" : "Resume") {
                                model.performRuleAction(rule.enabled ? "disable" : "enable", ruleID: rule.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(role: .destructive) {
                                model.performRuleAction("remove", ruleID: rule.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 4)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No automations configured yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Click 'Add Rule' above to configure automations.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
    }

    // MARK: - Add Rule Modal Sheet
    private var addRuleSheetView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Add Automation Rule")
                    .font(.headline)
                Spacer()
                Button {
                    settingsState.showingAddRuleSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
            }

            Picker("", selection: $settingsState.addRuleType) {
                Text("Application").tag(0)
                Text("Work Process").tag(1)
                Text("Weekly Schedule").tag(2)
            }
            .pickerStyle(.segmented)
            .onChange(of: settingsState.addRuleType) { type in
                if type == 1 {
                    settingsState.scanRunningProcesses()
                }
            }

            if settingsState.addRuleType == 0 {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Watch an Application")
                            .font(.subheadline.weight(.semibold))
                        Text("Awake keeps your Mac awake whenever this application is running.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button("Choose Installed App…") {
                        settingsState.showingAddRuleSheet = false
                        onAddApp()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    Spacer().frame(height: 10)
                }
                .padding(.vertical, 8)
            } else if settingsState.addRuleType == 1 {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Watch a Background Process")
                            .font(.subheadline.weight(.semibold))
                        Text("Select a popular developer tool or pick from processes currently running on your Mac.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // 1. Recommended Worker Presets Grid (Filtered dynamically by installed apps & tools)
                    if !settingsState.availablePresets.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RECOMMENDED WORKERS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                ForEach(settingsState.availablePresets) { preset in
                                    let isSelected = settingsState.newProcessName == preset.processName
                                    Button {
                                        settingsState.newProcessName = preset.processName
                                        settingsState.newProcessDisplayName = preset.name
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: preset.icon)
                                                .font(.system(size: 12))
                                                .foregroundColor(isSelected ? .white : .accentColor)
                                                .frame(width: 16)

                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(preset.name)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(isSelected ? .white : .primary)
                                                Text(preset.processName)
                                                    .font(.system(size: 9, design: .monospaced))
                                                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                            }
                                            Spacer()
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(
                                            isSelected ? Color.accentColor : Color.primary.opacity(0.04),
                                            in: RoundedRectangle(cornerRadius: 6)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // 2. Currently Running Processes on this Mac
                    if !settingsState.runningProcesses.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("RUNNING ON YOUR MAC")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Rescan") {
                                    settingsState.scanRunningProcesses()
                                }
                                .font(.system(size: 10))
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 5) {
                                    ForEach(settingsState.runningProcesses.prefix(18), id: \.self) { proc in
                                        let isSelected = settingsState.newProcessName == proc
                                        Button {
                                            settingsState.newProcessName = proc
                                            if settingsState.newProcessDisplayName.isEmpty {
                                                settingsState.newProcessDisplayName = proc
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Circle()
                                                    .fill(Color.green)
                                                    .frame(width: 5, height: 5)
                                                Text(proc)
                                                    .font(.system(size: 10, design: .monospaced))
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(
                                                isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05),
                                                in: Capsule()
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    // 3. Selected Configuration
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CONFIGURATION")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Executable Name").font(.caption2).foregroundColor(.secondary)
                                TextField("e.g. Code Helper, node", text: $settingsState.newProcessName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Display Label").font(.caption2).foregroundColor(.secondary)
                                TextField("e.g. VS Code Agent", text: $settingsState.newProcessDisplayName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11))
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button("Cancel") { settingsState.showingAddRuleSheet = false }
                        Button("Add Process Rule") {
                            let displayName = settingsState.newProcessDisplayName.trimmingCharacters(in: .whitespaces)
                            let proc = settingsState.newProcessName.trimmingCharacters(in: .whitespaces)
                            guard !proc.isEmpty else { return }
                            let name = displayName.isEmpty ? proc : displayName
                            model.addProcessRule(name: name, processName: proc)
                            settingsState.newProcessName = ""
                            settingsState.newProcessDisplayName = ""
                            settingsState.showingAddRuleSheet = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(settingsState.newProcessName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Weekly Schedule")
                            .font(.subheadline.weight(.semibold))
                        Text("Awake keeps your Mac awake automatically during defined recurring times.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // 1. Day Selection
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("ACTIVE DAYS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Weekdays") {
                                settingsState.selectedDays = ["mon", "tue", "wed", "thu", "fri"]
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10))

                            Text("•").foregroundColor(.secondary).font(.caption2)

                            Button("Everyday") {
                                settingsState.selectedDays = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10))

                            Text("•").foregroundColor(.secondary).font(.caption2)

                            Button("Weekends") {
                                settingsState.selectedDays = ["sat", "sun"]
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10))
                        }

                        HStack(spacing: 5) {
                            ForEach([
                                ("mon", "Mon"),
                                ("tue", "Tue"),
                                ("wed", "Wed"),
                                ("thu", "Thu"),
                                ("fri", "Fri"),
                                ("sat", "Sat"),
                                ("sun", "Sun")
                            ], id: \.0) { dayKey, dayLabel in
                                let isSelected = settingsState.selectedDays.contains(dayKey)
                                Button {
                                    if isSelected {
                                        if settingsState.selectedDays.count > 1 {
                                            settingsState.selectedDays.remove(dayKey)
                                        }
                                    } else {
                                        settingsState.selectedDays.insert(dayKey)
                                    }
                                } label: {
                                    Text(dayLabel)
                                        .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(
                                            isSelected ? Color.accentColor : Color.primary.opacity(0.04),
                                            in: RoundedRectangle(cornerRadius: 6)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // 2. Time Window
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("TIME WINDOW")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Overnight") {
                                settingsState.startHour = 22; settingsState.startMinute = 0
                                settingsState.endHour = 6; settingsState.endMinute = 0
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10))

                            Text("•").foregroundColor(.secondary).font(.caption2)

                            Button("Workday") {
                                settingsState.startHour = 9; settingsState.startMinute = 0
                                settingsState.endHour = 18; settingsState.endMinute = 0
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10))

                            Text("•").foregroundColor(.secondary).font(.caption2)

                            Button("All Day") {
                                settingsState.startHour = 0; settingsState.startMinute = 0
                                settingsState.endHour = 23; settingsState.endMinute = 59
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10))
                        }

                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Text("Start:").font(.caption.weight(.medium)).foregroundColor(.secondary)
                                Picker("", selection: $settingsState.startHour) {
                                    ForEach(0..<24, id: \.self) { h in
                                        Text(String(format: "%02d", h)).tag(h)
                                    }
                                }
                                .frame(width: 52)
                                Text(":")
                                Picker("", selection: $settingsState.startMinute) {
                                    ForEach([0, 15, 30, 45], id: \.self) { m in
                                        Text(String(format: "%02d", m)).tag(m)
                                    }
                                }
                                .frame(width: 52)
                            }

                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack(spacing: 4) {
                                Text("End:").font(.caption.weight(.medium)).foregroundColor(.secondary)
                                Picker("", selection: $settingsState.endHour) {
                                    ForEach(0..<24, id: \.self) { h in
                                        Text(String(format: "%02d", h)).tag(h)
                                    }
                                }
                                .frame(width: 52)
                                Text(":")
                                Picker("", selection: $settingsState.endMinute) {
                                    ForEach([0, 15, 30, 45, 59], id: \.self) { m in
                                        Text(String(format: "%02d", m)).tag(m)
                                    }
                                }
                                .frame(width: 52)
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                    }

                    // 3. Live Summary
                    HStack(spacing: 8) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.body)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(settingsState.scheduleSummary)
                                .font(.system(size: 11, weight: .semibold))
                            Text("Mac will stay awake automatically during this recurring window.")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                    HStack {
                        Spacer()
                        Button("Cancel") { settingsState.showingAddRuleSheet = false }
                        Button("Add Schedule Rule") {
                            model.addScheduleRule(
                                days: settingsState.formattedDays,
                                start: settingsState.formattedStart,
                                end: settingsState.formattedEnd
                            )
                            settingsState.showingAddRuleSheet = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(settingsState.selectedDays.isEmpty)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 470)
    }

    // MARK: - About Tab
    private var aboutTabView: some View {
        VStack(spacing: 16) {
            Image(nsImage: AppKitUtils.appIcon())
                .resizable()
                .frame(width: 72, height: 72)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

            VStack(spacing: 3) {
                Text("Awake")
                    .font(.title3.weight(.bold))
                Text("Version 1.0.0 • Native macOS 12+")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Zero-friction sleep prevention for AI agents, long-running builds, and developer tasks. Supports native caffeinate power assertions and clamshell execution.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("CLI Companion Mode")
                    .font(.subheadline.weight(.semibold))
                Text("Wrap any terminal command with auto-sleep prevention:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text("awake run <your-command>")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("awake run ", forType: .string)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))

            Spacer()

            Text("Open Source under MIT License • 100% Local & Privacy-first")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - System Test Tab (Clear, Modern, Human)
    private var diagnosticsTabView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header summary
            VStack(alignment: .leading, spacing: 4) {
                Text("Sleep Lock Status")
                    .font(.headline)
                Text("Check how Awake prevents your Mac from sleeping.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Status cards
            VStack(spacing: 10) {
                // Card 1: Standard Sleep Lock (caffeinate)
                let isAwakeActive = model.status?.active == true
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isAwakeActive ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                            .frame(width: 36, height: 36)
                        Image(systemName: isAwakeActive ? "bolt.fill" : "moon.zzz")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isAwakeActive ? .green : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Standard Sleep Lock")
                            .font(.body.weight(.medium))
                        Text(isAwakeActive ? "Active — Mac stays awake on idle" : "Idle — Normal macOS sleep behavior")
                            .font(.caption)
                            .foregroundColor(isAwakeActive ? .green : .secondary)
                    }

                    Spacer()

                    Text("caffeinate")
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))

                // Card 2: Clamshell / Lid-Closed (pmset)
                let isLidActive = model.status?.lidSupportEnabled == true
                let isSudoersReady = settingsState.sudoersConfigured
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isLidActive ? Color.green.opacity(0.15) : (isSudoersReady ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.1)))
                            .frame(width: 36, height: 36)
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isLidActive ? .green : (isSudoersReady ? .blue : .secondary))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lid-Closed Lock")
                            .font(.body.weight(.medium))
                        Text(isLidActive ? "Active — Mac stays awake with lid closed" : (isSudoersReady ? "Ready to use" : "Setup needed in General tab"))
                            .font(.caption)
                            .foregroundColor(isLidActive ? .green : .secondary)
                    }

                    Spacer()

                    Text("pmset")
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            }

            // Quick Test Button & Result
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        settingsState.runSelfTest(model: model)
                    } label: {
                        HStack(spacing: 6) {
                            if settingsState.isTestingAssertion {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "play.circle.fill")
                            }
                            Text(settingsState.isTestingAssertion ? "Testing…" : "Test Sleep Lock")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(settingsState.isTestingAssertion)

                    if settingsState.isTestingAssertion {
                        Text("Simulating sleep lock…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let summary = settingsState.testResultSummary {
                    HStack(spacing: 8) {
                        Image(systemName: summary.contains("normal") ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundColor(summary.contains("normal") ? .green : .accentColor)
                        Text(summary)
                            .font(.caption.weight(.medium))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (summary.contains("normal") ? Color.green : Color.accentColor).opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
            }

            // Collapsible Technical pmset output
            DisclosureGroup("Technical Details (pmset assertions)") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Raw output of 'pmset -g assertions':")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Refresh") {
                            settingsState.inspectAssertions()
                        }
                        .font(.system(size: 10))
                    }

                    if settingsState.pmsetOutput.isEmpty {
                        Text("Click Refresh or run a test to inspect assertions.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(8)
                    } else {
                        ScrollView(.vertical) {
                            Text(settingsState.pmsetOutput)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(height: 120)
                        .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private func isSettingsAppOpen(for rule: AwakeStatus.Rule) -> Bool {
        if rule.appOpen == true { return true }
        let running = NSWorkspace.shared.runningApplications
        if let bID = rule.bundleID, running.contains(where: { $0.bundleIdentifier == bID }) {
            return true
        }
        let lower = rule.name.lowercased()
        if lower.contains("visual studio code") || lower.contains("code") {
            return running.contains(where: { $0.bundleIdentifier == "com.microsoft.VSCode" || $0.bundleIdentifier == "com.microsoft.VSCodeInsiders" })
        }
        if lower.contains("cursor") {
            return running.contains(where: { $0.bundleIdentifier == "com.todesktop.230313mzl4w4u92" })
        }
        if lower.contains("claude") {
            return running.contains(where: { $0.bundleIdentifier == "com.anthropic.claude-desktop" })
        }
        if lower.contains("chatgpt") {
            return running.contains(where: { $0.bundleIdentifier == "com.openai.chat" })
        }
        if lower.contains("antigravity") {
            return running.contains(where: { $0.bundleIdentifier == "com.google.antigravity" })
        }
        if lower.contains("xcode") {
            return running.contains(where: { $0.bundleIdentifier == "com.apple.dt.Xcode" })
        }
        return false
    }

    private func settingsRuleStatusColor(_ rule: AwakeStatus.Rule, isActive: Bool, isAppOpen: Bool) -> Color {
        guard rule.enabled else { return .secondary.opacity(0.6) }
        if isActive {
            return Color(red: 0.2, green: 0.78, blue: 0.35)
        }
        if rule.kind == "work_process" && isAppOpen {
            return Color.orange
        }
        return .secondary.opacity(0.5)
    }

    private func settingsRuleStatusTooltip(_ rule: AwakeStatus.Rule, isActive: Bool, isAppOpen: Bool) -> String {
        guard rule.enabled else { return "Rule paused" }
        switch rule.kind {
        case "work_process":
            if isActive {
                return "Agent / Task running (Active)"
            } else if isAppOpen {
                return "App open, idle"
            } else {
                return "App closed"
            }
        case "app_open":
            if isActive {
                return "App is open (Active)"
            } else {
                return "App closed"
            }
        case "schedule":
            if isActive {
                return "Schedule active"
            } else {
                return "Outside schedule"
            }
        default:
            return isActive ? "Active" : "Inactive"
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
