// SPDX-License-Identifier: MIT
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showReenroll = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Enrollment") {
                TextField("Join key", text: $model.settings.joinKey)
                    .font(.body.monospaced())
                Toggle("Allow prerelease", isOn: $model.settings.preRelease)
                Button("Re-enroll with this join key") { showReenroll = true }
                    .disabled(model.installState != .installed
                              || model.settings.joinKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    .confirmationDialog("Re-enroll the agent?",
                                        isPresented: $showReenroll, titleVisibility: .visible) {
                        Button("Re-enroll", role: .destructive) { Task { await model.reEnroll() } }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Stops the agent, clears its current enrollment, and re-bootstraps with the join key above — the agent rejoins the router as a fresh enrollment. Use this to switch join keys without a full reinstall.")
                    }
            }

            Section("Runtime") {
                TextField("Max concurrent jobs", text: $model.settings.maxConcurrent)
                Picker("Log level", selection: $model.settings.logLevel) {
                    ForEach(AgentSettings.logLevels, id: \.self) { Text($0).tag($0) }
                }
                Toggle("Allow insecure transport", isOn: $model.settings.allowInsecure)
            }

            Section("GPU & vLLM tuning") {
                TextField("Memory utilization", text: $model.settings.gpuMemoryUtilization,
                          prompt: Text("0.90"))
                Text("Fraction (0–1) of the \(model.acceleratorName) budget (\(model.vramBudget)) vLLM may use, passed as --gpu-memory-utilization. Leave blank to use the agent's default.")
                    .font(.caption).foregroundStyle(.secondary)

                TextField("Max sequences", text: $model.settings.maxNumSeqs,
                          prompt: Text("256"))
                Text("Max concurrent sequences vLLM batches (--max-num-seqs). Lower it to maximize context length per request. Leave blank to use the agent's default.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Metrics") {
                TextField("Metrics port", text: $model.settings.metricsPort)
                    .disabled(model.settings.disableMetrics)
                Toggle("Disable metrics server", isOn: $model.settings.disableMetrics)
            }

            Section("vLLM") {
                TextField("Extra vLLM args", text: $model.settings.vllmArgs,
                          prompt: Text("--max-model-len 8192"))
                TextField("Extra vLLM env", text: $model.settings.vllmEnv,
                          prompt: Text("KEY=VALUE KEY2=VALUE2"))
                Text("Passed through the xerotier-vllm wrapper to vLLM.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Changes apply on the next service restart.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply & Restart") {
                        Task { await model.applyAndRestart() }
                    }
                    .disabled(model.installState != .installed)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
