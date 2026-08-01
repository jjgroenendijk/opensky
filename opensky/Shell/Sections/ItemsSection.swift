// World > HUD & Interaction > Items: the M12.1.3 acceptance surface.
//
// Everything the use key can do to an item is reachable here without knowing a
// CLI command: take what the crosshair is on, open the container it is on,
// empty that container, and drop something back into the world. The readout
// below the buttons is the whole state those operations move — what the player
// carries, what the open container holds, and how many objects the session has
// spawned — so a change is visible in the same place it was made.
//
// It carries no override state: taking and dropping are world changes recorded
// in `WorldStateStore`, and World > Runtime State already owns resetting those.
// Adding a second reset here would give the same deltas two owners.

import AppKit

final class ItemsSection: PanelSectionViewController {
    weak var provider: (any ItemControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let takeControl = NSButton(title: "Take target", target: nil, action: nil)
    let searchControl = NSButton(title: "Search target", target: nil, action: nil)
    let takeAllControl = NSButton(title: "Take all", target: nil, action: nil)
    let closeControl = NSButton(title: "Close container", target: nil, action: nil)
    let dropControl = NSButton(title: "Drop", target: nil, action: nil)
    let dropFormIDField = NSTextField(string: "")
    let dropCountField = NSTextField(string: "1")

    private let statsLabel = PanelComponents.statsLabel(identifier: "ItemsStatsLabel")

    /// Longest inventory listing the readout prints. A full player inventory is
    /// hundreds of stacks and this is a 2 Hz readout, not a menu.
    private static let listedStackLimit = 8

    override var sectionTitle: String {
        "Items"
    }

    override var sectionIdentifier: String {
        "items"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureButton(
            takeControl, target: self, action: #selector(take), identifier: "ItemsTakeControl"
        )
        PanelComponents.configureButton(
            searchControl, target: self, action: #selector(search),
            identifier: "ItemsSearchControl"
        )
        PanelComponents.configureButton(
            takeAllControl, target: self, action: #selector(takeAll),
            identifier: "ItemsTakeAllControl"
        )
        PanelComponents.configureButton(
            closeControl, target: self, action: #selector(closeContainer),
            identifier: "ItemsCloseContainerControl"
        )
        PanelComponents.configureButton(
            dropControl, target: self, action: #selector(drop), identifier: "ItemsDropControl"
        )
        PanelComponents.configureTextField(
            dropFormIDField, identifier: "ItemsDropFormIDField", width: 150,
            placeholder: "first stack"
        )
        PanelComponents.configureTextField(
            dropCountField, identifier: "ItemsDropCountField", width: 60
        )
        return [
            PanelComponents.note(
                "Take and Search act on whatever the walk-mode crosshair is on, exactly as "
                    + "the use key does. Drop places the item in front of the player in the "
                    + "cell they are standing in; it renders, collides and can be taken again. "
                    + "A dropped object survives cell eviction and a save/load cycle."
            ),
            PanelComponents.buttonRow([takeControl, searchControl]),
            PanelComponents.buttonRow([takeAllControl, closeControl]),
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "FormID", captionWidth: 60, field: dropFormIDField
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Count", captionWidth: 60, field: dropCountField
                )
            ]),
            PanelComponents.buttonRow([dropControl]),
            statsLabel
        ]
    }

    // MARK: - Actions

    @objc private func take() {
        provider?.takeInteractionTarget()
        finishInteraction()
    }

    @objc private func search() {
        provider?.openInteractionTargetContainer()
        finishInteraction()
    }

    @objc private func takeAll() {
        provider?.takeAllFromOpenContainer()
        finishInteraction()
    }

    @objc private func closeContainer() {
        provider?.closeOpenContainer()
        finishInteraction()
    }

    @objc private func drop() {
        provider?.dropPlayerItem(Self.parseFormID(dropFormIDField.stringValue), count: dropCount)
        finishInteraction()
    }

    /// The count field, floored at one: dropping zero or minus three of
    /// something is never what the field meant.
    private var dropCount: Int32 {
        max(1, Int32(dropCountField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 1)
    }

    /// Hexadecimal FormID, with or without a `0x` prefix. Blank or unparseable
    /// is nil, which the provider reads as "the first stack the player has".
    static func parseFormID(_ text: String) -> FormID? {
        var trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasPrefix("0x") {
            trimmed = String(trimmed.dropFirst(2))
        }
        guard !trimmed.isEmpty, let raw = UInt32(trimmed, radix: 16) else { return nil }
        return FormID(raw)
    }

    // MARK: - Readout

    override func refreshReadout() {
        guard let snapshot = provider?.itemControlSnapshot, snapshot.isAvailable else {
            statsLabel.stringValue = ItemControlSnapshot.unavailable.lastActionText
            return
        }
        statsLabel.stringValue = [
            Self.targetLine(snapshot),
            Self.carriedLine(snapshot),
            Self.stackLines("Carried", snapshot.playerStacks),
            Self.containerLine(snapshot),
            "Spawned objects: \(snapshot.spawnedObjectCount)",
            snapshot.lastActionText
        ].joined(separator: "\n")
    }

    private static func targetLine(_ snapshot: ItemControlSnapshot) -> String {
        guard let name = snapshot.targetName else { return "Target: none" }
        let kind = snapshot.targetIsTakeable
            ? "takeable item"
            : (snapshot.targetIsContainer ? "container" : "not an item")
        return "Target: \(name) · \(kind)"
    }

    private static func carriedLine(_ snapshot: ItemControlSnapshot) -> String {
        let weight = String(format: "%.1f", snapshot.playerWeight)
        return "Carried: \(snapshot.playerStacks.count) stacks · "
            + "weight \(weight) · gold \(snapshot.playerGold)"
    }

    private static func containerLine(_ snapshot: ItemControlSnapshot) -> String {
        guard let name = snapshot.containerName else { return "Container: none open" }
        return "Container: \(name)\n" + stackLines("Holds", snapshot.containerStacks)
    }

    /// One indented line per stack, truncated with a stated remainder so the
    /// readout never silently shows part of an inventory as the whole of it.
    private static func stackLines(_ title: String, _ stacks: [ItemStackReadout]) -> String {
        guard !stacks.isEmpty else { return "  \(title): empty" }
        var lines = stacks.prefix(listedStackLimit).map { "  \($0.count) × \($0.name)" }
        if stacks.count > listedStackLimit {
            lines.append("  … \(stacks.count - listedStackLimit) more")
        }
        return lines.joined(separator: "\n")
    }
}
