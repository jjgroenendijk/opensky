// Scene condition functions, from xEdit wbDefinitionsTES5.pas: 248 IsScenePlaying,
// 550 IsSceneActionComplete, 590 IsInScene. Scenes test them to wait on each other.
// See docs/engine/condition-functions.md#scenes.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

/// The scenes that play now, with the actions each has completed in this run.
nonisolated public struct SceneConditionResolution: ConditionResolution, Sendable {
    public static let empty = SceneConditionResolution()

    /// Scene FormID -> the `INAM` indices of its completed actions.
    private let playing: [FormID: Set<UInt32>]
    private let actors: Set<ReferenceKey>
    public let isAvailable: Bool

    public init(playing: [FormID: Set<UInt32>], actors: Set<ReferenceKey>) {
        self.playing = playing
        self.actors = actors
        isAvailable = true
    }

    private init() {
        playing = [:]
        actors = []
        isAvailable = false
    }

    public func isPlaying(_ scene: FormID) -> Bool {
        playing[scene] != nil
    }

    /// False for a scene that does not play: a new run starts with no action done.
    public func isActionComplete(_ action: UInt32, in scene: FormID) -> Bool {
        playing[scene]?.contains(action) ?? false
    }

    public func isInScene(_ actor: ReferenceKey) -> Bool {
        actors.contains(actor)
    }
}

nonisolated extension ConditionContext {
    public var scenes: SceneConditionResolution {
        get { self[resolution: SceneConditionResolution.self] }
        set { self[resolution: SceneConditionResolution.self] = newValue }
    }
}

nonisolated extension ConditionFunctions {
    public static func installScene(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 248, name: "IsScenePlaying", parameter1: .formID
        ) { call in
            guard let scene = call.parameter1 else { return .failure(.unresolvedParameter(248)) }
            return Self.scenes(call).map { Self.isTrue($0.isPlaying(scene.asFormID)) }
        })

        // "IsSceneActionComplete SceneID SceneActionID": the ID is the action's `INAM`
        // index (<https://ck.uesp.net/wiki/IsSceneActionComplete>).
        registry.register(ConditionFunction(
            index: 550, name: "IsSceneActionComplete", parameter1: .formID, parameter2: .integer
        ) { call in
            guard let scene = call.parameter1, let action = call.parameter2 else {
                return .failure(.unresolvedParameter(550))
            }
            return Self.scenes(call).map {
                Self.isTrue($0.isActionComplete(action.rawValue, in: scene.asFormID))
            }
        })

        registry.register(ConditionFunction(index: 590, name: "IsInScene") { call in
            call.referenceKey().flatMap { key in
                Self.scenes(call).map { Self.isTrue($0.isInScene(key)) }
            }
        })
    }

    private static func scenes(
        _ call: ConditionCall
    ) -> Result<SceneConditionResolution, ConditionFailure> {
        let scenes = call.context.scenes
        guard scenes.isAvailable else { return .failure(.unavailableData(.scene)) }
        return .success(scenes)
    }
}
