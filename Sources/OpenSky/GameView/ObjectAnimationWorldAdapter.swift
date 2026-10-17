// App side of the object behaviour graphs and the sequence doors: hands the
// coordinators the resident objects, steps them in the world update, and answers
// Papyrus. The rules live in `ObjectBehaviorCoordinator` and `SequenceDoorCoordinator`
// (docs/engine/object-animation.md).

import OpenSkyBehavior
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldState
import simd

/// What `ObjectAnimationWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol ObjectAnimationWorldHost: AnyObject {
    var audioFileSystem: (any GameFileSource)? { get }
    var playerSettings: PlayerSettingsCoordinator { get }
    var playerSettingsStore: PlayerSettingsStore { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var scripts: ScriptCoordinator { get }
    var streamer: CellStreamer? { get }
    var worldState: WorldStateStore { get }
}

final class ObjectAnimationWorldAdapter {
    unowned let game: any ObjectAnimationWorldHost
    private(set) lazy var objects = ObjectBehaviorCoordinator(
        settings: game.playerSettings.store,
        world: self,
        files: { [unowned game] in game.audioFileSystem }
    )
    private(set) lazy var doors: SequenceDoorCoordinator = {
        let doors = SequenceDoorCoordinator(world: self)
        doors.isEnabled = objects.isEnabled
        return doors
    }()

    /// Answers the scheduler did not take yet, because the waiting call was not
    /// queued when its event fired. Retried each frame.
    private var pendingAnswers: [UInt64: Bool] = [:]

    init(game: any ObjectAnimationWorldHost) {
        self.game = game
    }

    /// After the vehicles, so a cart's events and an object's events keep one order.
    func wire(gameSession: GameSession) {
        guard game.audioFileSystem != nil else { return }
        game.scripts.bridge?.objectAnimation = self
        objects.onAnimationEvent = { [weak self] reference, name in
            self?.forward(name, from: reference)
        }
        objects.onWaitFinished = { [weak self] token, fired in
            self?.pendingAnswers[token] = fired
        }
        gameSession.worldTick.register(.objectAnimation) { [weak self] delta in
            self?.advance(delta)
        }
    }

    /// Off holds every object and door in its pose. Persisted.
    var isEnabled: Bool {
        get { objects.isEnabled }
        set {
            objects.isEnabled = newValue
            doors.isEnabled = newValue
            game.playerSettingsStore.set(.objectAnimation, to: newValue ? 1 : 0)
        }
    }

    private func advance(_ delta: Float) {
        objects.sync()
        objects.tick(deltaTime: delta)
        run(doors.sync())
        run(doors.tick(deltaTime: delta))
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
        game.gameSession?.animationEvents?.handle(name, from: key)
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

    func animationVariable(_ name: String, on key: ReferenceKey) -> PapyrusValue? {
        switch reference(of: key).flatMap({ objects.variable(named: name, on: $0) }) {
        case let .bool(flag): .boolean(flag)
        case let .int(integer): .integer(integer)
        case let .real(real): .float(real)
        case .quad, nil: nil
        }
    }

    func setAnimationVariable(
        _ name: String,
        to value: PapyrusValue,
        on key: ReferenceKey
    ) -> Bool {
        guard let reference = reference(of: key) else { return false }
        let graphValue: BehaviorVariableValue? = switch value {
        case let .boolean(flag): .bool(flag)
        case let .integer(integer): .int(integer)
        case let .float(real): .real(real)
        default: nil
        }
        return graphValue.map { objects.setVariable($0, named: name, on: reference) } ?? false
    }

    func openStateCode(of key: ReferenceKey) -> Int32? {
        reference(of: key).flatMap { doors.openStateCode(of: $0) }
    }
}

extension ObjectAnimationWorldAdapter: SequenceDoorWorld {
    func residentSequenceDoors() -> [CellSequenceDoor] {
        game.streamer?.residentSequenceDoors() ?? []
    }

    func sequenceDoorWantsOpen(_ reference: UInt32) -> Bool {
        guard let entry = game.streamer?.referenceEntry(formID: FormID(reference)) else {
            return false
        }
        return game.worldState.resolvedState(for: entry).activation.isOpen
    }

    func run(_ commands: [SequenceDoorCommand]) {
        for command in commands {
            switch command {
            case let .textKey(name, reference):
                guard let key = game.streamer?.referenceEntry(formID: FormID(reference))?.key
                else { continue }
                game.gameSession?.animationEvents?.handle(name, from: key)
            case let .setLeaves(deltas, reference):
                game.streamer?.sequenceDoorLeaves[reference] = deltas
            }
        }
    }

    /// The panel's open and close: the same world-state write as `SetOpen`.
    func setDoorOpen(_ open: Bool, reference: UInt32) -> Bool {
        guard
            let streamer = game.streamer,
            let entry = streamer.referenceEntry(formID: FormID(reference))
        else { return false }
        var state = game.worldState.resolvedState(for: entry).activation
        state.isOpen = open
        game.worldState.set(state, for: entry.key, in: streamer.cellLocation(of: entry.key))
        return true
    }
}

/// The Animated Objects and Animated Doors sections read the adapter.
extension ObjectAnimationWorldAdapter: ObjectAnimationControlProviding,
    SequenceDoorControlProviding
{
    var objectAnimationEnabled: Bool {
        get { isEnabled }
        set { isEnabled = newValue }
    }

    var objectAnimationRows: [ObjectAnimationRow] {
        objects.rows
    }

    func sendObjectAnimationEvent(_ event: String, to reference: UInt32) -> Bool {
        objects.send(event, to: reference)
    }

    var sequenceDoorRows: [SequenceDoorRow] {
        doors.rows
    }

    func setSequenceDoorOpen(_ open: Bool, reference: UInt32) -> Bool {
        setDoorOpen(open, reference: reference)
    }
}
