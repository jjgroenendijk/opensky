// `CasterRuntime` as the seam scripts cast through.

import OpenSkyMagicInterface

extension CasterRuntime: SpellCasting {
    public var spellbookAccess: any SpellbookAccess {
        spellbook
    }
}
