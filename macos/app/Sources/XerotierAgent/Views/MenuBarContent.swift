// SPDX-License-Identifier: MIT
import SwiftUI

/// The popover shown from the menu bar item.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .foregroundStyle(.brand)
                Text("Xerotier Agent").font(.headline)
                Spacer()
                StatusPill(text: model.statusSummary,
                           tint: pillTint,
                           pulsing: model.serviceState.isBusy || model.installState == .installing)
            }

            Divider()

            row("Accelerator", model.installState == .installed ? model.acceleratorName : "—")
            row("Enrollment", model.isEnrolled ? "Enrolled" : "Not enrolled")

            Divider()

            controls

            Divider()

            HStack {
                Button("Open Xerotier…") { open() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
        .padding(14)
        .frame(width: 288)
    }

    @ViewBuilder private var controls: some View {
        switch model.installState {
        case .notInstalled:
            Button {
                open(.setup)
            } label: {
                Label("Set up agent…", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brand)
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installing…").foregroundStyle(.secondary)
            }
        case .installed:
            if model.serviceState == .running {
                Button(role: .destructive) {
                    Task { await model.stopService() }
                } label: {
                    Label("Stop agent", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task { await model.startService() }
                } label: {
                    Label("Start agent", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brand)
                .disabled(model.serviceState.isBusy)
            }
        }
    }

    private var pillTint: Color {
        model.installState == .installed ? model.serviceState.tint : .secondary
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.callout)
    }

    private func open(_ pane: Pane? = nil) {
        if let pane { model.selection = pane }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
