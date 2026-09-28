// Which hands an EQUP slot takes. The walk is `EquipSlotHands`, which lives with
// the equipment runtime, so the store in GameData stays free of it.

import OpenSkyFormats
import OpenSkyGameData

nonisolated extension EquipSlotStore {
    /// The hands the slot named by `id` occupies, or nil when the link names
    /// no EQUP in the load order. `[]` is a resolved slot that takes no hand —
    /// Voice and Potion — and is not a miss.
    public func hands(of id: FormID?, fromPlugin pluginName: String) -> HandSlots? {
        handChoice(of: id, fromPlugin: pluginName)?.hands
    }

    /// The same answer keeping the all-parents/choose-one distinction, which is
    /// what equipping a spell to a named hand needs (issue #470).
    public func handChoice(
        of id: FormID?,
        fromPlugin pluginName: String
    ) -> EquipSlotHandChoice? {
        guard let id, !id.isNull, let resolved = resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return EquipSlotHands.choice(of: resolved.slot) { parent in
            resolve(parent, fromPlugin: resolved.sourcePlugin)?.slot
        }
    }
}
