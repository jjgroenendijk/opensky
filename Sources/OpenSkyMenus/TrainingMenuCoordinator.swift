// The training menu `Game.ShowTrainingMenu` and a trainer's dialogue open. The card
// shows the trainer's skill, the price, and the sessions left; the rule that trains
// is the progression coordinator's. See docs/engine/training.md#training-menu.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsSWF

/// What the training menu needs from the app.
public protocol TrainingMenuWorld: MenuScreenWorld {
    /// The card for `trainer`, or nil when the actor does not train.
    func trainingCard(trainer: ReferenceKey) -> TrainingCard?
    /// Buys one session. The refusal text, or nil when the skill went up.
    func train(with trainer: ReferenceKey) -> String?
    /// The trainer the player stands closest to.
    var nearestTrainer: ReferenceKey? { get }
}

public final class TrainingMenuCoordinator: MenuScreen<TrainingMovieEvent> {
    public static let identifier: MenuIdentifier = "Training Menu"
    public static let hint = "E: train   Tab or Esc: leave"

    public private(set) var trainer: ReferenceKey?
    public private(set) var card: TrainingCard?
    private weak var world: (any TrainingMenuWorld)?

    public init(
        menuMode: MenuModeController,
        movies: SWFMovieSource? = nil,
        hud: HUDCoordinator? = nil,
        world: (any TrainingMenuWorld)? = nil
    ) {
        self.world = world
        super.init(
            identifier: Self.identifier, movieReadsKeys: false, menuMode: menuMode,
            layer: (movies, hud), world: world
        )
    }

    @discardableResult
    public func open(trainer: ReferenceKey) -> Bool {
        guard !isOpen else { return false }
        guard let card = world?.trainingCard(trainer: trainer) else {
            lastResult = "Not opened: \(trainer) does not train"
            return false
        }
        self.trainer = trainer
        self.card = card
        lastResult = "Open: \(card.trainerName)"
        present(
            path: TrainingMenuMovieBridge.moviePath,
            prepare: { [weak self] runtime in
                TrainingMenuMovieBridge.prepare(runtime: runtime) { self?.movie.post($0) }
            },
            activate: TrainingMenuMovieBridge.activate(runtime:)
        )
        return true
    }

    /// Opens the menu on the trainer the player stands closest to.
    @discardableResult
    public func openNearest() -> Bool {
        guard let trainer = world?.nearestTrainer else {
            lastResult = "Not opened: no trainer nearby"
            return false
        }
        return open(trainer: trainer)
    }

    override func handleKey(_ event: MenuInputEvent) {
        switch event {
        case .button(.accept): handle(.train)
        case .button(.cancel): handle(.exit)
        default: return
        }
    }

    override func handle(_ event: TrainingMovieEvent) {
        guard let trainer else { return }
        switch event {
        case .train:
            if let refusal = world?.train(with: trainer) {
                lastResult = "Refused: \(refusal)"
            } else {
                card = world?.trainingCard(trainer: trainer)
                lastResult = "Trained to \(card?.skillLevel ?? 0)"
            }
            publish()
        case .exit:
            close()
        }
    }

    override func didClose() {
        trainer = nil
        card = nil
    }

    override func publishMovie(_ runtime: SWFMovieRuntime) {
        guard let card else { return }
        TrainingMenuMovieBridge.publish(card, runtime: runtime)
    }

    override var panel: MenuTextPanel {
        MenuTextPanel(title: "Training", lines: card?.lines ?? [], hint: Self.hint)
    }
}
