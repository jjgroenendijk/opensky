// The item control fake and the `FakeWorldProviders` forwarding that goes with
// it, shared by the Items section suites and by the real-data inventory suites in
// openskyRealDataTests. See openskyTestSupport/AGENTS.md.

import AppKit
@testable import opensky
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
    func takeInteractionTarget() -> String {
        record("take")
    }

    @discardableResult
    func openInteractionTargetContainer() -> String {
        record("search")
    }

    @discardableResult
    func takeAllFromOpenContainer() -> String {
        record("takeAll")
    }

    @discardableResult
    func closeOpenContainer() -> String {
        record("close")
    }

    @discardableResult
    func dropPlayerItem(_ item: FormID?, count: Int32) -> String {
        record("drop \(item?.description ?? "first")×\(count)")
    }

    @discardableResult
    func equipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> String {
        record("equip \(item?.description ?? "first") on \(target)")
    }

    @discardableResult
    func unequipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> String {
        record("unequip \(item?.description ?? "first") on \(target)")
    }

    @discardableResult
    private func record(_ action: String) -> String {
        actions.append(action)
        return action
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
    func takeInteractionTarget() -> String {
        items.takeInteractionTarget()
    }

    @discardableResult
    func openInteractionTargetContainer() -> String {
        items.openInteractionTargetContainer()
    }

    @discardableResult
    func takeAllFromOpenContainer() -> String {
        items.takeAllFromOpenContainer()
    }

    @discardableResult
    func closeOpenContainer() -> String {
        items.closeOpenContainer()
    }

    @discardableResult
    func dropPlayerItem(_ item: FormID?, count: Int32) -> String {
        items.dropPlayerItem(item, count: count)
    }

    @discardableResult
    func equipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> String {
        items.equipItem(item, on: target)
    }

    @discardableResult
    func unequipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> String {
        items.unequipItem(item, on: target)
    }
}
