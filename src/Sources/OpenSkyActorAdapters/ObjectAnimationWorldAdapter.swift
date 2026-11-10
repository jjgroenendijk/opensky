// App side of the object behaviour graphs, the sequence doors, and the node controllers:
// hands the coordinators the resident objects, steps them in the world update, and
// answers Papyrus. The rules live in `ObjectBehaviorCoordinator`, `SequenceDoorCoordinator`,
// and `NodeControllerCoordinator` (docs/engine/object-animation.md).

import OpenSkyActorPresentation
import OpenSkyBehavior
public import OpenSkyFormatsESM
public import OpenSkyFormatsMesh
public import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyObjectAnimation
import OpenSkyRendering
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `ObjectAnimationWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol ObjectAnimationWorldHost: AnyObject, SendableMetatype {
    var actorWorld: any ActorWorldPort { get }
    var actorGraphWorld: any ActorGraphWorldPort { get }
    var containerMenu: any ContainerMenuPort { get }
    var effectGraphs: any EffectGraphPort { get }
    var objectBehaviors: any ObjectBehaviorPort { get }
    var sequenceDoors: any SequenceDoorPort { get }
    var nodeControllers: any NodeControllerPort { get }
    var audioFileSystem: (any GameFileSource)? { get }
    var gameSession: (any GameSessionPort)? { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var worldState: any WorldStateStorePort { get }
}

public final class ObjectAnimationWorldAdapter {
    public let game: any ObjectAnimationWorldHost
    public var objects: any ObjectBehaviorPort {
        game.objectBehaviors
    }

    public var doors: any SequenceDoorPort {
        game.sequenceDoors
    }

    /// Answers the scheduler did not take yet, because the waiting call was not
    /// queued when its event fired. Retried each frame.
    private var pendingAnswers: [UInt64: Bool] = [:]
    /// Which scripted traps touch which actors.
    var trapContact = TrapContactTracker()

    /// The streamer's animated parts. The composition root sets these, so the host stays port-only.
    public var animatedObjects: () -> [CellAnimatedObject] = { [] }
    public var sequenceDoors: () -> [CellSequenceDoor] = { [] }
    public var nodeAnimations: () -> [CellNodeAnimation] = { [] }

    public init(game: any ObjectAnimationWorldHost) {
        self.game = game
    }

    func advance(_ delta: Float) {
        objects.sync()
        objects.tick(deltaTime: delta)
        game.streamer.poseMovingCollision { [objects] in objects.boneMatrices(of: $0) }
        run(doors.sync())
        run(doors.tick(deltaTime: delta))
        game.nodeControllers.sync()
        game.nodeControllers.tick(deltaTime: delta)
        advanceTrapContact(delta)
        guard let scheduler = game.scripts.runtime?.scheduler else { return }
        for (token, fired) in pendingAnswers
            where scheduler.answer(token, returning: .boolean(fired))
        {
            pendingAnswers.removeValue(forKey: token)
        }
    }

    /// An object's or an actor's graph wait, answered on the next frame.
    public func answerWait(token: UInt64, fired: Bool) {
        pendingAnswers[token] = fired
    }

    private func reference(of key: ReferenceKey) -> UInt32? {
        game.streamer.referenceEntry(key: key)?.formID.rawValue
    }
}

extension ObjectAnimationWorldAdapter: ObjectBehaviorWorld {
    public func residentAnimatedObjects() -> [CellAnimatedObject] {
        animatedObjects()
    }

    public func objectGraphFired(_ name: String, from reference: UInt32) {
        guard let key = game.streamer.referenceEntry(formID: FormID(reference))?.key else {
            return
        }
        game.gameSession?.animationEvents?.handle(name, from: key)
        game.scripts.runtime?.queueAnimationEvent(sender: key, name: name)
    }

    public func animationWaitFinished(token: UInt64, fired: Bool) {
        answerWait(token: token, fired: fired)
    }
}

/// An object's own graph answers first; an actor's behaviour graph answers otherwise.
extension ObjectAnimationWorldAdapter: PapyrusObjectAnimationBridge {
    private var actorGraphs: any ActorGraphPort {
        game.actorGraphWorld.graphs
    }

    public func playAnimation(_ event: String, on key: ReferenceKey) -> Bool {
        if let reference = reference(of: key), objects.send(event, to: reference) {
            return true
        }
        return actorGraphs.raise(event, on: key)
    }

    public func awaitAnimationEvent(_ event: String, on key: ReferenceKey) -> UInt64? {
        reference(of: key).flatMap { objects.awaitEvent(event, on: $0) }
            ?? actorGraphs.awaitEvent(event, on: key)
    }

    public func animationVariable(_ name: String, on key: ReferenceKey) -> PapyrusValue? {
        let objectValue: BehaviorVariableValue? = reference(of: key).flatMap {
            objects.variable(named: name, on: $0)
        }
        let value = objectValue ?? actorGraphs.variable(named: name, on: key)
        return switch value {
        case let .bool(flag): .boolean(flag)
        case let .int(integer): .integer(integer)
        case let .real(real): .float(real)
        case .quad, nil: nil
        }
    }

    public func setAnimationVariable(
        _ name: String,
        to value: PapyrusValue,
        on key: ReferenceKey
    ) -> Bool {
        let graphValue: BehaviorVariableValue? = switch value {
        case let .boolean(flag): .bool(flag)
        case let .integer(integer): .int(integer)
        case let .float(real): .real(real)
        default: nil
        }
        guard let graphValue else { return false }
        if
            let reference = reference(of: key),
            objects.setVariable(graphValue, named: name, on: reference)
        {
            return true
        }
        return actorGraphs.setVariable(graphValue, named: name, on: key)
    }

    public func playSubGraphAnimation(_ event: String, on actor: ReferenceKey) -> Bool {
        game.effectGraphs.deliver(event, from: actor)
    }

    public func setSubGraphFloatVariable(_ name: String, to value: Float, on actor: ReferenceKey)
        -> Bool
    {
        game.effectGraphs.setSubGraphVariable(value, named: name, on: actor)
    }

    /// A moving door's phase, or 0 for a resident reference that cannot open: one whose
    /// use action is neither open nor search (CK wiki "GetOpenState - ObjectReference").
    public func openStateCode(of key: ReferenceKey) -> Int32? {
        guard let reference = reference(of: key) else { return nil }
        if let code = doors.openStateCode(of: reference) {
            return code
        }
        guard let interaction = game.streamer.residentInteraction(reference: FormID(reference))
        else { return 0 }
        return [.open, .search].contains(interaction.action) ? nil : 0
    }
}

extension ObjectAnimationWorldAdapter: SequenceDoorWorld {
    public func residentSequenceDoors() -> [CellSequenceDoor] {
        sequenceDoors()
    }

    public func sequenceDoorWantsOpen(_ door: CellSequenceDoor) -> Bool {
        guard let entry = game.streamer.referenceEntry(formID: FormID(door.reference)) else {
            return false
        }
        switch door.kind {
        case .door:
            return game.worldState.resolvedState(for: entry).activation.isOpen
        case .loadDoor:
            return false
        case .containerLid:
            return game.containerMenu.isOpen && game.containerMenu.container?.key == entry.key
        }
    }

    func run(_ commands: [SequenceDoorCommand]) {
        for command in commands {
            switch command {
            case let .textKey(name, reference):
                guard let key = game.streamer.referenceEntry(formID: FormID(reference))?.key
                else { continue }
                game.gameSession?.animationEvents?.handle(name, from: key)
                game.scripts.runtime?.queueAnimationEvent(sender: key, name: name)
            case let .setLeaves(deltas, reference):
                game.streamer.sequenceDoorLeaves[reference] = deltas
            }
        }
    }
}

extension ObjectAnimationWorldAdapter: NodeControllerWorld {
    public func residentNodeAnimations() -> [CellNodeAnimation] {
        nodeAnimations()
    }

    public var nodeControllerViewer: NIFBillboard.Viewer? {
        game.gameSession.map { NIFBillboard.Viewer(camera: $0.freeFlyCamera) }
    }
}

extension ObjectAnimationWorldAdapter: ObjectAnimationWorldPort {}
