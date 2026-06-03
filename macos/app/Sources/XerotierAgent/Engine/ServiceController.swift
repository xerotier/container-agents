// SPDX-License-Identifier: MIT
import Foundation

/// Manages the per-user LaunchAgent via `launchctl`. (SMAppService is the
/// App-Store-friendly alternative but can't carry the dynamically-rendered
/// plist + join key, so we bootstrap a plist written into ~/Library/LaunchAgents.)
enum ServiceController {
    static func isInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: Paths.agentBin.path)
    }

    static func isEnrolled() -> Bool {
        FileManager.default.fileExists(atPath: Paths.enrollmentState.path)
    }

    /// Inspect launchd for the agent's current state.
    static func status() async -> ServiceState {
        let (code, out) = await Shell.capture("/bin/launchctl", ["print", Paths.serviceTarget])
        guard code == 0 else { return .stopped }
        // "state = running" appears while the program is actually executing;
        // a loaded-but-waiting job (KeepAlive between restarts) still counts.
        if out.contains("state = running") { return .running }
        return out.contains("pid = ") ? .running : .stopped
    }

    /// Build the LaunchAgent plist from current settings and write it out.
    static func writePlist(settings: AgentSettings) throws {
        var env: [String: String] = [
            "HOME": Paths.home.path,
            "PATH": "\(Paths.venv.path)/bin:\(Paths.binDir.path):/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        func put(_ key: String, _ value: String) {
            let v = value.trimmingCharacters(in: .whitespaces)
            if !v.isEmpty { env[key] = v }
        }
        put("XEROTIER_AGENT_JOIN_KEY", settings.joinKey)
        put("XEROTIER_AGENT_MAX_CONCURRENT", settings.maxConcurrent)
        put("XEROTIER_AGENT_LOG_LEVEL", settings.logLevel)
        put("XEROTIER_AGENT_METRICS_PORT", settings.metricsPort)

        // Compose the extra vLLM args, folding in the tuning the user chose so it
        // overrides the agent's auto-detected defaults. The entrypoint splits
        // this on spaces into individual --vllm-arg= values.
        var vllmArgs = settings.vllmArgs.trimmingCharacters(in: .whitespaces)
        func appendArg(_ flag: String, _ value: String) {
            let v = value.trimmingCharacters(in: .whitespaces)
            guard !v.isEmpty else { return }
            if !vllmArgs.isEmpty { vllmArgs += " " }
            vllmArgs += "\(flag) \(v)"
        }
        appendArg("--gpu-memory-utilization", settings.gpuMemoryUtilization)
        appendArg("--max-num-seqs", settings.maxNumSeqs)
        put("XEROTIER_AGENT_VLLM_ARGS", vllmArgs)
        put("XEROTIER_AGENT_VLLM_ENV", settings.vllmEnv)
        if settings.allowInsecure { env["XEROTIER_AGENT_ALLOW_INSECURE"] = "1" }
        if settings.disableMetrics { env["XEROTIER_AGENT_DISABLE_METRICS_SERVER"] = "1" }

        let plist: [String: Any] = [
            "Label": Paths.label,
            "ProgramArguments": [Paths.entrypoint.path],
            "EnvironmentVariables": env,
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
            "StandardOutPath": Paths.outLog.path,
            "StandardErrorPath": Paths.errLog.path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                      format: .xml, options: 0)
        try FileManager.default.createDirectory(at: Paths.launchAgentsDir,
                                                withIntermediateDirectories: true)
        try data.write(to: Paths.plist)
    }

    /// Enable + (re)bootstrap the agent so it runs now and at login.
    @discardableResult
    static func start(emit: @escaping LogEmit) async -> Bool {
        // Clear any prior disabled state (from stop) before bootstrapping.
        await Shell.run("/bin/launchctl", ["enable", Paths.serviceTarget], emit: { _, _ in })
        await Shell.run("/bin/launchctl", ["bootout", Paths.serviceTarget], emit: { _, _ in })
        let code = await Shell.run("/bin/launchctl",
                                   ["bootstrap", Paths.domainTarget, Paths.plist.path],
                                   emit: emit)
        return code == 0
    }

    /// Stop the agent and forcibly reap everything it spawned. A graceful
    /// `bootout` tells the agent to shut down, but vLLM/MLX worker processes can
    /// outlive it; this escalates to ensure nothing is left holding the GPU.
    static func stop(emit: @escaping LogEmit) async {
        // Remove the job from launchd first so KeepAlive can't relaunch anything
        // we're about to kill.
        await Shell.run("/bin/launchctl", ["bootout", Paths.serviceTarget], emit: emit)
        await Shell.run("/bin/launchctl", ["disable", Paths.serviceTarget], emit: { _, _ in })

        emit("Force-stopping any lingering agent / vLLM processes…", .out)
        await reap(signal: "TERM")
        try? await Task.sleep(for: .seconds(2))
        await reap(signal: "KILL")
    }

    /// Signal lingering processes: the agent binary by absolute path, and
    /// anything launched from the vLLM venv (the wrapper interpreter plus every
    /// vllm/MLX subprocess, which all carry the venv path on their command line).
    private static func reap(signal: String) async {
        for pattern in [Paths.agentBin.path, Paths.venv.path] {
            await Shell.run("/usr/bin/pkill", ["-\(signal)", "-f", pattern], emit: { _, _ in })
        }
    }

    /// Delete the local enrollment state so the next start re-enrolls (used to
    /// re-bootstrap with a new join key).
    static func clearEnrollment() {
        try? FileManager.default.removeItem(at: Paths.enrollmentState)
    }

    static func uninstall(purge: Bool, emit: @escaping LogEmit) async {
        await stop(emit: emit)
        for url in [Paths.plist, Paths.vllmWrapper, Paths.entrypoint] {
            try? FileManager.default.removeItem(at: url)
        }
        emit("Removed LaunchAgent and rendered files.", .out)
        if purge {
            try? FileManager.default.removeItem(at: Paths.agentBin)
            try? FileManager.default.removeItem(at: Paths.venv)
            emit("Purged agent binary and venv.", .out)
        }
    }
}
