// SPDX-License-Identifier: MIT
import SwiftUI

/// The full window: sidebar + detail pane.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(Pane.allCases, id: \.self, selection: $model.selection) { pane in
                Label(pane.title, systemImage: pane.icon)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            detail
                .frame(minWidth: 560, minHeight: 480)
        }
        .navigationTitle("Xerotier Agent")
        .task { await model.bootstrap() }
    }

    @ViewBuilder private var detail: some View {
        switch model.selection ?? .setup {
        case .setup: OnboardingView()
        case .dashboard: DashboardView()
        case .settings: SettingsView()
        case .logs: LogsView()
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            Circle().fill(model.serviceState.tint).frame(width: 8, height: 8)
            Text(model.statusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
