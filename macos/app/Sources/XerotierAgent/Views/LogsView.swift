// SPDX-License-Identifier: MIT
import SwiftUI

struct LogsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: LogStream? = nil
    @State private var autoScroll = true

    private static let timeFormat: Date.FormatStyle =
        .dateTime.hour().minute().second()

    private var filtered: [LogLine] {
        guard let filter else { return model.logs }
        return model.logs.filter { $0.stream == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if filtered.isEmpty {
                EmptyState(systemImage: "text.alignleft",
                           title: "No log output",
                           message: "Install or start the agent to see streamed stdout/stderr here.")
            } else {
                logScroll
            }
        }
        .navigationTitle("Logs")
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Level", selection: $filter) {
                Text("All").tag(LogStream?.none)
                ForEach(LogStream.allCases) { Text($0.displayName).tag(LogStream?.some($0)) }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.switch)
                .controlSize(.small)

            Spacer()

            Text("\(filtered.count) lines")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                model.clearLogs()
            } label: { Label("Clear", systemImage: "trash") }
                .disabled(model.logs.isEmpty)
        }
        .padding(10)
    }

    private var logScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(line.timestamp, format: Self.timeFormat)
                                .foregroundStyle(.tertiary)
                            Text(line.stream.shortTag)
                                .foregroundStyle(line.stream.tint)
                                .frame(width: 36, alignment: .leading)
                            Text(line.text)
                                .foregroundStyle(line.stream == .err ? .primary : .secondary)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .font(.caption.monospaced())
                        .id(line.id)
                    }
                    // Stable bottom anchor so we can always scroll to the end,
                    // even before a freshly-appended row is laid out.
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.logs.count) {
                guard autoScroll else { return }
                // Defer a tick so the new row exists before we scroll to it.
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(Self.bottomID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: autoScroll) {
                guard autoScroll else { return }
                DispatchQueue.main.async { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onAppear {
                DispatchQueue.main.async { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
    }

    private static let bottomID = "logs.bottom"
}
