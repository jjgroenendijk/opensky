// One host for every Magic adapter part, each port a generated fake.

import OpenSkyGameData
import OpenSkyMagicAdapters
import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkySessionTesting

@MainActor
final class MagicHost: MagicWorldHost, MagicArchetypeEffectsHost, MagicSpellDeliveryHost,
    MagicHeldMagicHost, MagicSummonedActorsHost, MagicWorldFactsHost
{
    let fakeActorValues = FakeActorValuePort()
    let fakeActorWorld = FakeActorWorldPort()
    let fakeCombat = FakeCombatPort()
    let fakeControllerRumble = FakeControllerRumblePort()
    let fakeEffectsWorld = FakeEffectsWorldPort()
    let fakeFactions = FakeFactionPort()
    let fakeHazardWorld = FakeHazardWorldPort()
    let fakeHazards = FakeHazardPort()
    let fakeHUD = FakeHUDPort()
    let fakeInventory = FakeInventoryPort()
    let fakeInventoryWorld = FakeInventoryWorldPort()
    let fakeMagic = FakeMagicPort()
    let fakeMapWorld = FakeMapWorldPort()
    let fakeMenuWorld = FakeMenuWorldPort()
    let fakeMessages = FakeMessageCoordinatorPort()
    let fakeMountWorld = FakeMountWorldPort()
    let fakePerks = FakePerkPort()
    let fakeProgression = FakeProgressionPort()
    let fakeScripts = FakeScriptPort()
    let fakeStoryWorld = FakeStoryWorldPort()
    let fakeStreamer = FakeCellStreamerPort()
    let fakeWorldState = FakeWorldStateStorePort()
    var worldRecords: (any WorldRecordsPort)?
    var renderer: (any RendererPort)?

    var actorValues: any ActorValuePort {
        fakeActorValues
    }

    var actorWorld: any ActorWorldPort {
        fakeActorWorld
    }

    var combat: any CombatPort {
        fakeCombat
    }

    var controllerRumble: any ControllerRumblePort {
        fakeControllerRumble
    }

    var effectsWorld: any EffectsWorldPort {
        fakeEffectsWorld
    }

    var factions: any FactionPort {
        fakeFactions
    }

    var hazardWorld: any HazardWorldPort {
        fakeHazardWorld
    }

    var hazards: any HazardPort {
        fakeHazards
    }

    var hud: any HUDPort {
        fakeHUD
    }

    var inventory: any InventoryPort {
        fakeInventory
    }

    var inventoryWorld: any InventoryWorldPort {
        fakeInventoryWorld
    }

    var magic: any MagicPort {
        fakeMagic
    }

    var mapWorld: any MapWorldPort {
        fakeMapWorld
    }

    var menuWorld: any MenuWorldPort {
        fakeMenuWorld
    }

    var messages: any MessageCoordinatorPort {
        fakeMessages
    }

    var mountWorld: any MountWorldPort {
        fakeMountWorld
    }

    var perks: any PerkPort {
        fakePerks
    }

    var progression: any ProgressionPort {
        fakeProgression
    }

    var scripts: any ScriptPort {
        fakeScripts
    }

    var storyWorld: any StoryWorldPort {
        fakeStoryWorld
    }

    var streamer: any CellStreamerPort {
        fakeStreamer
    }

    var worldState: any WorldStateStorePort {
        fakeWorldState
    }

    var gameSession: (any GameSessionPort)? {
        nil
    }
}
