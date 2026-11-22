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
    var addRuleSheetView: some View {
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
            } else {
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
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text("RUNNING ON YOUR MAC (\(settingsState.runningProcesses.count))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)

                                Spacer()

                                HStack(spacing: 4) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                    TextField("Search process…", text: $settingsState.processSearchText)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 10))
                                        .frame(width: 120)
                                    if !settingsState.processSearchText.isEmpty {
                                        Button {
                                            settingsState.processSearchText = ""
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))

                                Button("Rescan") {
                                    settingsState.scanRunningProcesses()
                                }
                                .font(.system(size: 10))
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                            }

                            let filtered = settingsState.filteredRunningProcesses
                            if filtered.isEmpty {
                                HStack {
                                    Spacer()
                                    Text("No running processes match \"\(settingsState.processSearchText)\"")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 14)
                                .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
                            } else {
                                ScrollView(.vertical) {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 5)], spacing: 5) {
                                        ForEach(filtered, id: \.self) { proc in
                                            let isSelected = settingsState.newProcessName == proc
                                            Button {
                                                settingsState.newProcessName = proc
                                                if settingsState.newProcessDisplayName.isEmpty {
                                                    settingsState.newProcessDisplayName = proc
                                                }
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Circle()
                                                        .fill(isSelected ? Color.accentColor : Color.green)
                                                        .frame(width: 5, height: 5)
                                                    Text(proc)
                                                        .font(.system(size: 10, design: .monospaced))
                                                        .foregroundColor(isSelected ? .primary : .secondary)
                                                        .lineLimit(1)
                                                        .truncationMode(.middle)
                                                    Spacer(minLength: 0)
                                                }
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 4)
                                                .background(
                                                    isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04),
                                                    in: RoundedRectangle(cornerRadius: 5)
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 5)
                                                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .help("Select \(proc)")
                                        }
                                    }
                                    .padding(4)
                                }
                                .frame(height: 82)
                                .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
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
            }
        }
        .padding(20)
        .frame(width: 470)
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
