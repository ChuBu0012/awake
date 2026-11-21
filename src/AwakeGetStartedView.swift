import AppKit
import Combine
import SwiftUI

// MARK: - Get Started State Model (ObservableObject for Macro-free macOS 12+ compatibility)
final class AwakeGetStartedModel: ObservableObject {
    @Published var currentStep: Int = 1

    // Step 1: Goals
    @Published var goalAgents: Bool = true
    @Published var goalSchedule: Bool = false
    @Published var goalLidClose: Bool = true

    // Step 2: Recommendations
    @Published var discoveredApps: [RecommendedAppItem] = []

    // Step 3: Setup & Review
    @Published var startAtLogin: Bool = true
    @Published var scheduleDays: String = "mon,tue,wed,thu,fri"
    @Published var scheduleStart: String = "22:00"
    @Published var scheduleEnd: String = "06:00"
    @Published var sudoersConfigured: Bool = false

    func loadDiscoveredApps() {
        discoveredApps = AppRecommendationEngine.discoverRecommendations()
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

// MARK: - Get Started Setup Wizard View
struct AwakeGetStartedView: View {
    @ObservedObject var model: AwakePopoverModel
    @StateObject private var wizardState = AwakeGetStartedModel()
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch wizardState.currentStep {
                    case 1:
                        stepOneGoalsView
                    case 2:
                        stepTwoAppsView
                    case 3:
                        stepThreeReviewView
                    default:
                        EmptyView()
                    }
                }
                .padding(24)
            }

            Divider()
            footerBar
        }
        .frame(width: 540, height: 500)
        .onAppear {
            wizardState.loadDiscoveredApps()
            wizardState.checkSudoersStatus()
        }
    }

    // MARK: - Header
    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppKitUtils.appIcon())
                .resizable()
                .frame(width: 36, height: 36)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Awake")
                    .font(.headline)
                Text(stepSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            stepBadge
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var stepSubtitle: String {
        switch wizardState.currentStep {
        case 1: return "Step 1 of 3: Choose your goals"
        case 2: return "Step 2 of 3: Select apps to watch"
        case 3: return "Step 3 of 3: Review and finish setup"
        default: return ""
        }
    }

    private var stepBadge: some View {
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { idx in
                Circle()
                    .fill(idx == wizardState.currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Step 1: Goals
    private var stepOneGoalsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What should Awake help with?")
                .font(.title3.weight(.semibold))
            Text("Select any goals that apply. Awake will tailor its rules and recommendations to your workflow.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                goalToggleRow(
                    title: "Keep Mac awake while an AI agent works",
                    subtitle: "Prevent sleep during long runs in Cursor, VS Code, Claude, Terminal, etc.",
                    systemImage: "sparkles",
                    isOn: $wizardState.goalAgents
                )

                goalToggleRow(
                    title: "Keep Mac awake when closing the MacBook lid",
                    subtitle: "Prevent clamshell sleep when you close your screen while tasks run",
                    systemImage: "laptopcomputer",
                    isOn: $wizardState.goalLidClose
                )

                goalToggleRow(
                    title: "Keep Mac awake during a weekly schedule",
                    subtitle: "Automatically stay awake during specific work hours (e.g. overnight builds)",
                    systemImage: "calendar",
                    isOn: $wizardState.goalSchedule
                )
            }
        }
    }

    private func goalToggleRow(title: String, subtitle: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(14)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Step 2: Recommendations
    private var stepTwoAppsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recommended apps found on this Mac")
                        .font(.title3.weight(.semibold))
                    Text("Awake discovered these tools locally. Choose which apps should trigger sleep prevention.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: addCustomApp) {
                    Label("Add Custom…", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if wizardState.discoveredApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("No standard developer apps detected in /Applications.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("You can still add any application or command manually.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                VStack(spacing: 8) {
                    ForEach($wizardState.discoveredApps) { $app in
                        appRecommendationRow(app: $app)
                    }
                }
            }
        }
    }

    private func appRecommendationRow(app: Binding<RecommendedAppItem>) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: app.isSelected)
                .labelsHidden()

            if let url = app.wrappedValue.appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.wrappedValue.name)
                    .font(.body.weight(.medium))
                Text(app.wrappedValue.reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Picker("", selection: app.mode) {
                ForEach(RecommendedAppItem.WatchMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            .disabled(!app.wrappedValue.isSelected)
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Step 3: Review & Finish
    private var stepThreeReviewView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review and optional setup")
                .font(.title3.weight(.semibold))
            Text("Review your selected automation rules and optional permissions.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Automations summary
            let selectedCount = wizardState.discoveredApps.filter(\.isSelected).count
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedCount) App Automations Selected")
                        .font(.body.weight(.medium))
                    Text(selectedCount > 0 ? "Awake will monitor these apps independently." : "No apps selected. You can add rules anytime in Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))

            // Schedule Config (if chosen)
            if wizardState.goalSchedule {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Weekly Schedule Rule")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 10) {
                        TextField("Days (e.g. mon,tue,wed,thu,fri)", text: $wizardState.scheduleDays)
                            .textFieldStyle(.roundedBorder)
                        TextField("Start (22:00)", text: $wizardState.scheduleStart)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 75)
                        TextField("End (06:00)", text: $wizardState.scheduleEnd)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 75)
                    }
                    Text("Overnight schedules crossing midnight are supported.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            }

            // Start at Login toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Awake when I log in")
                        .font(.body.weight(.medium))
                    Text("Runs Awake in the background menu bar automatically on startup.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $wizardState.startAtLogin)
                    .labelsHidden()
            }
            .padding(12)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))

            // Lid-Closed Sudoers Permission
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Lid-closed Support (Clamshell)")
                            .font(.body.weight(.medium))
                        if wizardState.sudoersConfigured {
                            Text("Configured")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.green)
                        } else {
                            Text("Setup Needed")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.orange)
                        }
                    }
                    Text("Allows sleep prevention when closing laptop lid without password prompts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !wizardState.sudoersConfigured {
                    Button(action: wizardState.configureSudoersOnce) {
                        Text("Configure Once…")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Footer Controls
    private var footerBar: some View {
        HStack {
            if wizardState.currentStep == 1 {
                Button("Skip setup", action: finishWithoutRules)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            } else {
                Button("Back", action: { wizardState.currentStep -= 1 })
                    .buttonStyle(.bordered)
            }

            Spacer()

            if wizardState.currentStep < 3 {
                Button("Continue", action: { wizardState.currentStep += 1 })
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Start using Awake", action: applyAndFinish)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Actions
    private func addCustomApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add App"

        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }

        let name = FileManager.default.displayName(atPath: url.path)
        let execName = Bundle(url: url)?.executableURL?.lastPathComponent ?? name
        let item = RecommendedAppItem(
            id: bundleID,
            name: name,
            bundleID: bundleID,
            appURL: url,
            suggestedProcess: execName,
            reason: "User custom application",
            mode: .workProcess,
            isSelected: true
        )
        wizardState.discoveredApps.append(item)
    }

    private func applyAndFinish() {
        // 1. Add selected app rules
        for app in wizardState.discoveredApps where app.isSelected {
            switch app.mode {
            case .workProcess:
                model.addProcessRule(name: app.name, processName: app.suggestedProcess)
            case .appOpen:
                model.addAppRule(name: app.name, bundleID: app.bundleID)
            }
        }

        // 2. Add schedule if selected
        if wizardState.goalSchedule && !wizardState.scheduleDays.isEmpty {
            model.addScheduleRule(days: wizardState.scheduleDays, start: wizardState.scheduleStart, end: wizardState.scheduleEnd)
        }

        // 3. Mark complete & save login preference
        UserDefaults.standard.set(true, forKey: "hasCompletedGetStarted")
        UserDefaults.standard.set(wizardState.startAtLogin, forKey: "startAtLogin")

        onFinish()
    }

    private func finishWithoutRules() {
        UserDefaults.standard.set(true, forKey: "hasCompletedGetStarted")
        onFinish()
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
