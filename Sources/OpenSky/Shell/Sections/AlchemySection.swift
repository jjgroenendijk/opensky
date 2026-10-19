// World > Inventory & Equipment > Alchemy: opens a lab by name, chooses carried
// ingredients, previews and brews, eats one to learn it, and poisons the weapon.

import AppKit
import OpenSkyFormatsESM
import OpenSkyInventory

final class AlchemySection: PanelSectionViewController {
    weak var provider: (any AlchemyControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let labControl = NSPopUpButton()
    let openControl = NSButton(title: "Open lab", target: nil, action: nil)
    let ingredientControl = NSPopUpButton()
    let chooseControl = NSButton(title: "Choose", target: nil, action: nil)
    let clearControl = NSButton(title: "Clear", target: nil, action: nil)
    let brewControl = NSButton(title: "Brew", target: nil, action: nil)
    let eatControl = NSButton(title: "Eat", target: nil, action: nil)
    let poisonControl = NSPopUpButton()
    let applyPoisonControl = NSButton(title: "Apply poison", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "AlchemyStatsLabel")
    private var ingredientIDs: [FormID] = []
    private var poisonIDs: [FormID] = []

    override var sectionTitle: String {
        "Alchemy"
    }

    override var sectionIdentifier: String {
        "alchemy"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        for (popUp, identifier) in [
            (labControl, "AlchemyLabControl"), (ingredientControl, "AlchemyIngredientControl"),
            (poisonControl, "AlchemyPoisonControl")
        ] {
            PanelComponents.configurePopUp(
                popUp, target: self, action: #selector(noAction), identifier: identifier, width: 260
            )
        }
        PanelComponents.configureButtons([
            PanelButtonSpec(
                openControl, #selector(openLab), "AlchemyOpenControl", "Uses the lab as if at it."
            ),
            PanelButtonSpec(
                chooseControl, #selector(choose), "AlchemyChooseControl", "Adds or removes it."
            ),
            PanelButtonSpec(
                clearControl, #selector(clear), "AlchemyClearControl", "Removes every choice."
            ),
            PanelButtonSpec(
                brewControl, #selector(brew), "AlchemyBrewControl", "Uses one of each, makes it."
            ),
            PanelButtonSpec(
                eatControl, #selector(eat), "AlchemyEatControl", "Eats one, which teaches it."
            ),
            PanelButtonSpec(
                applyPoisonControl, #selector(applyPoison), "AlchemyApplyPoisonControl",
                "Puts the poison on the weapon in the right hand."
            )
        ], target: self)
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Lab", captionWidth: 70, field: labControl
                ),
                PanelComponents.buttonRow([openControl]),
                PanelComponents.labeledFieldRow(
                    caption: "Ingredient", captionWidth: 70, field: ingredientControl
                ),
                PanelComponents.buttonRow([chooseControl, clearControl, brewControl, eatControl]),
                PanelComponents.labeledFieldRow(
                    caption: "Poison", captionWidth: 70, field: poisonControl
                ),
                PanelComponents.buttonRow([applyPoisonControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        sync(provider?.alchemySnapshot ?? .unavailable)
    }

    override func refreshReadout() {
        let snapshot = provider?.alchemySnapshot ?? .unavailable
        sync(snapshot)
        statsLabel.stringValue = snapshot.readoutText
    }

    private func sync(_ snapshot: AlchemyControlSnapshot) {
        if labControl.itemTitles != snapshot.labs {
            labControl.removeAllItems()
            labControl.addItems(withTitles: snapshot.labs)
        }
        let ingredients = snapshot.ingredients
        if
            ingredients.map(\.id) != ingredientIDs
            || ingredientControl.itemTitles != ingredients.map(Self.title)
        {
            ingredientIDs = ingredients.map(\.id)
            ingredientControl.removeAllItems()
            ingredientControl.addItems(withTitles: ingredients.map(Self.title))
        }
        if snapshot.poisons.map(\.id) != poisonIDs {
            poisonIDs = snapshot.poisons.map(\.id)
            poisonControl.removeAllItems()
            poisonControl.addItems(withTitles: snapshot.poisons.map { "\($0.name) (\($0.count))" })
        }
        let open = snapshot.labName != nil
        openControl.isEnabled = snapshot.isAvailable && !snapshot.labs.isEmpty
        chooseControl.isEnabled = open && !ingredientIDs.isEmpty
        clearControl.isEnabled = open
        brewControl.isEnabled = open
        eatControl.isEnabled = !ingredientIDs.isEmpty
        applyPoisonControl.isEnabled = !poisonIDs.isEmpty
    }

    private static func title(_ ingredient: AlchemyIngredientReadout) -> String {
        let mark = ingredient.isChosen ? "* " : ""
        return "\(mark)\(ingredient.name) (\(ingredient.count)): \(ingredient.effectsText)"
    }

    private var selectedIngredient: FormID? {
        let index = ingredientControl.indexOfSelectedItem
        return ingredientIDs.indices.contains(index) ? ingredientIDs[index] : nil
    }

    // MARK: - Actions

    @objc private func noAction() {}

    @objc private func openLab() {
        guard let title = labControl.titleOfSelectedItem else { return }
        provider?.openAlchemyLab(title)
        finishInteraction()
    }

    @objc private func choose() {
        guard let item = selectedIngredient else { return }
        provider?.toggleAlchemyIngredient(item)
        finishInteraction()
    }

    @objc private func clear() {
        provider?.clearAlchemyIngredients()
        finishInteraction()
    }

    @objc private func brew() {
        provider?.brewChosenIngredients()
        finishInteraction()
    }

    @objc private func eat() {
        guard let item = selectedIngredient else { return }
        provider?.eatIngredient(item)
        finishInteraction()
    }

    @objc private func applyPoison() {
        let index = poisonControl.indexOfSelectedItem
        guard poisonIDs.indices.contains(index) else { return }
        provider?.applyPoison(poisonIDs[index])
        finishInteraction()
    }
}
