public import OpenSkyFormatsESM
public import OpenSkyMagicInterface

extension MagicCoordinator {
    public func readBookLine(_ item: FormID) -> String? {
        readBook(item)?.text
    }

    public func readyKnownSpellLine(at index: Int, in hand: SpellHand) -> String {
        readyKnownSpell(at: index, in: hand).text
    }
}
