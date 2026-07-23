// Localized-strings preview content for World > UI Lab (M8.1.4). Invented
// $KEY fixture strings merged through the real TranslationFile ->
// LocalizedLabels path, and a UIScene that renders them via
// LocalizedLabels.label(for:): a wrapped long string, an unwrapped long line
// that clips at the frame edge, and a deliberately unknown key shown verbatim
// (the vanilla-observable fallback). Every string here is invented in code —
// never game data (AGENTS.md legal boundary). The vanilla install ships zero
// translation .txt files, so a synthetic sample is the only way the preview
// can show resolved text.

import simd

extension LocalizedLabels {
    /// Synthetic sample provider for the UI Lab preview. Goes through the real
    /// merge path so the preview exercises the same provider the SWF menus
    /// (issue #99) will consume.
    static let uiLabSample = LocalizedLabels(
        language: "english",
        files: [TranslationFile(entries: [
            "$OPENSKY_UILAB_TITLE": "Localized strings",
            "$OPENSKY_UILAB_BODY": "UI tokens resolved through the translation-file provider.",
            "$OPENSKY_UILAB_LONG": "This deliberately long localized paragraph must wrap "
                + "across several lines so the preview shows how translated menu text "
                + "reflows at every scale preset, including verbose languages whose "
                + "strings run far longer than the English source text.",
            "$OPENSKY_UILAB_CLIP": "This unwrapped localized line intentionally keeps "
                + "running past the right edge of the frame so edge clipping stays "
                + "visible at every scale preset."
        ])]
    )
}

extension UIScene {
    /// The deliberately-unresolved token the preview renders verbatim.
    static let localizedSampleMissingToken = "$OPENSKY_UILAB_MISSING"

    /// Wrap width (points) of the long-paragraph case.
    static let localizedSampleWrapWidth: Float = 312

    /// The preview scene over the built-in synthetic sample labels.
    static let localizedSample = UIScene.localizedSample(labels: .uiLabSample)

    /// Localized preview scene: every visible string passes through
    /// `LocalizedLabels.label(for:)`. Parametrized over the provider so tests
    /// can substitute their own fixtures.
    static func localizedSample(labels: LocalizedLabels) -> UIScene {
        UIScene(nodes: [
            UINode(
                anchor: .topLeft,
                offset: UIPoint(x: 24, y: 24),
                content: .panel(
                    size: UISize(width: 360, height: 240),
                    color: SIMD4(0.06, 0.07, 0.10, 0.85),
                    border: UIBorder(width: 2, color: SIMD4(0.55, 0.62, 0.75, 1))
                )
            ),
            sampleLabel(
                labels.label(for: "$OPENSKY_UILAB_TITLE"),
                at: UIPoint(x: 40, y: 40),
                font: UIFont(pointSize: 20, weight: .bold),
                color: SIMD4(0.96, 0.97, 1, 1)
            ),
            sampleLabel(
                labels.label(for: "$OPENSKY_UILAB_BODY"),
                at: UIPoint(x: 40, y: 72),
                font: UIFont(pointSize: 13),
                color: SIMD4(0.80, 0.85, 0.95, 1)
            ),
            // Long-string case: wraps at a fixed point width.
            sampleLabel(
                labels.label(for: "$OPENSKY_UILAB_LONG"),
                at: UIPoint(x: 40, y: 96),
                font: UIFont(pointSize: 13),
                color: SIMD4(0.72, 0.78, 0.90, 1),
                maxWidth: localizedSampleWrapWidth
            ),
            // Unknown-key case: the token stays on screen verbatim.
            sampleLabel(
                labels.label(for: localizedSampleMissingToken),
                at: UIPoint(x: 40, y: 196),
                font: UIFont(pointSize: 13),
                color: SIMD4(0.95, 0.60, 0.45, 1)
            ),
            // Clip case: no wrap width, so the line runs past the frame edge.
            sampleLabel(
                labels.label(for: "$OPENSKY_UILAB_CLIP"),
                at: UIPoint(x: 24, y: -32),
                font: UIFont(pointSize: 14),
                color: SIMD4(0.85, 0.88, 0.95, 1),
                anchor: .bottomLeft
            )
        ])
    }

    private static func sampleLabel(
        _ text: String,
        at offset: UIPoint,
        font: UIFont,
        color: SIMD4<Float>,
        maxWidth: Float? = nil,
        anchor: UIAnchor = .topLeft
    ) -> UINode {
        UINode(
            anchor: anchor,
            offset: offset,
            content: .label(UILabel(text: text, font: font, color: color, maxWidth: maxWidth))
        )
    }
}
