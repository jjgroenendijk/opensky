import Foundation

// One host for every Menu adapter part, each port a generated fake.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenuAdapters
import OpenSkyMenusInterface
import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface

@MainActor
final class MenuHost: LoadingScreenPresentationHost, LoadingScreenWorldHost, MapQuestsHost,
    MapRecordsHost, MapTravelHost, MapWorldHost, MenuScreensCraftingDeskHost,
    MenuScreensGiftListsHost, MenuScreensGuidesHost, MenuScreensWorldHost, MenuWorldHost,
    MenuWorldNewGameHost, MenuWorldScriptMenusHost, MenuWorldSettingsApplyHost,
    MenuWorldSkillsRaceHost, MenuWorldTeleportsHost, MessageCameraEffectsHost, MessageWorldHost,
    MovieWorldHost, PerkActivationWorldHost
{
    let fakeActorValues = FakeActorValuePort()
    let fakeActorWorld = FakeActorWorldPort()
    let fakeAgentWorld = FakeAgentWorldPort()
    let fakeAudio = FakeAudioPort()
    let fakeCameraInput = FakeCameraInputStatePort()
    let fakeCinematicCamera = FakeCinematicCameraPort()
    let fakeCinematicWorld = FakeCinematicCameraWorldPort()
    let fakeCombat = FakeCombatPort()
    let fakeContainerMenu = FakeContainerMenuPort()
    let fakeCrime = FakeCrimePort()
    let fakeEffectsWorld = FakeEffectsWorldPort()
    let fakeHud = FakeHUDPort()
    let fakeInventory = FakeInventoryPort()
    let fakeInventoryWorld = FakeInventoryWorldPort()
    let fakeJournal = FakeJournalPort()
    let fakeJournalMenu = FakeJournalMenuPort()
    let fakeLoadingScreens = FakeLoadingScreenPort()
    let fakeLoadingWorld = FakeLoadingScreenWorldPort()
    let fakeMagic = FakeMagicPort()
    let fakeMagicWorld = FakeMagicWorldPort()
    let fakeMapMenu = FakeMapMenuPort()
    let fakeMapWorld = FakeMapWorldPort()
    let fakeMenuMode = FakeMenuModePort()
    let fakeMenuScreens = FakeMenuScreensPort()
    let fakeMessageWorld = FakeMessageWorldPort()
    let fakeMessages = FakeMessageCoordinatorPort()
    let fakeMovies = FakeMoviePlayerPort()
    let fakePerkActivation = FakePerkActivationPort()
    let fakePerks = FakePerkPort()
    let fakePlayer = FakePlayerPort()
    let fakePlayerSettings = FakePlayerSettingsPort()
    let fakeProgression = FakeProgressionPort()
    let fakeProgressionWorld = FakeProgressionWorldPort()
    let fakeRaceMenu = FakeRaceMenuPort()
    let fakeRuntimeState = FakeRuntimeStatePort()
    let fakeRuntimeStateWorld = FakeRuntimeStateWorldPort()
    let fakeSaveGames = FakeSaveGameWorldPort()
    let fakeScripts = FakeScriptPort()
    let fakeSimulationClock = FakeSteppedWallClockPort()
    let fakeStoryWorld = FakeStoryWorldPort()
    let fakeStreamer = FakeCellStreamerPort()
    let fakeSubtitles = FakeSubtitlePort()
    let fakeSwfMovies = FakeSWFMovieSourcePort()
    let fakeWorldState = FakeWorldStateStorePort()
    var audioFileSystem: (any GameFileSource)?
    var gameSession: (any GameSessionPort)?
    var localizedStringsLoader: (() -> LocalizedStrings)?
    var playerBeastForm = PlayerBeastForm.none
    var renderer: (any RendererPort)?
    var menuRecords: (any MenuRecordsPort)?

    var actorValues: any ActorValuePort {
        fakeActorValues
    }

    var actorWorld: any ActorWorldPort {
        fakeActorWorld
    }

    var agentWorld: any AgentWorldPort {
        fakeAgentWorld
    }

    var audio: any AudioPort {
        fakeAudio
    }

    var cameraInput: any CameraInputStatePort {
        fakeCameraInput
    }

    var cinematicCamera: any CinematicCameraPort {
        fakeCinematicCamera
    }

    var cinematicWorld: any CinematicCameraWorldPort {
        fakeCinematicWorld
    }

    var combat: any CombatPort {
        fakeCombat
    }

    var containerMenu: any ContainerMenuPort {
        fakeContainerMenu
    }

    var crime: any CrimePort {
        fakeCrime
    }

    var effectsWorld: any EffectsWorldPort {
        fakeEffectsWorld
    }

    var hud: any HUDPort {
        fakeHud
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

    var journalMenu: any JournalMenuPort {
        fakeJournalMenu
    }

    var loadingScreens: any LoadingScreenPort {
        fakeLoadingScreens
    }

    var loadingWorld: any LoadingScreenWorldPort {
        fakeLoadingWorld
    }

    var magic: any MagicPort {
        fakeMagic
    }

    var magicWorld: any MagicWorldPort {
        fakeMagicWorld
    }

    var mapMenu: any MapMenuPort {
        fakeMapMenu
    }

    var mapWorld: any MapWorldPort {
        fakeMapWorld
    }

    var menuMode: any MenuModePort {
        fakeMenuMode
    }

    var menuScreens: any MenuScreensPort {
        fakeMenuScreens
    }

    var messageWorld: any MessageWorldPort {
        fakeMessageWorld
    }

    var messages: any MessageCoordinatorPort {
        fakeMessages
    }

    var movies: any MoviePlayerPort {
        fakeMovies
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

    var playerSettings: any PlayerSettingsPort {
        fakePlayerSettings
    }

    var progression: any ProgressionPort {
        fakeProgression
    }

    var progressionWorld: any ProgressionWorldPort {
        fakeProgressionWorld
    }

    var raceMenu: any RaceMenuPort {
        fakeRaceMenu
    }

    var runtimeState: any RuntimeStatePort {
        fakeRuntimeState
    }

    var runtimeStateWorld: any RuntimeStateWorldPort {
        fakeRuntimeStateWorld
    }

    var saveGames: any SaveGameWorldPort {
        fakeSaveGames
    }

    var scripts: any ScriptPort {
        fakeScripts
    }

    var simulationClock: any SteppedWallClockPort {
        fakeSimulationClock
    }

    var storyWorld: any StoryWorldPort {
        fakeStoryWorld
    }

    var streamer: any CellStreamerPort {
        fakeStreamer
    }

    var subtitles: any SubtitlePort {
        fakeSubtitles
    }

    var swfMovies: any SWFMovieSourcePort {
        fakeSwfMovies
    }

    var worldState: any WorldStateStorePort {
        fakeWorldState
    }

    private(set) var menuInputs: [MenuInputEvent] = []

    func handleMenuInput(_ event: MenuInputEvent) {
        menuInputs.append(event)
    }
}
