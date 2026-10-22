// Fills the panel context from the live game: each seam names the object that
// serves it, so a panel never sees the whole controller graph.

import OpenSkyDialogue
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyQuests
import OpenSkyScripting

extension WorldPanelContext {
    init(game: GameViewController) {
        self.init(game: GamePanelServices(game: game), features: FeaturePanelServices(game: game))
    }
}

extension GamePanelServices {
    init(game: GameViewController) {
        self.init(
            aiNavigation: game,
            aiOverlay: game,
            alchemy: game,
            actorValue: game,
            animation: game.renderControls,
            archery: game,
            assetCache: game,
            camera: game.renderControls,
            casting: game,
            combatLoop: game,
            containerMenu: game,
            crafting: game,
            crimeFaction: game,
            dialogueCamera: game,
            dialogue: game,
            faceMorph: game,
            firstPerson: game,
            frameStats: game.renderControls,
            grass: game.renderControls,
            inventoryEquipment: game,
            inventoryMenu: game,
            item: game,
            journal: game,
            lock: game,
            magicEffect: game,
            meleeCombat: game,
            particle: game.renderControls,
            perception: game,
            physics: game.renderControls,
            playerLocomotion: game,
            precipitation: game.renderControls,
            progression: game,
            ragdoll: game,
            renderDebug: game.renderControls,
            renderPerformance: game.renderControls,
            sceneStats: game.renderControls,
            shadow: game.renderControls,
            surfaceShading: game.renderControls,
            terrainLOD: game.renderControls,
            terrainShading: game.renderControls,
            trap: game,
            trigger: game.renderControls,
            water: game.renderControls,
            weather: game.renderControls,
            worldLoadReport: game,
            worldspace: game
        )
    }
}

extension FeaturePanelServices {
    init(game: GameViewController) {
        self.init(
            actorGraph: game.actorGraphWorld,
            agent: game.agentWorld,
            audio: game.audio,
            cinematicCamera: game.cinematicWorld,
            dialogueBranch: game.dialogue,
            enchanting: game.magic,
            shouts: game.magic,
            explosion: game.effectsWorld,
            hud: game.hud,
            headAssembly: game.headAssembly,
            idle: game.idles,
            imageSpace: game.effectsWorld,
            impact: game.effectsWorld,
            loadingScreen: game.loadingScreens,
            mapMenu: game.mapMenu,
            menuScreens: game.menuScreens,
            message: game.messages,
            objectAnimation: game.objectAnimationWorld,
            perkActivation: game.perkActivation,
            playerSettings: game.menuWorld,
            raceMenu: game.raceMenu,
            runtimeState: game.runtimeState,
            swfLab: game.swfLab,
            scene: game.scenes,
            script: game.scripts,
            sequenceDoor: game.objectAnimationWorld,
            skillsMenu: game.skillsMenu,
            storyManager: game.storyManager,
            survivalMode: game.survivalMode,
            systemMenu: game.systemMenu,
            titleMenu: game.titleMenu,
            uiLab: game.uiLab,
            visualEffect: game.effectsWorld
        )
    }
}
