// SPDX-License-Identifier: MIT
import Foundation

/// A callback that receives a single line of process output on an arbitrary
/// thread. Implementations are responsible for hopping to the main actor.
typealias LogEmit = (String, LogStream) -> Void

/// Buffers raw pipe bytes and yields complete lines.
private final class LineAccumulator {
    private var data = Data()

    func append(_ new: Data) -> [String] {
        data.append(new)
        var lines: [String] = []
        while let nl = data.firstIndex(of: 0x0A) {
            let lineData = data.subdata(in: data.startIndex..<nl)
            lines.append(String(decoding: lineData, as: UTF8.self))
            data.removeSubrange(data.startIndex...nl)
        }
        return lines
    }

    func flush() -> String? {
        guard !data.isEmpty else { return nil }
        defer { data.removeAll() }
        return String(decoding: data, as: UTF8.self)
    }
}

enum Shell {
    /// Stream a process line-by-line to `emit`, resolving with its exit code.
    /// Never blocks the calling thread.
    @discardableResult
    static func run(_ launchPath: String,
                    _ args: [String],
                    env extra: [String: String]? = nil,
                    emit: @escaping LogEmit) async -> Int32 {
        await withCheckedContinuation { cont in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: launchPath)
            proc.arguments = args
            proc.environment = environment(extra)

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            attachReader(outPipe, stream: .out, emit: emit)
            attachReader(errPipe, stream: .err, emit: emit)

            proc.terminationHandler = { p in
                cont.resume(returning: p.terminationStatus)
            }
            do {
                try proc.run()
            } catch {
                emit("failed to launch \(launchPath): \(error.localizedDescription)", .err)
                cont.resume(returning: 127)
            }
        }
    }

    /// Run a `/bin/bash -c` pipeline (for upstream `curl … | sh` installers).
    @discardableResult
    static func bash(_ script: String, emit: @escaping LogEmit) async -> Int32 {
        await run("/bin/bash", ["-c", script], emit: emit)
    }

    /// Run a process and capture its stdout as a string. Runs off the main
    /// thread; used for short queries (site-packages path, launchctl print).
    static func capture(_ launchPath: String,
                        _ args: [String],
                        env extra: [String: String]? = nil) async -> (code: Int32, out: String) {
        await Task.detached(priority: .userInitiated) { () -> (Int32, String) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: launchPath)
            proc.arguments = args
            proc.environment = environment(extra)
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            do { try proc.run() } catch { return (127, "") }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return (proc.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }

    /// Attach a line-reader to a pipe. Internal so LogTailer can reuse it.
    static func attachReader(_ pipe: Pipe, stream: LogStream, emit: @escaping LogEmit) {
        let handle = pipe.fileHandleForReading
        let acc = LineAccumulator()
        handle.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                if let rest = acc.flush() { emit(rest, stream) }
                return
            }
            for line in acc.append(data) { emit(line, stream) }
        }
    }

    private static func environment(_ extra: [String: String]?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Paths.augmentedPATH
        extra?.forEach { env[$0] = $1 }
        return env
    }
}
