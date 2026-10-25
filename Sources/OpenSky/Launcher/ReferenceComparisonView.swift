// The newest comparison pair, drawn as `ReferenceComparisonState` says.
// `openskycli reference capture` writes the files.

import AppKit
import OpenSkyReference

@MainActor
final class ReferenceComparisonView: NSStackView {
    private let imageViews = [NSImageView(), NSImageView()]
    private var images: [ReferenceComparisonImage: NSImage] = [:]
    private(set) var state = ReferenceComparisonState()

    init(width: CGFloat) {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 10
        for view in imageViews {
            view.imageScaling = .scaleProportionallyUpOrDown
            view.heightAnchor.constraint(equalToConstant: width * 9 / 16).isActive = true
            addArrangedSubview(view)
        }
        imageViews[0].setAccessibilityIdentifier("ReferenceFirstImage")
        imageViews[1].setAccessibilityIdentifier("ReferenceSecondImage")
        widthAnchor.constraint(equalToConstant: width).isActive = true
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func load(_ run: ReferenceComparisonRun) {
        images[.opensky] = NSImage(contentsOf: run.openskyImage)
        images[.reference] = NSImage(contentsOf: run.referenceImage)
        images[.difference] = NSImage(contentsOf: run.differenceImage)
        isHidden = images[.opensky] == nil || images[.reference] == nil
        draw()
    }

    func select(_ mode: ReferenceComparisonMode) {
        state.select(mode)
        draw()
    }

    private func draw() {
        let shown = state.images
        for (index, view) in imageViews.enumerated() {
            view.isHidden = index >= shown.count
            view.image = index < shown.count ? images[shown[index]] : nil
        }
    }
}
