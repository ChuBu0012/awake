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

    static func setEnabled(_ enabled: Bool) {
        let url = plistURL
        let dir = url.deletingLastPathComponent()

        if enabled {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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
            try? plistContent.write(to: url, atomically: true, encoding: .utf8)

            let unloadProc = Process()
            unloadProc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            unloadProc.arguments = ["unload", url.path]
            try? unloadProc.run()
            unloadProc.waitUntilExit()

            let loadProc = Process()
            loadProc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            loadProc.arguments = ["load", "-w", url.path]
            try? loadProc.run()
            loadProc.waitUntilExit()
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["unload", "-w", url.path]
            try? process.run()
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: url)
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
    @Published var startAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(startAtLogin, forKey: "startAtLogin")
            LoginItemManager.setEnabled(startAtLogin)
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
    @Published var newScheduleDays: String = "mon,tue,wed,thu,fri"
    @Published var newScheduleStart: String = "22:00"
    @Published var newScheduleEnd: String = "06:00"

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
        testResultSummary = "Activating sleep assertion via Awake…"

        let wasActive = model.status?.active == true
        if !wasActive {
            model.toggleAwake()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
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

            self.pmsetOutput = output
            let hasCaffeinate = output.contains("caffeinate")
            let hasIdleSleep = output.contains("PreventUserIdleSystemSleep")

            if hasCaffeinate || hasIdleSleep {
                self.testResultSummary = "✅ PASS: Verified with macOS kernel! PreventUserIdleSystemSleep assertion is actively held by caffeinate."
            } else {
                self.testResultSummary = "ℹ️ Assertion registered in Awake. Review pmset output below."
            }

            if !wasActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    model.toggleAwake()
                }
            }
            self.isTestingAssertion = false
        }
    }

    func configureSudoersOnce() {
        let currentUser = NSUserName()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            Bundle.main.url(forResource: "setup-sudoers", withExtension: "sh")?.path,
            Bundle.main.resourcePath.map { "\($0)/setup-sudoers.sh" },
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/setup-sudoers.sh").path,
            "\(home)/.local/lib/awake/setup-sudoers.sh",
            FileManager.default.currentDirectoryPath + "/scripts/setup-sudoers.sh"
        ].compactMap { $0 }.filter { FileManager.default.isExecutableFile(atPath: $0) || FileManager.default.fileExists(atPath: $0) }

        guard let targetPath = candidates.first else {
            testResultSummary = "⚠️ setup-sudoers.sh not found. Run 'make setup' in Terminal."
            return
        }

        let appleScript = "do shell script \"bash '\(targetPath)' '\(currentUser)'\" with administrator privileges"
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            scriptObject.executeAndReturnError(&error)
            if error == nil {
                checkSudoersStatus()
            }
        }
    }
}

// MARK: - Native macOS Settings Window View
struct AwakeSettingsView: View {
    @ObservedObject var model: AwakePopoverModel
    @StateObject private var settingsState = AwakeSettingsModel()
    let onRerunGetStarted: () -> Void
    let onAddApp: () -> Void
    let onAddProcess: () -> Void
    let onAddSchedule: () -> Void

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
            settingsState.checkSudoersStatus()
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
                Text("Power & Startup")
                    .font(.headline)

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
                        Text("Start Awake at Login")
                            .font(.body.weight(.medium))
                        Text("Automatically launch Awake in the menu bar when your Mac boots")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settingsState.startAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(12)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
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
                            Text(settingsState.sudoersConfigured ? (model.status?.lidSupportEnabled == true ? "Enabled" : "Configured") : "Setup Needed")
                                .font(.caption.weight(.bold))
                                .foregroundColor(settingsState.sudoersConfigured ? (model.status?.lidSupportEnabled == true ? .green : .secondary) : .orange)
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

            // Section 4: Setup Assistant
            VStack(alignment: .leading, spacing: 8) {
                Text("Setup Assistant")
                    .font(.headline)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rerun Get Started Wizard")
                            .font(.body.weight(.medium))
                        Text("Re-discover local developer apps and reconfigure goals")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Open Wizard…", action: onRerunGetStarted)
                        .buttonStyle(.bordered)
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
                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary.opacity(0.4))
                                    Text(settingsRuleStatusText(rule, isActive: isAct, isAppOpen: appOpen))
                                        .font(.caption.weight(isAct ? .medium : .regular))
                                        .foregroundColor(statusCol)
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
                    Text("Click 'Add Rule' above or rerun the Get Started wizard to add rules.")
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Automation Rule")
                .font(.headline)

            Picker("", selection: $settingsState.addRuleType) {
                Text("App").tag(0)
                Text("Process").tag(1)
                Text("Schedule").tag(2)
            }
            .pickerStyle(.segmented)

            if settingsState.addRuleType == 0 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Keep Awake while an Application is Open")
                        .font(.subheadline.weight(.medium))
                    Text("Choose any installed macOS application. Awake monitors its running state without indexing or network requests.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Choose Application…") {
                        settingsState.showingAddRuleSheet = false
                        onAddApp()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 8)
            } else if settingsState.addRuleType == 1 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Keep Awake while a Work Process Runs")
                        .font(.subheadline.weight(.medium))
                    Text("Matches active background commands or processes (e.g. node, python3, swift-frontend, docker).")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Process Name (e.g. node)", text: $settingsState.newProcessName)
                        .textFieldStyle(.roundedBorder)

                    TextField("Display Name (optional)", text: $settingsState.newProcessDisplayName)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Spacer()
                        Button("Cancel") { settingsState.showingAddRuleSheet = false }
                        Button("Add Process Rule") {
                            let name = settingsState.newProcessDisplayName.isEmpty ? settingsState.newProcessName : settingsState.newProcessDisplayName
                            guard !settingsState.newProcessName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            model.addProcessRule(name: name, processName: settingsState.newProcessName.trimmingCharacters(in: .whitespaces))
                            settingsState.newProcessName = ""
                            settingsState.newProcessDisplayName = ""
                            settingsState.showingAddRuleSheet = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(settingsState.newProcessName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Keep Awake on a Weekly Schedule")
                        .font(.subheadline.weight(.medium))
                    Text("Keeps your Mac awake during defined recurring windows (e.g. overnight builds).")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Days (e.g. mon,tue,wed,thu,fri)", text: $settingsState.newScheduleDays)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start Time (24h)").font(.caption2).foregroundColor(.secondary)
                            TextField("22:00", text: $settingsState.newScheduleStart)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("End Time (24h)").font(.caption2).foregroundColor(.secondary)
                            TextField("06:00", text: $settingsState.newScheduleEnd)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }

                    HStack {
                        Spacer()
                        Button("Cancel") { settingsState.showingAddRuleSheet = false }
                        Button("Add Schedule Rule") {
                            model.addScheduleRule(days: settingsState.newScheduleDays, start: settingsState.newScheduleStart, end: settingsState.newScheduleEnd)
                            settingsState.showingAddRuleSheet = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            if settingsState.addRuleType == 0 {
                HStack {
                    Spacer()
                    Button("Cancel") { settingsState.showingAddRuleSheet = false }
                }
            }
        }
        .padding(20)
        .frame(width: 420)
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

    // MARK: - System Test Tab (Verification & Transparency)
    private var diagnosticsTabView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.accentColor)
                    Text("Power Management Transparency")
                        .font(.headline)
                }
                Text("Awake uses macOS /usr/bin/caffeinate to create native power assertions. Standard sleep prevention does NOT require administrator privileges. Sudo is strictly used only when enabling clamshell mode with lid closed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
            .padding(12)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 10) {
                Text("Live macOS Power Assertions")
                    .font(.headline)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Current System Assertion")
                            .font(.body.weight(.medium))
                        Text(model.status?.active == true ? "ACTIVE — Sleep prevention is registered with macOS" : "INACTIVE — macOS will sleep normally on idle")
                            .font(.caption)
                            .foregroundColor(model.status?.active == true ? .green : .secondary)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.status?.active == true ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 8, height: 8)
                        Text(model.status?.active == true ? "Active" : "Idle")
                            .font(.caption.weight(.medium))
                            .foregroundColor(model.status?.active == true ? .green : .secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.04), in: Capsule())
                }
                .padding(12)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 12) {
                    Button(action: {
                        settingsState.inspectAssertions()
                    }) {
                        Label("Inspect pmset Assertions", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        settingsState.runSelfTest(model: model)
                    }) {
                        Label(settingsState.isTestingAssertion ? "Verifying…" : "Run Verification Test", systemImage: "play.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(settingsState.isTestingAssertion)
                }

                if let summary = settingsState.testResultSummary {
                    Text(summary)
                        .font(.caption.weight(.medium))
                        .foregroundColor(summary.contains("PASS") ? .green : .secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }

                if !settingsState.pmsetOutput.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Output of /usr/bin/pmset -g assertions:")
                                .font(.caption.weight(.bold))
                            Spacer()
                            Text("Official macOS Power Subsystem")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        ScrollView(.vertical) {
                            Text(settingsState.pmsetOutput)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(height: 110)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
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

    private func settingsRuleStatusText(_ rule: AwakeStatus.Rule, isActive: Bool, isAppOpen: Bool) -> String {
        guard rule.enabled else { return "Paused" }
        switch rule.kind {
        case "work_process":
            if isActive {
                return "● Agent / Task running"
            } else if isAppOpen {
                return "○ App open, idle"
            } else {
                return "○ App closed"
            }
        case "app_open":
            if isActive {
                return "● App is open"
            } else {
                return "○ App closed"
            }
        case "schedule":
            if isActive {
                return "● Schedule active"
            } else {
                return "○ Outside schedule"
            }
        default:
            return isActive ? "● Active" : "○ Inactive"
        }
    }
}
