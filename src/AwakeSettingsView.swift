import AppKit
import Combine
import SwiftUI

// MARK: - Settings State Model (ObservableObject for Macro-free macOS 12+ compatibility)
final class AwakeSettingsModel: ObservableObject {
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case automations = "Automations"
        case about = "About"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .automations: return "sparkles"
            case .about: return "info.circle"
            }
        }
    }

    @Published var selectedTab: SettingsTab = .general
    @Published var startAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(startAtLogin, forKey: "startAtLogin")
        }
    }
    @Published var sudoersConfigured: Bool = false

    init() {
        self.startAtLogin = UserDefaults.standard.object(forKey: "startAtLogin") as? Bool ?? true
    }

    func checkSudoersStatus() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "pmset", "-a", "disablesleep", "1"]
        try? process.run()
        process.waitUntilExit()
        sudoersConfigured = (process.terminationStatus == 0)
        if sudoersConfigured {
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/sudo"), arguments: ["-n", "pmset", "-a", "disablesleep", "0"])
        }
    }

    func configureSudoersOnce() {
        let scriptPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/awake").deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scripts/setup-sudoers.sh").path
        let fallbackPath = FileManager.default.homeDirectoryForCurrentUser.path + "/Desktop/active_macbook/scripts/setup-sudoers.sh"
        let targetPath = FileManager.default.fileExists(atPath: scriptPath) ? scriptPath : fallbackPath

        let appleScript = "do shell script \"bash '\(targetPath)'\" with administrator privileges"
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
                VStack(alignment: .leading, spacing: 20) {
                    switch settingsState.selectedTab {
                    case .general:
                        generalTabView
                    case .automations:
                        automationsTabView
                    case .about:
                        aboutTabView
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 520, height: 460)
        .onAppear {
            settingsState.checkSudoersStatus()
        }
    }

    // MARK: - Tab Picker Bar
    private var tabPicker: some View {
        HStack(spacing: 16) {
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
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(settingsState.selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
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
                        .foregroundColor(model.status?.active == true ? .accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.status?.active == true ? "Awake is Active" : "Awake is Inactive")
                            .font(.body.weight(.medium))
                        Text(model.status?.active == true ? "System sleep is currently prevented" : "Normal macOS sleep behavior active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            }

            // Section 2: Battery & Power
            VStack(alignment: .leading, spacing: 8) {
                Text("Battery & Power")
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
                    .labelsHidden()
                }
                .padding(12)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))

                // Start at Login
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start Awake at login")
                            .font(.body.weight(.medium))
                        Text("Automatically start Awake in the menu bar when your Mac boots")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settingsState.startAtLogin)
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
                            Text(settingsState.sudoersConfigured ? "Configured" : "Setup Needed")
                                .font(.caption.weight(.bold))
                                .foregroundColor(settingsState.sudoersConfigured ? .green : .orange)
                        }
                        Text("Allows keeping Mac awake when closing the lid without password prompts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !settingsState.sudoersConfigured {
                        Button("Configure Once…", action: settingsState.configureSudoersOnce)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            }

            // Section 4: Onboarding Reset
            VStack(alignment: .leading, spacing: 8) {
                Text("Setup Assistant")
                    .font(.headline)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rerun Get Started Wizard")
                            .font(.body.weight(.medium))
                        Text("Re-discover local apps and reconfigure initial goals")
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
                Menu {
                    Button("Watch an App is open…", action: onAddApp)
                    Button("Watch a Work process…", action: onAddProcess)
                    Button("Add a Schedule…", action: onAddSchedule)
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if let rules = model.status?.rules, !rules.isEmpty {
                VStack(spacing: 8) {
                    ForEach(rules, id: \.id) { rule in
                        HStack(spacing: 12) {
                            Image(systemName: rule.kind == "schedule" ? "calendar" : rule.kind == "app_open" ? "app.badge.checkmark" : "gearshape.2")
                                .font(.title3)
                                .foregroundColor(rule.enabled ? .accentColor : .secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name)
                                    .font(.body.weight(.medium))
                                Text(rule.kind == "schedule" ? "Weekly Schedule" : rule.kind == "app_open" ? "App is open" : "Work process")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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

    // MARK: - About Tab
    private var aboutTabView: some View {
        VStack(spacing: 16) {
            Image(nsImage: AppKitUtils.appIcon())
                .resizable()
                .frame(width: 80, height: 80)
                .cornerRadius(18)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            VStack(spacing: 4) {
                Text("Awake")
                    .font(.title2.weight(.bold))
                Text("Version 1.0.0 (macOS 12+)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Zero-friction sleep prevention for AI agents, long-running builds, and developer tasks. Supports true clamshell / lid-closed execution.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("CLI Companion Mode")
                    .font(.subheadline.weight(.semibold))
                Text("You can run any task from the terminal with auto-awake:")
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

            Text("Open Source under MIT License • Privacy-first (Zero Telemetry)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
