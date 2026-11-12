public import OpenSkyFormatsESM
public import OpenSkyMagicInterface

extension MagicCoordinator.MenuLines {
    public func readBookLine(_ item: FormID) -> String? {
        coordinator.spellTomes.readBook(item)?.text
    }

    public func readyKnownSpellLine(at index: Int, in hand: SpellHand) -> String {
        coordinator.magicMenu.readyKnownSpell(at: index, in: hand).text
    }
}
