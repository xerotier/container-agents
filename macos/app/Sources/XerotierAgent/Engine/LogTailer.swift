// SPDX-License-Identifier: MIT
import Foundation

/// Streams the agent's launchd log files into the UI via `tail -F`, tagging
/// stdout vs stderr. `-F` tolerates the files not existing yet (launchd creates
/// them on first start) and survives log rotation.
final class LogTailer {
    private var procs: [Process] = []

    func start(emit: @escaping LogEmit) {
        stop()
        tail(Paths.outLog, stream: .out, emit: emit)
        tail(Paths.errLog, stream: .err, emit: emit)
    }

    func stop() {
        for p in procs where p.isRunning { p.terminate() }
        procs.removeAll()
    }

    private func tail(_ file: URL, stream: LogStream, emit: @escaping LogEmit) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        p.arguments = ["-n", "200", "-F", file.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        Shell.attachReader(pipe, stream: stream, emit: emit)
        do { try p.run(); procs.append(p) } catch { /* file dir may not exist yet */ }
    }
}
