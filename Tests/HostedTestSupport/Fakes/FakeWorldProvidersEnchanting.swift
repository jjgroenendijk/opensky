// The enchanting seam for the fake world: nothing to enchant, so every action is
// refused the way a session with no inventory refuses it.

@testable import OpenSky
import OpenSkyFormatsESM
import OpenSkyMagic
import OpenSkyMagicInterface

extension FakeWorldProviders {
    var enchantingSnapshot: EnchantingControlSnapshot {
        .unavailable
    }

    func disenchant(_: FormID) -> EnchantingOutcome {
        .unavailable
    }

    func enchant(
        _: FormID, with _: [ReferenceKey], gem _: SoulGemCandidate, name _: String?
    ) -> EnchantingOutcome {
        .unavailable
    }

    func enchantingPreview(
        _: FormID, with _: [ReferenceKey], gem _: SoulGemCandidate
    ) -> Result<MadeEnchantment, EnchantingRefusal> {
        .failure(.notCarried)
    }
}
