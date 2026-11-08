// Clip annotations that ask the engine, not the graph, to act: sounds, camera shake,
// head tracking, and script events. The player graph, the NPC idles, and the object graphs all send
// their
// fired names here. See docs/engine/animation-events.md.

import Foundation
public import OpenSkyBehavior
public import OpenSkyFormatsESM
import simd

/// What the coordinator needs from the session.
public protocol AnimationEventWorld: AnyObject {
    /// Where `source` stands. Nil when it is not loaded.
    func animationEventPosition(of source: ReferenceKey) -> SIMD3<Float>?
    /// Where the posed bone or node `node` of `source` is now. Nil when it has no such bone.
    func animationEventPosition(of source: ReferenceKey, node: String) -> SIMD3<Float>?
    /// False when no `SNDR` has the editor ID.
    func playAnimationSound(editorID: String, source: ReferenceKey, at position: SIMD3<Float>)
        -> Bool
    func stopAnimationSound(editorID: String, source: ReferenceKey)
    /// Lets the loop finish its current pass, then end.
    func releaseAnimationSound(editorID: String, source: ReferenceKey)
    /// A far source shakes the camera less.
    func shakeCamera(from position: SIMD3<Float>, strength: Float)
    func setHeadTracking(_ enabled: Bool, for actor: ReferenceKey)
    /// Sends `name` to the `OnAnimationEvent` of the scripts that registered on `source`.
    func sendScriptAnimationEvent(_ name: String, from source: ReferenceKey)
    /// Sends `name` to the behaviour graphs of the effects on `source`.
    func sendEffectGraphEvent(_ name: String, from source: ReferenceKey)
}

extension AnimationEventWorld {
    public func animationEventPosition(of _: ReferenceKey, node _: String) -> SIMD3<Float>? {
        nil
    }

    public func releaseAnimationSound(editorID: String, source: ReferenceKey) {
        stopAnimationSound(editorID: editorID, source: source)
    }
}

public final class AnimationEventCoordinator {
    let world: any AnimationEventWorld
    /// Off drops every action, so the graph's own events still run.
    public var isEnabled = true
    /// Actions run, by kind, for the readout.
    public private(set) var counts: [String: Int] = [:]
    /// The last annotation acted on, and its source, for the readout.
    public private(set) var lastEvent: String?
    /// Sound editor IDs a clip named that no `SNDR` has.
    public private(set) var missingSounds: Set<String> = []

    public init(world: any AnimationEventWorld) {
        self.world = world
    }

    /// Runs the annotation's action. Returns it, or nil when `name` is not one. Every
    /// event also reaches the source's effect graphs, unless one of them raised it.
    @discardableResult
    public func handle(
        _ name: String, from source: ReferenceKey, reachesEffectGraphs: Bool = true
    ) -> AnimationEventAction? {
        if reachesEffectGraphs {
            world.sendEffectGraphEvent(name, from: source)
        }
        guard isEnabled, let action = AnimationEventAction.parse(name) else {
            return nil
        }
        switch action {
        case let .playSound(editorID, node):
            // `SoundPlayAt` names a bone; a source without it plays at its feet.
            let atNode = node.flatMap { world.animationEventPosition(of: source, node: $0) }
            guard let position = atNode ?? world.animationEventPosition(of: source)
            else { return nil }
            if !world.playAnimationSound(editorID: editorID, source: source, at: position) {
                missingSounds.insert(editorID)
            }
        case let .stopSound(editorID):
            world.stopAnimationSound(editorID: editorID, source: source)
        case let .releaseSound(editorID):
            world.releaseAnimationSound(editorID: editorID, source: source)
        case let .cameraShake(strength):
            guard let position = world.animationEventPosition(of: source) else { return nil }
            world.shakeCamera(from: position, strength: strength)
        case let .headTracking(enabled):
            world.setHeadTracking(enabled, for: source)
        case let .raiseEvent(event):
            world.sendScriptAnimationEvent(event, from: source)
        }
        counts[Self.kind(action), default: 0] += 1
        lastEvent = "\(name) from \(source)"
        return action
    }

    /// One readout line per action kind, in name order.
    public var readout: [String] {
        counts.keys.sorted().map { "\($0): \(counts[$0] ?? 0)" }
    }

    static func kind(_ action: AnimationEventAction) -> String {
        switch action {
        case .playSound: "sound play"
        case .stopSound: "sound stop"
        case .releaseSound: "sound release"
        case .cameraShake: "camera shake"
        case .headTracking: "head tracking"
        case .raiseEvent: "script event"
        }
    }
}
