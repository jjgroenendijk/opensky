// IDLP, TRNS, SOCL, and AVDM chunks: a playing idle with its target, a running scripted
// move, an actor's social timers and conversation, and imported damage come back as they
// were; an untouched session writes none.

import Foundation
import OpenSkyActorsInterface
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyQuestsInterface
@testable import OpenSkySave
import OpenSkySaveFixtures
import OpenSkyScriptingInterface
import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct RunningStateSaveTests {
    private let dancer = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BBD)
    private let partner = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BBE)
    private let lift = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0004_1000)
    private let tags = ["IDLP", "TRNS", "SOCL", "AVDM"]
    private let damage = ImportedActorDamage(
        amounts: ActorValues(health: 40, magicka: 0, stamina: 12.5)
    )

    private var idle: SavedIdlePlay {
        SavedIdlePlay(
            idle: ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x0001_0C2A), target: partner
        )
    }

    private let move = SavedTranslation(
        position: SIMD3(10, 20, 30), rotation: SIMD3(0, 0, 1.5),
        targetPosition: SIMD3(10, 20, 330), targetRotation: SIMD3(0, 0, 3),
        speed: 50, maxRotationSpeed: 0.5, sentAlmostComplete: false
    )

    private var social: SavedSocialState {
        SavedSocialState(
            socialTimer: 12.5, recentTimer: nil, bodyCheckAge: 4,
            conversation: SavedSocialState.Conversation(
                partner: partner, phase: .approaching, age: 1.25, answerSeconds: 2,
                goal: SIMD3(1, 2, 3)
            )
        )
    }

    private func snapshot() -> WorldStateSnapshot {
        OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(
                    key: dancer, cell: nil, components: [idle.erased, social.erased]
                ),
                OpenSkySaveFixture.entry(
                    key: partner, cell: nil,
                    components: [SavedSocialState(recentTimer: 30).erased, damage.erased]
                ),
                OpenSkySaveFixture.entry(key: lift, cell: nil, components: [move.erased])
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
    }

    @Test func runningStateSurvivesAnEncodeAndDecode() throws {
        let original = snapshot()
        let data = OpenSkySaveFixture.encode(original)
        for tag in tags {
            #expect(data.range(of: Data(tag.utf8)) != nil)
        }
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == original)
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        #expect(store.component(SavedIdlePlay.self, for: dancer) == idle)
        #expect(store.component(SavedSocialState.self, for: dancer) == social)
        #expect(store.component(SavedSocialState.self, for: partner)?.recentTimer == 30)
        #expect(store.component(SavedTranslation.self, for: lift) == move)
        #expect(store.component(ImportedActorDamage.self, for: partner) == damage)
    }

    @Test func noRunningStateWritesNoChunk() {
        let data = OpenSkySaveFixture.encode(
            OpenSkySaveFixture.snapshot([], bystanderCell: OpenSkySaveFixture.riverwood)
        )
        for tag in tags {
            #expect(data.range(of: Data(tag.utf8)) == nil)
        }
    }

    @Test func anUnknownConversationPhaseIsRejected() {
        var payload = Data()
        payload.appendUInt32(1)
        // A generated key (tag 1, sequence 7) and no cell.
        payload.append(1)
        payload.append(contentsOf: [7, 0, 0, 0, 0, 0, 0, 0])
        payload.append(0)
        payload.append(OpenSkySaveFormat.SocialFlag.conversation)
        payload.append(1)
        payload.append(contentsOf: [8, 0, 0, 0, 0, 0, 0, 0])
        payload.append(9)
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveStoryDecoder.decodeSocialStates(payload)
        }
    }
}
