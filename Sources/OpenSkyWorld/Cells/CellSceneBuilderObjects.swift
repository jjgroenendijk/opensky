// Animated objects in a cell build: activators and doors whose mesh names a
// behaviour project. The build decodes the set and poses the object's own
// model through a buffer the main-actor coordinator fills.
// See docs/engine/object-animation.md.

import OpenSkyFormatsCore
import OpenSkyRendering

/// One animated object a cell drew, handed to `ObjectBehaviorCoordinator`.
nonisolated public struct CellAnimatedObject: Sendable {
    public let reference: UInt32
    public let asset: ObjectBehaviorAsset
    public let pose: PlayerPoseBuffer

    public init(reference: UInt32, asset: ObjectBehaviorAsset, pose: PlayerPoseBuffer) {
        self.reference = reference
        self.asset = asset
        self.pose = pose
    }
}

nonisolated extension CellSceneBuilder {
    /// Base types whose meshes vanilla animates with a behaviour graph.
    static let animatedObjectTypes: Set<FourCC> = ["ACTI", "DOOR"]

    /// The behaviour set of a base that can animate and whose mesh names one.
    func objectBehavior(recordType: FourCC, modelPath: String) -> ObjectBehaviorAsset? {
        guard
            Self.animatedObjectTypes.contains(recordType),
            let fileSystem,
            let project = meshes.behaviorProjectPath(forPath: modelPath)
        else { return nil }
        if let known = objectBehaviorAssets[project] {
            return known
        }
        var asset: ObjectBehaviorAsset?
        do {
            asset = try ObjectBehaviorAsset.load(fileSystem: fileSystem, projectPath: project)
        } catch {
            let reason = String(describing: error)
            Self.logger.warning(
                """
                [WARNING] object behaviour \(project, privacy: .public) did not load: \
                \(reason, privacy: .public)
                """
            )
        }
        objectBehaviorAssets[project] = .some(asset)
        return asset
    }

    /// A pose buffer and playback for each animated instance.
    func animatedObjects(
        _ instances: [ResolvedInstance]
    ) -> [(object: CellAnimatedObject, playback: any RenderAnimation)] {
        instances.compactMap { instance in
            guard let asset = instance.animated else { return nil }
            let pose = PlayerPoseBuffer()
            let playback = PlayerAnimationPlayback(
                skeleton: asset.skeleton, pose: pose, models: [instance.model]
            )
            let object = CellAnimatedObject(reference: instance.formID, asset: asset, pose: pose)
            return (object, playback)
        }
    }
}
