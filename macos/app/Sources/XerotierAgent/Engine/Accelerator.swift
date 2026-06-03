// SPDX-License-Identifier: MIT
import Foundation
import Metal

/// Live readout of the Apple GPU the agent reports as its accelerator. Mirrors
/// the agent's own GPUResources.detect() on macOS: a single unified-memory
/// device whose budget is MTLDevice.recommendedMaxWorkingSetSize.
struct AcceleratorInfo {
    let name: String
    let workingSetBytes: UInt64
    let unifiedMemory: Bool
    let totalRAMBytes: UInt64

    var budgetDisplay: String { Self.bytes(workingSetBytes) }
    var totalRAMDisplay: String { Self.bytes(totalRAMBytes) }

    private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }
}

enum Accelerator {
    /// Synchronous and cheap; returns nil on the (Apple-Silicon-impossible)
    /// case of no Metal device.
    static func detect() -> AcceleratorInfo? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return AcceleratorInfo(
            name: device.name,
            workingSetBytes: device.recommendedMaxWorkingSetSize,
            unifiedMemory: device.hasUnifiedMemory,
            totalRAMBytes: ProcessInfo.processInfo.physicalMemory
        )
    }
}
