// SPDX-License-Identifier: MIT
import Foundation

/// Streams the agent's launchd log files into the UI via `tail -F`, tagging
/// stdout vs stderr. `-F` tolerates the files not existing yet (launchd creates
/// them on first start) and survives log rotation.
final class LogTailer {
    private var procs: [Process] = []

    func start(emit: @escaping LogEmit) {
        stop()
        tail(Paths.outLog, emit: emit)
        tail(Paths.errLog, emit: emit)
    }

    func stop() {
        for p in procs where p.isRunning { p.terminate() }
        procs.removeAll()
    }

    private func tail(_ file: URL, emit: @escaping LogEmit) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        p.arguments = ["-n", "200", "-F", file.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        // Classify by severity, not by which log file the line came from.
        Shell.attachReader(pipe, stream: .out) { line, _ in
            emit(line, LogStream.classify(line))
        }
        do { try p.run(); procs.append(p) } catch { /* file dir may not exist yet */ }
    }
}
