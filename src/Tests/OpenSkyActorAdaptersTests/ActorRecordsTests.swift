// The actor adapters read races, packages, and templates through the records port, and
// answer nothing when a store is not loaded.

import OpenSkyActorAdapters
import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyPlayer
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import OpenSkyWorldTesting
import Testing

@MainActor
struct ActorRecordsTests {
    private let host = ActorHost()

    init() throws {
        host.actorRecords = FakeActorRecords()
        let entry = try PackageRuntimeFixture.residentActor(0x20, base: 0x30)
        host.fakeStreamer.residents.residentActorEntryResult = entry
        host.fakeActorWorld.combatActorsResult = [CombatActorObservation(
            key: entry.key,
            feet: .one
        )]
    }

    @Test func withoutTemplatesAnActorHasNoGraphNameOrSounds() {
        let events = ActorGraphWorldAdapter(game: host, stage: nil).graphEvents
        let actors = ActorWorldAdapter(game: host, stage: nil)
        let key = PackageRuntimeFixture.key(0x20)
        #expect(events.graphBase(of: key, base: FormID(0x30)) == nil)
        #expect(events.actorSoundSources().isEmpty)
        #expect(actors.displayName(of: key, base: FormID(0x30)) == nil)
    }

    @Test func withoutRacesNoBeastFormOrMountOffset() {
        let beasts = BeastFormWorldAdapter(game: host, stage: nil)
        let mounts = MountWorldAdapter(game: host, stage: nil)
        #expect(!beasts.force(.werewolf))
        #expect(
            mounts.dismountOffset(of: PackageRuntimeFixture.key(0x20))
                == RaceProperties.MountOffsets.fallbackDismount
        )
    }

    @Test func withoutAPackageStoreAPackageHasNoIdles() {
        let idles = IdleWorldAdapter(game: host, stage: nil).placement
        #expect(idles.packageIdleList(FormID(0x40)) == nil)
    }

    @Test func aTakenMountDrivesWithTheRecordsConfiguration() {
        let mounts = MountWorldAdapter(game: host, stage: nil)
        let key = PackageRuntimeFixture.key(0x20)
        host.fakeStreamer.actors.takeRiddenActorResult = NPCRiddenHold(
            actor: key, formID: FormID(0x20),
            placement: PlacedReference.Placement(position: .zero, rotation: .zero),
            scale: 1, feetPosition: .one, yaw: 0.5
        )
        let start = mounts.takeMount(key, kind: .horse, saddleBone: "SaddleBone")
        #expect(start?.feet == .one)
        #expect(start?.yaw == 0.5)
    }

    @Test func thePlayerRigAndGraphReadTheRecords() {
        let player = PlayerWorldAdapter(game: host, stage: nil)
        host.cellRunner = FakeSerialCellBuildRunnerPort()
        host.fakeWorldState.componentResult = PlayerIdentityState(
            race: FormID(0x13746), isFemale: true, name: "Lydia"
        )
        #expect(player.rigSource() != nil)
        #expect(player.playerBehaviorProject == nil)
    }
}
