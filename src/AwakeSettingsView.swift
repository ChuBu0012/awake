import AppKit
import SwiftUI

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
}
