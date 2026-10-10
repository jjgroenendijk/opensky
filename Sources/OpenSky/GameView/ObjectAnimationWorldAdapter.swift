// App side of the object behaviour graphs: hands the coordinator the resident
// animated objects, steps it in the world update, and answers Papyrus waits.
// The rules live in `ObjectBehaviorCoordinator` (docs/engine/object-animation.md).

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldState

final class ObjectAnimationWorldAdapter {
    unowned let game: GameViewController
    let objects: ObjectBehaviorCoordinator
    /// Answers the scheduler did not take yet, because the waiting call was not
    /// queued when its event fired. Retried each frame.
    private var pendingAnswers: [UInt64: Bool] = [:]

    init(game: GameViewController) {
        self.game = game
        objects = ObjectBehaviorCoordinator(settings: game.playerSettings.store)
    }

    /// After the vehicles, so a cart's events and an object's events keep one order.
    func wire(renderer: Renderer) {
        guard let files = game.audioFileSystem else { return }
        objects.attach(world: self, files: files)
        game.scripts.bridge?.objectAnimation = self
        objects.onAnimationEvent = { [weak self] reference, name in
            self?.forward(name, from: reference)
        }
        objects.onWaitFinished = { [weak self] token, fired in
            self?.pendingAnswers[token] = fired
        }
        let advanceWorld = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak self] delta in
            advanceWorld?(delta)
            self?.advance(delta)
        }
    }

    private func advance(_ delta: Float) {
        objects.sync()
        objects.tick(deltaTime: delta)
        guard let scheduler = game.scripts.runtime?.scheduler else { return }
        for (token, fired) in pendingAnswers
            where scheduler.answer(token, returning: .boolean(fired))
        {
            pendingAnswers.removeValue(forKey: token)
        }
    }

    private func forward(_ name: String, from reference: UInt32) {
        guard let key = game.streamer?.referenceEntry(formID: FormID(reference))?.key else {
            return
        }
        game.scripts.runtime?.queueAnimationEvent(sender: key, name: name)
    }

    private func reference(of key: ReferenceKey) -> UInt32? {
        game.streamer?.referenceEntry(key: key)?.formID.rawValue
    }
}

extension ObjectAnimationWorldAdapter: ObjectBehaviorWorld {
    func residentAnimatedObjects() -> [CellAnimatedObject] {
        game.streamer?.residentAnimatedObjects() ?? []
    }
}

extension ObjectAnimationWorldAdapter: PapyrusObjectAnimationBridge {
    func playAnimation(_ event: String, on key: ReferenceKey) -> Bool {
        guard let reference = reference(of: key) else { return false }
        return objects.send(event, to: reference)
    }

    func awaitAnimationEvent(_ event: String, on key: ReferenceKey) -> UInt64? {
        reference(of: key).flatMap { objects.awaitEvent(event, on: $0) }
    }
}
