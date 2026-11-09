// Runs the commands an inventory or lock action returns. The owner and the Papyrus part
// both run commands; each builds this runner over its own host, so neither holds the other.

public import OpenSkyInventoryInterface
public import OpenSkySessionInterface
import OpenSkyWorldInterface

/// What `InventoryCommandRunner` reads from the session.
@MainActor
public protocol InventoryCommandsHost: AnyObject {
    var hud: any HUDPort { get }
    var inventory: any InventoryPort { get }
    var magic: any MagicPort { get }
    var streamer: any CellStreamerPort { get }
}

public struct InventoryCommandRunner {
    public let game: any InventoryCommandsHost

    public init(game: any InventoryCommandsHost) {
        self.game = game
    }

    /// Runs the commands, then hands back the action's answer.
    @discardableResult
    public func run<Value>(_ result: InventoryResult<Value>) -> Value {
        run(result.commands)
        return result.value
    }

    public func run(_ commands: [InventoryCommand]) {
        for command in commands {
            switch command {
            case let .equipmentChanged(holder):
                game.magic.equipmentChanged(on: holder)
            case .refreshInteractionTarget:
                // The streamer's raw target: the HUD's copy is already labelled, and a
                // lock label appends to the name, so labelling it twice repeats the band.
                game.hud.updateTarget(labelled(game.streamer.interactionTarget))
            case let .showNotice(text):
                game.hud.showNotification(text)
            }
        }
    }

    private func labelled(_ target: InteractionTarget?) -> InteractionTarget? {
        target.map {
            InteractionTarget(
                interaction: game.inventory.labelled($0.interaction),
                hitPosition: $0.hitPosition,
                distance: $0.distance
            )
        }
    }
}
