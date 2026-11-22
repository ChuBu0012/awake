import AppKit
import SwiftUI

// MARK: - Automations Tab & Rule Builder Views
extension AwakeSettingsView {
    var automationsTabView: some View {
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
                    settingsState.appSearchText = ""
                    settingsState.scanInstalledApps()
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
                            Image(systemName: rule.kind == "app_open" ? "app.badge.checkmark" : "terminal")
                                .font(.title3)
                                .foregroundColor(isAct ? Color(red: 0.2, green: 0.78, blue: 0.35) : (rule.enabled ? .accentColor : .secondary))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name)
                                    .font(.body.weight(.medium))
                                HStack(spacing: 6) {
                                    Text(rule.kind == "app_open" ? "App is open" : "Work process")
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
    var addRuleSheetView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Application Rule")
                        .font(.headline)
                    Text("Awake keeps your Mac awake whenever this application is running.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search installed applications...", text: $settingsState.appSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !settingsState.appSearchText.isEmpty {
                    Button {
                        settingsState.appSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            // Installed Applications List
            if settingsState.installedApps.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    ProgressView()
                    Text("Scanning applications…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 250)
            } else if settingsState.filteredInstalledApps.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "questionmark.app.dashed")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No applications matching \"\(settingsState.appSearchText)\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 250)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(settingsState.filteredInstalledApps) { app in
                            Button {
                                model.addAppRule(name: app.name, bundleID: app.bundleID)
                                settingsState.showingAddRuleSheet = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 28, height: 28)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.primary)
                                        Text(app.bundleID)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.accentColor)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 250)
            }

            Divider()

            HStack {
                Button("Choose from Finder…") {
                    settingsState.showingAddRuleSheet = false
                    onAddApp()
                }
                .buttonStyle(.link)
                .font(.caption)

                Spacer()

                Button("Cancel") {
                    settingsState.showingAddRuleSheet = false
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 420)
    }

    func isSettingsAppOpen(for rule: AwakeStatus.Rule) -> Bool {
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

    func settingsRuleStatusColor(_ rule: AwakeStatus.Rule, isActive: Bool, isAppOpen: Bool) -> Color {
        guard rule.enabled else { return .secondary.opacity(0.6) }
        if isActive {
            return Color(red: 0.2, green: 0.78, blue: 0.35)
        }
        if rule.kind == "work_process" && isAppOpen {
            return Color.orange
        }
        return .secondary.opacity(0.5)
    }

    func settingsRuleStatusTooltip(_ rule: AwakeStatus.Rule, isActive: Bool, isAppOpen: Bool) -> String {
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
        default:
            return isActive ? "Active" : "Inactive"
        }
    }
}
