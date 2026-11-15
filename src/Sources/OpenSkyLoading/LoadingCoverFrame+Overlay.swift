// The screen-space half of a loading screen: the line of text at the bottom,
// and during the fade a dark panel that thins out over the world.
// See docs/engine/loading-screens.md.

public import OpenSkyRenderCore
import simd

nonisolated extension LoadingCoverFrame {
    /// Larger than any drawable, so the panel covers the whole view.
    static let coverSize = UISize(width: 16384, height: 16384)
    static let textWidth: Float = 900

    var overlay: UIScene {
        overlay(showsText: true)
    }

    /// `showsText` is false while the game's loading movie draws the tip.
    public func overlay(showsText: Bool) -> UIScene {
        var nodes: [UINode] = []
        if !drawsObject {
            nodes.append(UINode(
                anchor: .center,
                content: .marker(size: Self.coverSize, color: SIMD4(0, 0, 0, opacity))
            ))
        }
        if showsText, let text, !text.isEmpty {
            nodes.append(UINode(
                anchor: .bottom,
                offset: UIPoint(x: 0, y: -72),
                content: .label(UILabel(
                    text: text,
                    font: UIFont(pointSize: 15),
                    color: SIMD4(0.92, 0.92, 0.88, opacity),
                    maxWidth: Self.textWidth
                ))
            ))
        }
        return UIScene(nodes: nodes)
    }
}

nonisolated extension LoadingCoverFrame {
    /// The model's pose in the scene, with the model's inventory marker turn when it has one.
    public func modelPose(markerRotation: SIMD3<Float>?) -> LoadingScreenScene.ModelPose {
        LoadingScreenScene.ModelPose(
            rotationDegrees: rotationDegrees, scale: scale, translation: translation,
            turnRadians: turnRadians, markerRotation: markerRotation
        )
    }
}
