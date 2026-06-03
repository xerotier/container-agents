// SPDX-License-Identifier: MIT
import SwiftUI

extension Color {
    /// Xerotier accent — teal.
    static let brand = Color(red: 0.10, green: 0.78, blue: 0.73)
}

/// Lets `.brand` resolve in ShapeStyle contexts too (foregroundStyle, fill, …),
/// not just where a `Color` is expected (tint, …).
extension ShapeStyle where Self == Color {
    static var brand: Color { Color.brand }
}

extension ServiceState {
    var tint: Color {
        switch self {
        case .running: return .green
        case .stopped: return .secondary
        case .starting, .stopping: return .orange
        }
    }
}

extension LogStream {
    var tint: Color {
        switch self {
        case .out: return .secondary
        case .err: return .orange
        }
    }

    var displayName: String { self == .err ? "Errors" : "Info" }
    var shortTag: String { self == .err ? "ERR" : "INFO" }

    /// Classify a raw log line by apparent severity. The agent and vLLM
    /// interleave levels across stdout/stderr (most logging goes to stderr
    /// regardless of level), so we key off the line content rather than the
    /// file descriptor it arrived on.
    static func classify(_ text: String) -> LogStream {
        let t = text.lowercased()
        let markers = ["error", "critical", "fatal", "panic", "traceback",
                       "exception", "  err ", "[err", "err]"]
        return markers.contains(where: t.contains) ? .err : .out
    }
}

/// A rounded, padded surface used for grouping content.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 1)
            )
    }
}

/// Colored dot + text describing the current service/lifecycle state.
struct StatusPill: View {
    let text: String
    let tint: Color
    var pulsing: Bool = false

    @State private var on = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .opacity(pulsing && on ? 0.3 : 1)
                .animation(pulsing ? .easeInOut(duration: 0.7).repeatForever() : .default, value: on)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
        .foregroundStyle(tint == .secondary ? Color.secondary : tint)
        .onAppear { on = true }
    }
}

/// A single row in the install checklist.
struct StepRowView: View {
    let step: InstallStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            icon
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(step.status == .pending ? .secondary : .primary)
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var icon: some View {
        switch step.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

/// A labeled value tile for the dashboard grid.
struct InfoTile<Trailing: View>: View {
    let label: String
    let value: String
    var systemImage: String
    var valueColor: Color = .primary
    @ViewBuilder var trailing: Trailing

    init(_ label: String,
         value: String,
         systemImage: String,
         valueColor: Color = .primary,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.label = label
        self.value = value
        self.systemImage = systemImage
        self.valueColor = valueColor
        self.trailing = trailing()
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .foregroundStyle(.brand)
                    Text(label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    trailing
                }
                Text(value)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(valueColor)
            }
        }
    }
}

/// Centered empty-state placeholder.
struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.brand)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
