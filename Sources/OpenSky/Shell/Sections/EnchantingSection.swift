// World > Inventory & Equipment > Enchanting: disenchants a carried item, and enchants a
// plain one with known enchantments and a filled soul gem, as at an arcane enchanter.

import AppKit
import OpenSkyFormatsESM
import OpenSkyMagic
import OpenSkyMagicInterface

final class EnchantingSection: PanelSectionViewController {
    weak var provider: (any EnchantingControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let disenchantItemControl = NSPopUpButton()
    let disenchantControl = NSButton(title: "Disenchant", target: nil, action: nil)
    let itemControl = NSPopUpButton()
    let baseControl = NSPopUpButton()
    let secondBaseControl = NSPopUpButton()
    let gemControl = NSPopUpButton()
    let enchantControl = NSButton(title: "Enchant", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "EnchantingStatsLabel")
    private var snapshot = EnchantingControlSnapshot.unavailable

    override var sectionTitle: String {
        "Enchanting"
    }

    override var sectionIdentifier: String {
        "enchanting"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        for (popUp, identifier) in [
            (disenchantItemControl, "EnchantingDisenchantItemControl"),
            (itemControl, "EnchantingItemControl"), (baseControl, "EnchantingBaseControl"),
            (secondBaseControl, "EnchantingSecondBaseControl"), (gemControl, "EnchantingGemControl")
        ] {
            PanelComponents.configurePopUp(
                popUp, target: self, action: #selector(choiceChanged), identifier: identifier,
                width: 260
            )
        }
        PanelComponents.configureButtons([
            PanelButtonSpec(
                disenchantControl, #selector(disenchant), "EnchantingDisenchantControl",
                "Destroys the item and learns its enchantment."
            ),
            PanelButtonSpec(
                enchantControl, #selector(enchant), "EnchantingEnchantControl",
                "Puts the enchantments on the item and uses the soul gem."
            )
        ], target: self)
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Enchanted", captionWidth: 80, field: disenchantItemControl
                ),
                PanelComponents.buttonRow([disenchantControl]),
                PanelComponents.labeledFieldRow(
                    caption: "Item",
                    captionWidth: 80,
                    field: itemControl
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Enchantment", captionWidth: 80, field: baseControl
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Second", captionWidth: 80, field: secondBaseControl
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Soul gem",
                    captionWidth: 80,
                    field: gemControl
                ),
                PanelComponents.buttonRow([enchantControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        sync(provider?.enchantingSnapshot ?? .unavailable)
    }

    override func refreshReadout() {
        let latest = provider?.enchantingSnapshot ?? .unavailable
        sync(latest)
        var preview = "choose an item, an enchantment, and a gem"
        if let choice = choice(), let provider {
            preview = Self.previewText(
                provider.enchantingPreview(choice.item, with: choice.bases, gem: choice.gem)
            )
        }
        statsLabel.stringValue = latest.readoutText + "\nPreview: \(preview)"
    }

    private func sync(_ latest: EnchantingControlSnapshot) {
        snapshot = latest
        Self.fill(disenchantItemControl, latest.disenchantable.map(\.name))
        Self.fill(itemControl, latest.enchantable.map(\.name))
        Self.fill(baseControl, latest.bases.map(\.name))
        Self.fill(secondBaseControl, ["None"] + latest.bases.map(\.name))
        Self.fill(gemControl, latest.gems.map(\.name))
        disenchantControl.isEnabled = latest.isAvailable && !latest.disenchantable.isEmpty
        secondBaseControl.isEnabled = latest.allowedBases > 1
        enchantControl.isEnabled = choice() != nil
    }

    /// Keeps the selection by title, so a refresh does not reset the user's choice.
    private static func fill(_ popUp: NSPopUpButton, _ titles: [String]) {
        guard popUp.itemTitles != titles else { return }
        let selected = popUp.titleOfSelectedItem
        popUp.removeAllItems()
        popUp.addItems(withTitles: titles)
        if let selected, titles.contains(selected) {
            popUp.selectItem(withTitle: selected)
        }
    }

    private static func previewText(_ preview: Result<MadeEnchantment, EnchantingRefusal>)
        -> String
    {
        switch preview {
        case let .success(made): made.previewText
        case let .failure(refusal): EnchantingOutcome.refused(refusal).text
        }
    }

    private struct Choice {
        let item: FormID
        let bases: [ReferenceKey]
        let gem: SoulGemCandidate
    }

    /// The chosen item, bases, and gem, or nil while one is missing.
    private func choice() -> Choice? {
        guard
            let item = Self.pick(snapshot.enchantable, at: itemControl)?.id,
            let base = Self.pick(snapshot.bases, at: baseControl)?.key,
            let gem = Self.pick(snapshot.gems, at: gemControl)?.gem
        else { return nil }
        let second = secondBaseControl.indexOfSelectedItem - 1
        let extra = secondBaseControl.isEnabled && snapshot.bases.indices.contains(second)
            ? [snapshot.bases[second].key] : []
        return Choice(item: item, bases: [base] + extra.filter { $0 != base }, gem: gem)
    }

    private static func pick<Element>(_ list: [Element], at popUp: NSPopUpButton) -> Element? {
        let index = popUp.indexOfSelectedItem
        return list.indices.contains(index) ? list[index] : nil
    }

    // MARK: - Actions

    @objc private func choiceChanged() {
        refreshReadout()
    }

    @objc private func disenchant() {
        guard let item = Self.pick(snapshot.disenchantable, at: disenchantItemControl)
        else { return }
        provider?.disenchant(item.id)
        finishInteraction()
    }

    @objc private func enchant() {
        guard let choice = choice() else { return }
        provider?.enchant(choice.item, with: choice.bases, gem: choice.gem, name: nil)
        finishInteraction()
    }
}
