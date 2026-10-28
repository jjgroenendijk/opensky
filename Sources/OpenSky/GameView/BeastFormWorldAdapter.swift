// App side of the beast forms: which form the player has taken, the activation gate a
// beast meets, and the debug switch. The change scripts do the rest through their
// natives. The rules live in `PlayerBeastForm` (docs/engine/beast-forms.md).

import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `BeastFormWorldAdapter` reads from the session.
@MainActor
protocol BeastFormWorldHost: AnyObject {
    var gameSession: GameSession? { get }
    var menuWorld: MenuWorldAdapter { get }
    var scripts: ScriptCoordinator { get }
    var streamer: CellStreamer? { get }
    var worldData: WorldDataStores? { get }
    var worldState: WorldStateStore { get }
}

final class BeastFormWorldAdapter {
    unowned let game: any BeastFormWorldHost

    init(game: any BeastFormWorldHost) {
        self.game = game
    }

    var form: PlayerBeastForm {
        let flag = game.scripts.bridge?.scriptedState(of: .player)
            .flag(ScriptedStateName.beastForm) == true
        return PlayerBeastForm.resolve(beastFormFlag: flag, raceEditorID: playerRace?.editorID)
    }

    /// After the mount gate, so a rider hears the door refusal first.
    func wire() {
        guard let streamer = game.streamer else { return }
        streamer.activationGate.register(.beastForm) { [weak self] target in
            guard let self else { return nil }
            let canTake = playerRace?.flags.contains(.canPickUpItems) ?? true
            return form.refusal(for: target.interaction.action, raceCanPickUpItems: canTake)
        }
    }

    /// The debug switch: the form's race and `SetBeastForm`, without the change scripts.
    /// `.none` restores the race the player had before. False when the race is not loaded.
    func force(_ wanted: PlayerBeastForm) -> Bool {
        let race: FormID?
        switch wanted {
        case .none: race = nil
        case .werewolf: race = raceFormID(editorID: PlayerBeastForm.werewolfRace)
        case .vampireLord: race = raceFormID(editorID: PlayerBeastForm.vampireLordRace)
        case .otherBeast: return false
        }
        guard wanted == .none || race != nil else { return false }
        game.scripts.bridge?.updateScriptedState(of: .player) {
            $0.setFlag(ScriptedStateName.beastForm, wanted.isBeast ? true : nil)
        }
        // A beast form has no first-person rig, as `Game.ForceThirdPerson` in the scripts says.
        if wanted.isBeast, let session = game.gameSession, session.movementMode.isPlayerControlled {
            session.setMovementMode(.thirdPerson)
        }
        return game.menuWorld.setRace(of: .player, to: race)
    }

    private var races: [UInt32: Race] {
        game.worldData?.actorValueBaselines?.resolver?.races ?? [:]
    }

    private var playerRace: Race? {
        game.worldState.component(PlayerIdentityState.self, for: .player)
            .flatMap { races[$0.race.rawValue] }
    }

    private func raceFormID(editorID: String) -> FormID? {
        races.first { $0.value.editorID == editorID }.map { FormID($0.key) }
    }
}

extension GameSessionScope {
    var playerBeastForm: PlayerBeastForm {
        beastForms.form
    }
}
