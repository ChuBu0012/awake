import AppKit
import SwiftUI

// MARK: - General Tab View
extension AwakeSettingsView {
    var generalTabView: some View {
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
}
