// The armatures an actor's footstep set is picked from: worn feet pieces first,
// then every other part, so a creature skin with no feet slot still counts.

import OpenSkyActorPresentation
import OpenSkyFormatsESM
import Testing

struct WornArmorAddonFootstepTests {
    @Test func feetSlotPartsComeFirstAndTheRestFollowInOrder() {
        let parts = [
            WornArmorAddon(armature: FormID(1), modelPath: "body.nif", slots: .body),
            WornArmorAddon(armature: FormID(2), modelPath: "boots.nif", slots: .feet),
            WornArmorAddon(armature: FormID(3), modelPath: "mane.nif")
        ]
        #expect(parts.footstepArmatures == [FormID(2), FormID(1), FormID(3)])
    }
}
