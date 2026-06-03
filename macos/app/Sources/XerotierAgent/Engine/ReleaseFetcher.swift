// SPDX-License-Identifier: MIT
import Foundation

/// Resolves and downloads the prebuilt `xerotier-xim-agent` from GitHub releases.
enum ReleaseFetcher {
    static let repo = "cloudnull/xerotier-public"

    struct Asset: Decodable { let name: String; let browser_download_url: String }
    struct Release: Decodable { let draft: Bool; let prerelease: Bool; let assets: [Asset] }

    enum FetchError: LocalizedError {
        case noAsset(String)
        case api(String)
        case http(Int)
        var errorDescription: String? {
            switch self {
            case .noAsset(let a): return "No release asset named \(a) found."
            case .api(let m): return "Releases API error: \(m)"
            case .http(let c): return "Download failed with HTTP \(c)."
            }
        }
    }

    /// Asset name follows `uname -sm` joined by '-' (e.g. Darwin-arm64).
    static func assetName() -> String {
        "xerotier-xim-agent-\(systemName())-\(machineArch())"
    }

    /// Walk releases newest-first for the newest stable (or, with
    /// allowPrerelease, prerelease) release carrying the asset.
    static func resolveURL(preRelease: Bool) async throws -> String {
        let asset = assetName()
        let api = URL(string: "https://api.github.com/repos/\(repo)/releases")!
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("xerotier-agent-gui", forHTTPHeaderField: "User-Agent")

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw FetchError.api(error.localizedDescription)
        }
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw FetchError.api("HTTP \(http.statusCode) (network or rate limit)")
        }
        let releases = try JSONDecoder().decode([Release].self, from: data)

        func find(includePrerelease: Bool) -> String? {
            for rel in releases where !rel.draft {
                if !includePrerelease && rel.prerelease { continue }
                if let a = rel.assets.first(where: { $0.name == asset }) {
                    return a.browser_download_url
                }
            }
            return nil
        }

        if let url = find(includePrerelease: false) { return url }
        if preRelease, let url = find(includePrerelease: true) { return url }
        throw FetchError.noAsset(asset)
    }

    /// Download the asset to `dest`, make it executable, and clear quarantine.
    static func download(preRelease: Bool, to dest: URL, emit: @escaping LogEmit) async throws {
        let urlString = try await resolveURL(preRelease: preRelease)
        emit("Resolved \(assetName()) → \(urlString)", .out)
        guard let url = URL(string: urlString) else { throw FetchError.api("bad URL") }

        let (tmp, resp) = try await URLSession.shared.download(from: url)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw FetchError.http(http.statusCode)
        }

        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tmp, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)

        // Best-effort: clear the Gatekeeper quarantine xattr so launchd can exec it.
        await Shell.run("/usr/bin/xattr",
                        ["-d", "com.apple.quarantine", dest.path],
                        emit: { _, _ in })
        emit("Installed agent → \(dest.path)", .out)
    }
}
