// One bar per measured scene: the average frame rate, with the 1% low drawn inside it.

import AppKit
import OpenSkyWorld

final class BenchmarkChartView: NSView {
    var scenes: [BenchmarkSceneResult] = [] {
        didSet {
            needsDisplay = true
            setAccessibilityValue(scenes.compactMap { scene in
                scene.frameTime.map { "\(scene.title) \(Int($0.averageFPS)) fps" }
            }.joined(separator: ", "))
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: LauncherPageLayout.width, height: 120)
    }

    override func draw(_: NSRect) {
        let measured = scenes.compactMap(\.frameTime)
        guard !measured.isEmpty else { return }
        let top = max(60, measured.map(\.averageFPS).max() ?? 60)
        let gap: CGFloat = 4
        let width = (bounds.width - gap * CGFloat(measured.count - 1)) / CGFloat(measured.count)
        for (index, frame) in measured.enumerated() {
            let x = CGFloat(index) * (width + gap)
            let average = bounds.height * CGFloat(frame.averageFPS / top)
            let low = bounds.height * CGFloat(frame.onePercentLowFPS / top)
            LauncherStyle.highlight.setFill()
            NSRect(x: x, y: 0, width: width, height: bounds.height).fill()
            LauncherStyle.good.setFill()
            NSRect(x: x, y: 0, width: width, height: average).fill()
            LauncherStyle.warning.setFill()
            NSRect(x: x, y: 0, width: width, height: min(low, average)).fill()
        }
        let line = bounds.height * CGFloat(60 / top)
        LauncherStyle.rule.setFill()
        NSRect(x: 0, y: line, width: bounds.width, height: 1).fill()
    }
}
