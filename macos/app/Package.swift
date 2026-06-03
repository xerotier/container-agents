// swift-tools-version:5.10
// SPDX-License-Identifier: MIT
import PackageDescription

// Xerotier XIM Agent — native macOS GUI (UX prototype).
//
// This is the native macOS deployment of the Xerotier agent: a full-native
// installer + environment-prep + control surface that wraps the downloaded
// `xerotier-xim-agent` release binary.
//
// At this stage every privileged/long-running action is SIMULATED (see
// AppModel) so we can iterate on the flow before wiring the real engine
// (uv / vllm-metal install, URLSession download, SMAppService LaunchAgent).
//
// Run from the CLI:   swift run
// Or open Package.swift in Xcode and Run.
let package = Package(
    name: "XerotierAgent",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "XerotierAgent",
            path: "Sources/XerotierAgent"
        )
    ]
)
