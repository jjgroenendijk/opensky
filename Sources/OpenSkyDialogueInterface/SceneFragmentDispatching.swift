import Foundation
import OpenSkyFormatsESM

/// Where a scene's begin, end, and phase fragments go. In a real session the
/// Papyrus world bridge conforms; without one the scene runtime counts them unrun.
@MainActor
public protocol SceneFragmentDispatching: AnyObject {
    /// Instantiates `scriptName` on the scene if needed and enqueues `functionName`.
    /// - Returns: false when the script or its instance is unavailable.
    @discardableResult
    func runSceneFragment(
        of scene: Scene,
        key: ReferenceKey,
        scriptName: String,
        functionName: String
    ) -> Bool
}
