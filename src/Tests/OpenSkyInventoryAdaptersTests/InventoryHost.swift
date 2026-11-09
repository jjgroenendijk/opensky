// One host for every Inventory adapter, each port a generated fake.

import OpenSkyGameData
import OpenSkyInventoryAdapters
import OpenSkySessionInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface

@MainActor
final class InventoryHost: InventoryWorldHost, InventoryReadoutsHost, InventoryPickpocketHost,
    InventoryPerksHost, InventoryRecipesHost, InventoryVendorHost, InventoryCommandsHost,
    LockWorldHost,
    ActivationRefusalWorldHost
{
    let fakeActorValues = FakeActorValuePort()
    let fakeActorWorld = FakeActorWorldPort()
    let fakeCombat = FakeCombatPort()
    let fakeCrime = FakeCrimePort()
    let fakeFactions = FakeFactionPort()
    let fakeFurniture = FakeFurniturePort()
    let fakeHUD = FakeHUDPort()
    let fakeInventory = FakeInventoryPort()
    let fakeInventoryWorld = FakeInventoryWorldPort()
    let fakeJournal = FakeJournalPort()
    let fakeLockpickingMenu = FakeLockpickingMenuPort()
    let fakeMagic = FakeMagicPort()
    let fakeMagicWorld = FakeMagicWorldPort()
    let fakeMapWorld = FakeMapWorldPort()
    let fakeMenuScreens = FakeMenuScreensPort()
    let fakeMessages = FakeMessageCoordinatorPort()
    let fakePerception = FakePerceptionPort()
    let fakePerkActivation = FakePerkActivationPort()
    let fakePerks = FakePerkPort()
    let fakePlayer = FakePlayerPort()
    let fakeProgression = FakeProgressionPort()
    let fakeRagdollWorld = FakeRagdollWorldPort()
    let fakeRuntimeState = FakeRuntimeStatePort()
    let fakeScenes = FakeScenePort()
    let fakeScripts = FakeScriptPort()
    let fakeStreamer = FakeCellStreamerPort()
    let fakeWorldState = FakeWorldStateStorePort()

    var actorValues: any ActorValuePort {
        fakeActorValues
    }

    var actorWorld: any ActorWorldPort {
        fakeActorWorld
    }

    var combat: any CombatPort {
        fakeCombat
    }

    var crime: any CrimePort {
        fakeCrime
    }

    var factions: any FactionPort {
        fakeFactions
    }

    var furniture: any FurniturePort {
        fakeFurniture
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

    var journal: any JournalPort {
        fakeJournal
    }

    var lockpickingMenu: any LockpickingMenuPort {
        fakeLockpickingMenu
    }

    var magic: any MagicPort {
        fakeMagic
    }

    var magicWorld: any MagicWorldPort {
        fakeMagicWorld
    }

    var mapWorld: any MapWorldPort {
        fakeMapWorld
    }

    var menuScreens: any MenuScreensPort {
        fakeMenuScreens
    }

    var messages: any MessageCoordinatorPort {
        fakeMessages
    }

    var perception: any PerceptionPort {
        fakePerception
    }

    var perkActivation: any PerkActivationPort {
        fakePerkActivation
    }

    var perks: any PerkPort {
        fakePerks
    }

    var player: any PlayerPort {
        fakePlayer
    }

    var progression: any ProgressionPort {
        fakeProgression
    }

    var ragdollWorld: any RagdollWorldPort {
        fakeRagdollWorld
    }

    var runtimeState: any RuntimeStatePort {
        fakeRuntimeState
    }

    var scenes: any ScenePort {
        fakeScenes
    }

    var scripts: any ScriptPort {
        fakeScripts
    }

    var streamer: any CellStreamerPort {
        fakeStreamer
    }

    var worldState: any WorldStateStorePort {
        fakeWorldState
    }

    var gameSession: (any GameSessionPort)?
    var worldRecords: (any WorldRecordsPort)?
}
