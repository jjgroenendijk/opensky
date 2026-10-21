// World > Combat & Physics > Shouts: teach a shout, equip it, spend dragon souls on its
// words, and shout one, two, or three words. The shout key does the same in the world.

import AppKit
import OpenSkyFormatsESM
import OpenSkyMagic

final class ShoutsSection: PanelSectionViewController {
    weak var provider: (any ShoutControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let shoutControl = NSPopUpButton()
    let learnControl = NSButton(title: "Learn", target: nil, action: nil)
    let equipControl = NSButton(title: "Equip", target: nil, action: nil)
    let unlockControl = NSButton(title: "Unlock next word", target: nil, action: nil)
    let addSoulControl = NSButton(title: "Add dragon soul", target: nil, action: nil)
    let shoutOneControl = NSButton(title: "Shout 1", target: nil, action: nil)
    let shoutTwoControl = NSButton(title: "Shout 2", target: nil, action: nil)
    let shoutThreeControl = NSButton(title: "Shout 3", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "ShoutsStatsLabel")
    private var snapshot = ShoutControlSnapshot.unavailable

    override var sectionTitle: String {
        "Shouts"
    }

    override var sectionIdentifier: String {
        "shouts"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configurePopUp(
            shoutControl, target: self, action: #selector(choiceChanged),
            identifier: "ShoutsShoutControl", width: 260
        )
        configureButtons()
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Shout",
                    captionWidth: 80,
                    field: shoutControl
                ),
                PanelComponents.buttonRow([learnControl, equipControl, unlockControl]),
                PanelComponents.buttonRow([addSoulControl]),
                PanelComponents.buttonRow([shoutOneControl, shoutTwoControl, shoutThreeControl])
            ]),
            statsLabel
        ]
    }

    private func configureButtons() {
        PanelComponents.configureButtons([
            PanelButtonSpec(
                learnControl,
                #selector(learn),
                "ShoutsLearnControl",
                "Teaches and unlocks every word of the shout."
            ),
            PanelButtonSpec(
                equipControl,
                #selector(equip),
                "ShoutsEquipControl",
                "Equips the shout on the shout key."
            ),
            PanelButtonSpec(
                unlockControl,
                #selector(unlock),
                "ShoutsUnlockControl",
                "Spends a dragon soul on the next learned word."
            ),
            PanelButtonSpec(
                addSoulControl,
                #selector(addSoul),
                "ShoutsAddSoulControl",
                "Gives the player one dragon soul."
            ),
            PanelButtonSpec(
                shoutOneControl,
                #selector(shoutOne),
                "ShoutsShoutOneControl",
                "Taps the shout key."
            ),
            PanelButtonSpec(
                shoutTwoControl,
                #selector(shoutTwo),
                "ShoutsShoutTwoControl",
                "Holds the shout key for two words."
            ),
            PanelButtonSpec(
                shoutThreeControl,
                #selector(shoutThree),
                "ShoutsShoutThreeControl",
                "Holds the shout key for three words."
            )
        ], target: self)
    }

    override func syncControls() {
        sync(provider?.shoutSnapshot ?? .unavailable)
    }

    override func refreshReadout() {
        let latest = provider?.shoutSnapshot ?? .unavailable
        sync(latest)
        statsLabel.stringValue = latest.readoutText
    }

    private func sync(_ latest: ShoutControlSnapshot) {
        snapshot = latest
        let titles = latest.all.map { readout in
            guard readout.wordsKnown > 0 else { return readout.name }
            return "\(readout.name) (\(readout.wordsUnlocked)/\(readout.wordCount))"
        }
        if shoutControl.itemTitles != titles {
            let selected = shoutControl.indexOfSelectedItem
            shoutControl.removeAllItems()
            shoutControl.addItems(withTitles: titles)
            if titles.indices.contains(selected) {
                shoutControl.selectItem(at: selected)
            }
        }
        let chosen = chosenShout() != nil
        for control in [learnControl, equipControl, unlockControl] {
            control.isEnabled = latest.isAvailable && chosen
        }
        for control in [addSoulControl, shoutOneControl, shoutTwoControl, shoutThreeControl] {
            control.isEnabled = latest.isAvailable
        }
    }

    private func chosenShout() -> ReferenceKey? {
        let index = shoutControl.indexOfSelectedItem
        return snapshot.all.indices.contains(index) ? snapshot.all[index].key : nil
    }

    // MARK: - Actions

    @objc private func choiceChanged() {
        refreshReadout()
    }

    @objc private func learn() {
        guard let shout = chosenShout() else { return }
        provider?.learnShout(shout)
        finishInteraction()
    }

    @objc private func equip() {
        guard let shout = chosenShout() else { return }
        provider?.equipShout(shout)
        finishInteraction()
    }

    @objc private func unlock() {
        guard let shout = chosenShout() else { return }
        provider?.unlockNextWord(of: shout)
        finishInteraction()
    }

    @objc private func addSoul() {
        provider?.addDragonSoul()
        finishInteraction()
    }

    @objc private func shoutOne() {
        provider?.shout(words: 1)
        finishInteraction()
    }

    @objc private func shoutTwo() {
        provider?.shout(words: 2)
        finishInteraction()
    }

    @objc private func shoutThree() {
        provider?.shout(words: 3)
        finishInteraction()
    }
}
