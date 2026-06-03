// SPDX-License-Identifier: MIT
import Foundation

/// Filesystem locations and identifiers for the XIM agent install.
enum Paths {
    static let label = "com.xerotier.xim-agent"

    static let home = FileManager.default.homeDirectoryForCurrentUser
    static var binDir: URL { home.appending(path: ".local/bin") }
    static var venv: URL { home.appending(path: ".venv-vllm-metal") }
    static var venvPython: URL { venv.appending(path: "bin/python3") }
    static var venvVLLM: URL { venv.appending(path: "bin/vllm") }
    static var logDir: URL { home.appending(path: "Library/Logs/xerotier") }
    static var launchAgentsDir: URL { home.appending(path: "Library/LaunchAgents") }
    static var configDir: URL { home.appending(path: ".config/xerotier") }

    static var plist: URL { launchAgentsDir.appending(path: "\(label).plist") }
    static var enrollmentState: URL { configDir.appending(path: "enrollment.json") }
    static var agentBin: URL { binDir.appending(path: "xerotier-xim-agent") }
    static var vllmWrapper: URL { binDir.appending(path: "xerotier-vllm") }
    static var entrypoint: URL { binDir.appending(path: "xerotier-xim-entrypoint") }
    static var outLog: URL { logDir.appending(path: "xim-agent.out.log") }
    static var errLog: URL { logDir.appending(path: "xim-agent.err.log") }

    static var uid: String { String(getuid()) }
    static var serviceTarget: String { "gui/\(uid)/\(label)" }
    static var domainTarget: String { "gui/\(uid)" }

    /// PATH for spawned processes. GUI apps launched from Finder inherit a
    /// bare PATH, so we prepend the venv and the user/homebrew bin dirs where
    /// uv, curl, and friends actually live.
    static var augmentedPATH: String {
        "\(venv.path)/bin:\(binDir.path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }
}

/// Reads a NUL-terminated C char field from `utsname` (sysname, machine, …).
func utsnameField(_ ptr: UnsafePointer<CChar>) -> String {
    String(cString: ptr)
}

func machineArch() -> String {
    var info = utsname()
    uname(&info)
    return withUnsafePointer(to: &info.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) { utsnameField($0) }
    }
}

func systemName() -> String {
    var info = utsname()
    uname(&info)
    return withUnsafePointer(to: &info.sysname) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) { utsnameField($0) }
    }
}
