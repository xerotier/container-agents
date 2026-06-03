// SPDX-License-Identifier: MIT
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                switch model.installState {
                case .notInstalled:
                    joinKeyCard(model: $model)
                    requirementsCard
                    stepsCard
                case .installing:
                    stepsCard
                case .installed:
                    successCard
                    stepsCard
                }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Set up the XIM agent")
                .font(.largeTitle.weight(.bold))
            Text("Install the Metal-accelerated inference agent and enroll it with your Xerotier router. Everything runs as your user — no admin password needed.")
                .foregroundStyle(.secondary)
        }
    }

    private func joinKeyCard(model: Bindable<AppModel>) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Join key", systemImage: "key.horizontal")
                    .font(.headline)
                Text("Dashboard → Infrastructure → Agents → Generate Join Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("XEROTIER_AGENT_JOIN_KEY", text: model.settings.joinKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                Toggle("Allow installing from a prerelease", isOn: model.settings.preRelease)
                    .font(.callout)
                Toggle("Force reinstall vllm-metal (rebuild from source)", isOn: model.settings.reinstallVLLM)
                    .font(.callout)

                HStack {
                    Spacer()
                    Button {
                        Task { await self.model.runInstall() }
                    } label: {
                        Label("Install & Start", systemImage: "arrow.down.circle.fill")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brand)
                    .controlSize(.large)
                    .disabled(self.model.settings.joinKey.trimmingCharacters(in: .whitespaces).isEmpty
                              || !self.model.requiredPreflightOK)
                }
            }
        }
    }

    private var requirementsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Requirements", systemImage: "checklist").font(.headline)
                    Spacer()
                    Button {
                        Task { await model.runPreflight() }
                    } label: { Label("Re-check", systemImage: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
                if model.preflightChecks.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking host…").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                } else {
                    ForEach(model.preflightChecks) { requirement($0) }
                    if !model.requiredPreflightOK {
                        Text("Resolve the failed required checks before installing.")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private func requirement(_ check: PreflightCheck) -> some View {
        HStack(spacing: 8) {
            Image(systemName: check.ok ? "checkmark.circle.fill"
                  : (check.required ? "xmark.circle.fill" : "exclamationmark.triangle.fill"))
                .foregroundStyle(check.ok ? .green : (check.required ? .red : .orange))
            Text(check.name).font(.callout)
            Spacer()
            Text(check.detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var stepsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Label("Install pipeline", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                    .padding(.bottom, 4)
                ForEach(model.steps) { step in
                    StepRowView(step: step)
                    if step.id != model.steps.last?.id { Divider() }
                }
            }
        }
    }

    private var successCard: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("You're all set").font(.headline)
                    Text("The agent is enrolled and running, reporting \(model.acceleratorName) (\(model.vramBudget)).")
                        .foregroundStyle(.secondary)
                    Button("Open Dashboard") { model.selection = .dashboard }
                        .buttonStyle(.link)
                        .padding(.top, 2)
                }
                Spacer()
            }
        }
    }
}
