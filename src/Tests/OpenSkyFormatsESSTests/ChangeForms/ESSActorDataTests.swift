// The actor data after the animation part of an actor with no AI process: the life
// state, the killer, and the health modifiers, over bytes built in code.

import Foundation
@testable import OpenSkyFormatsESS
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct ESSActorDataTests {
    private static func change(_ data: Data) throws -> ESSReferenceChange {
        try ESSReferenceChange(ESSChangeForm(
            form: ESSRefID(kind: .default, value: 0x1000), flags: 0, typeIndex: 1,
            version: 74, data: ESSChangeFormData(stored: data)
        ))
    }

    @Test func anActorWithNoProcessReadsItsDeathAndHealth() throws {
        let change = try Self.change(ESSActorDataBytes.actor(lifeState: 2, damage: -40))
        #expect(change.status == .complete)
        let data = try #require(change.actorData)
        #expect(data.isDead)
        #expect(data.killer == ESSRefID(kind: .default, value: 0x14))
        #expect(data.health == ESSActorValueModifiers(permanent: 10, temporary: 0, damage: -40))
        #expect(data.health?.permanent == 10)
        #expect(data.health?.temporary == 0)
        #expect(data.primaryValues.count == 4)
    }

    @Test func movementDataStopsTheRestButKeepsTheValues() throws {
        let change = try Self.change(ESSActorDataBytes.actor(
            lifeState: 7,
            damage: -40,
            movement: 1
        ))
        #expect(change.status == .partial(blockedBy: "actor movement data"))
        #expect(change.actorData?.isDead == false)
        #expect(change.actorData?.health?.damage == -40)
    }

    @Test func anActorWithAProcessIsBlockedByItsProcessData() throws {
        let change = try Self.change(ESSActorDataBytes.actor(processLevel: 0, lifeState: 2))
        #expect(change.status == .partial(blockedBy: "actor process data"))
        #expect(change.actorData == nil)
        #expect(change.processLevel == 0)
    }
}
