// The item control fake and the `FakeWorldProviders` forwarding that goes with
// it, shared by the Items section suites and by the real-data inventory suites in
// OpenSkyRealDataTests. See Tests/HostedTestSupport/AGENTS.md.

import AppKit
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventory
import Testing

/// Records what the section asked the engine to do, and answers with whatever
/// reading the test set. Shared with `DestinationRegistryTests`, which holds one
/// of these so a registry-level panel build and a button press are observed
/// through the same fake.
@MainActor
final class FakeItemProvider: ItemControlProviding {
    var itemControlSnapshot = ItemControlSnapshot.unavailable
    /// Every action a control ran, in order.
    private(set) var actions: [String] = []

    @discardableResult
    func takeInteractionTarget() -> ItemActionOutcome {
        record("take")
    }

    @discardableResult
    func openInteractionTargetContainer() -> ItemActionOutcome {
        record("search")
    }

    @discardableResult
    func takeAllFromOpenContainer() -> ItemActionOutcome {
        record("takeAll")
    }

    @discardableResult
    func closeOpenContainer() -> ItemActionOutcome {
        record("close")
    }

    @discardableResult
    func dropPlayerItem(_ item: FormID?, count: Int32) -> ItemActionOutcome {
        record("drop \(item?.description ?? "first")×\(count)")
    }

    @discardableResult
    func equipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> ItemActionOutcome {
        record("equip \(item?.description ?? "first") on \(target)")
    }

    @discardableResult
    func unequipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> ItemActionOutcome {
        record("unequip \(item?.description ?? "first") on \(target)")
    }

    @discardableResult
    private func record(_ action: String) -> ItemActionOutcome {
        actions.append(action)
        return .idle
    }
}

/// Forwards the item seam to the shared recorder, exactly as the runtime-state
/// and trigger seams are forwarded. The conformance itself comes from
/// `WorldControlProviders`, which `FakeWorldProviders` already declares.
extension FakeWorldProviders {
    var itemControlSnapshot: ItemControlSnapshot {
        items.itemControlSnapshot
    }

    @discardableResult
    func takeInteractionTarget() -> ItemActionOutcome {
        items.takeInteractionTarget()
    }

    @discardableResult
    func openInteractionTargetContainer() -> ItemActionOutcome {
        items.openInteractionTargetContainer()
    }

    @discardableResult
    func takeAllFromOpenContainer() -> ItemActionOutcome {
        items.takeAllFromOpenContainer()
    }

    @discardableResult
    func closeOpenContainer() -> ItemActionOutcome {
        items.closeOpenContainer()
    }

    @discardableResult
    func dropPlayerItem(_ item: FormID?, count: Int32) -> ItemActionOutcome {
        items.dropPlayerItem(item, count: count)
    }

    @discardableResult
    func equipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> ItemActionOutcome {
        items.equipItem(item, on: target)
    }

    @discardableResult
    func unequipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> ItemActionOutcome {
        items.unequipItem(item, on: target)
    }
}
