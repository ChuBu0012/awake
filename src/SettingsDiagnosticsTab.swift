import AppKit
import SwiftUI

// MARK: - System Test Tab (Clear, Modern, Human)
extension AwakeSettingsView {
    var diagnosticsTabView: some View {
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
                let isLidActive = model.status?.lidSupportEnabled == true && isAwakeActive
                let isLidEnabled = model.status?.lidSupportEnabled == true
                let isSudoersReady = settingsState.sudoersConfigured
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isLidActive ? Color.green.opacity(0.15) : (isLidEnabled ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.1)))
                            .frame(width: 36, height: 36)
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isLidActive ? .green : (isLidEnabled ? .blue : .secondary))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lid-Closed Lock")
                            .font(.body.weight(.medium))
                        Text(isLidActive ? "Active — Mac stays awake with lid closed" : (isLidEnabled ? "Enabled — Ready when Awake is active" : (isSudoersReady ? "Ready to use" : "Setup needed in General tab")))
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
}
