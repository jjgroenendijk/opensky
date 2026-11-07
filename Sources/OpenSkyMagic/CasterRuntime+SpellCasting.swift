// `CasterRuntime` as the seam scripts cast through.

public import OpenSkyMagicInterface

extension CasterRuntime: SpellCasting {
    public var spellbookAccess: any SpellbookAccess {
        spellbook
    }
}
