// SPDX-License-Identifier: MIT
import SwiftUI
import Observation

/// Central app state for the Xerotier XIM agent GUI.
///
/// State mutations happen on the main actor; the engine layer (Installer,
/// ServiceController, …) does its blocking work off-main and reports back
/// through `emit`, which hops to the main actor.
@MainActor
@Observable
final class AppModel {
    // Lifecycle
    var installState: InstallState = .notInstalled
    var serviceState: ServiceState = .stopped
    var isEnrolled = false

    // Configuration (shared by Onboarding + Settings)
    var settings = AgentSettings()

    // Host inspection
    var preflightChecks: [PreflightCheck] = []

    // Install pipeline
    var steps: [InstallStep] = StepKind.allCases.map { InstallStep(kind: $0) }

    // Observability
    var logs: [LogLine] = []

    // Navigation
    var selection: Pane? = .setup

    // The agent reports Apple Silicon as a single unified-memory accelerator;
    // detected live from Metal on launch.
    var accelerator: AcceleratorInfo?
    var acceleratorName: String { accelerator?.name ?? "Apple Metal" }
    var vramBudget: String { accelerator?.budgetDisplay ?? "unified memory" }

    private let tailer = LogTailer()

    var menuBarSymbol: String {
        serviceState == .running ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle"
    }

    var statusSummary: String {
        switch installState {
        case .notInstalled: return "Not installed"
        case .installing: return "Installing…"
        case .installed: return serviceState.label
        }
    }

    var requiredPreflightOK: Bool {
        preflightChecks.isEmpty || Preflight.requiredSatisfied(preflightChecks)
    }

    // MARK: - Startup

    /// Inspect the host and reflect any existing install. Safe / side-effect free.
    func bootstrap() async {
        accelerator = Accelerator.detect()
        preflightChecks = await Preflight.run()
        await refreshState()
        // Already set up? Open the Dashboard rather than the (now irrelevant)
        // Setup pane, so the user sees live status immediately on launch.
        if installState == .installed { selection = .dashboard }
    }

    func runPreflight() async {
        preflightChecks = await Preflight.run()
    }

    func refreshState() async {
        if ServiceController.isInstalled() {
            installState = .installed
            isEnrolled = ServiceController.isEnrolled()
            serviceState = await ServiceController.status()
            if serviceState == .running { tailer.start(emit: emit) }
        } else {
            installState = .notInstalled
            isEnrolled = false
            serviceState = .stopped
            for i in steps.indices { steps[i].status = .pending }
        }
    }

    // MARK: - Logging

    /// Thread-safe log sink handed to the engine. Hops to the main actor.
    nonisolated func emit(_ text: String, _ stream: LogStream) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.appendLog(text, stream: stream) }
        }
    }

    func appendLog(_ text: String, stream: LogStream = .out) {
        logs.append(LogLine(timestamp: Date(), stream: stream, text: text))
        if logs.count > 1000 { logs.removeFirst(logs.count - 1000) }
    }

    func clearLogs() { logs.removeAll() }

    // MARK: - Install

    func runInstall() async {
        guard installState != .installing,
              !settings.joinKey.trimmingCharacters(in: .whitespaces).isEmpty
        else { return }

        installState = .installing
        selection = .setup
        for i in steps.indices { steps[i].status = .pending }
        appendLog("Starting Xerotier XIM agent installation…")

        for i in steps.indices {
            steps[i].status = .running
            let ok = await Installer.perform(steps[i].kind, settings: settings, emit: emit)
            steps[i].status = ok ? .done : .failed
            if !ok {
                appendLog("Install halted at: \(steps[i].title)", stream: .err)
                installState = .notInstalled
                return
            }
        }

        isEnrolled = ServiceController.isEnrolled()
        installState = .installed
        serviceState = await ServiceController.status()
        if serviceState == .running { tailer.start(emit: emit) }
        selection = .dashboard
        appendLog("Install complete. Service: \(serviceState.label).")
    }

    // MARK: - Service control

    func startService() async {
        guard installState == .installed, serviceState == .stopped else { return }
        serviceState = .starting
        let ok = await ServiceController.start(emit: emit)
        if !ok { appendLog("Failed to start service.", stream: .err) }
        serviceState = await ServiceController.status()
        if serviceState == .running { tailer.start(emit: emit) }
    }

    func stopService() async {
        guard serviceState == .running else { return }
        serviceState = .stopping
        tailer.stop()
        await ServiceController.stop(emit: emit)
        serviceState = await ServiceController.status()
    }

    func restartService() async {
        await stopService()
        await startService()
    }

    /// Re-render the plist with current settings, then restart so they apply.
    func applyAndRestart() async {
        guard installState == .installed else { return }
        do { try ServiceController.writePlist(settings: settings) }
        catch { appendLog("Failed to write plist: \(error.localizedDescription)", stream: .err) }
        await restartService()
    }

    /// Re-bootstrap the installed agent with the current join key: stop, clear
    /// enrollment state, rewrite the plist, and start (which re-enrolls).
    func reEnroll() async {
        guard installState == .installed else { return }
        guard !settings.joinKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            appendLog("Enter a join key before re-enrolling.", stream: .err)
            return
        }
        serviceState = .stopping
        tailer.stop()
        appendLog("Re-enrolling: stopping agent and clearing enrollment state…")
        await ServiceController.stop(emit: emit)
        ServiceController.clearEnrollment()
        isEnrolled = false
        do { try ServiceController.writePlist(settings: settings) }
        catch { appendLog("Failed to write plist: \(error.localizedDescription)", stream: .err) }

        serviceState = .starting
        let ok = await ServiceController.start(emit: emit)
        if !ok { appendLog("Failed to start service.", stream: .err) }
        serviceState = await ServiceController.status()
        isEnrolled = ServiceController.isEnrolled()
        if serviceState == .running { tailer.start(emit: emit) }
        appendLog("Re-enroll complete. Service: \(serviceState.label).")
    }

    func uninstall(purge: Bool = false) async {
        tailer.stop()
        await ServiceController.uninstall(purge: purge, emit: emit)
        await refreshState()
        selection = .setup
    }
}
