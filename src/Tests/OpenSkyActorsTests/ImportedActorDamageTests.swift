// Damage an imported Skyrim save gave an actor: read off the derived maximums, kept
// until the first write, then dropped.

import Foundation
@testable import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyWorldState
import Testing

@MainActor
struct ImportedActorDamageTests {
    private let holder = ActorValueHolder(
        key: .plugin(name: "skyrim.esm", objectID: 0x0001_3BAC),
        subject: .actor(base: FormID(0x0001_3BAC))
    )

    private func runtime() -> (ActorValueRuntime, WorldStateStore) {
        let store = WorldStateStore()
        let baselines = ActorValueBaselineResolver(fallback: ActorValueBaseline(
            maximums: ActorValues(health: 100, magicka: 80, stamina: 60),
            regenPercentPerSecond: .zero
        ))
        return (
            ActorValueRuntime(store: store, baselines: baselines, regeneration: .vanilla),
            store
        )
    }

    @Test func theDamageIsTakenOffTheDerivedMaximums() {
        let (runtime, store) = runtime()
        store.set(
            ImportedActorDamage(amounts: ActorValues(health: 40, magicka: 200, stamina: -5)),
            for: holder.key
        )
        #expect(runtime.current(of: holder) == ActorValues(health: 60, magicka: 0, stamina: 60))
    }

    @Test func theFirstWriteKeepsTheDamageAndDropsTheComponent() {
        let (runtime, store) = runtime()
        store.set(
            ImportedActorDamage(amounts: ActorValues(health: 40, magicka: 0, stamina: 0)),
            for: holder.key
        )
        runtime.damage(.health, by: 10, on: holder)
        #expect(runtime.current(of: holder).health == 50)
        #expect(store.component(ImportedActorDamage.self, for: holder.key) == nil)
    }
}
