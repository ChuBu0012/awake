import AppKit
import SwiftUI

// MARK: - About Tab View
extension AwakeSettingsView {
    var aboutTabView: some View {
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
}
