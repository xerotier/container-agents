// SPDX-License-Identifier: MIT
import Foundation

struct PreflightCheck: Identifiable {
    let id = UUID()
    let name: String
    let ok: Bool
    /// Required checks block install; non-required ones (e.g. uv) are
    /// auto-provisioned by the installer when missing.
    let required: Bool
    let detail: String
}

enum Preflight {
    /// Inspect the host. Side-effect free — safe to run on launch and on demand.
    static func run() async -> [PreflightCheck] {
        var checks: [PreflightCheck] = []

        let arch = machineArch()
        checks.append(.init(name: "Apple Silicon (arm64)",
                            ok: arch == "arm64",
                            required: true,
                            detail: arch.isEmpty ? "unknown" : arch))

        let v = ProcessInfo.processInfo.operatingSystemVersion
        checks.append(.init(name: "macOS 15 or newer",
                            ok: v.majorVersion >= 15,
                            required: true,
                            detail: "\(v.majorVersion).\(v.minorVersion)"))

        let curl = FileManager.default.isExecutableFile(atPath: "/usr/bin/curl")
        checks.append(.init(name: "curl",
                            ok: curl,
                            required: true,
                            detail: curl ? "/usr/bin/curl" : "missing"))

        let uv = locateUV()
        checks.append(.init(name: "uv",
                            ok: uv != nil,
                            required: false,
                            detail: uv ?? "will be installed automatically"))

        return checks
    }

    static func requiredSatisfied(_ checks: [PreflightCheck]) -> Bool {
        checks.filter(\.required).allSatisfy(\.ok)
    }

    /// Locate a usable `uv`, searching the dirs a Finder-launched app won't have
    /// on PATH.
    static func locateUV() -> String? {
        let candidates = [
            Paths.binDir.appending(path: "uv").path,
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
