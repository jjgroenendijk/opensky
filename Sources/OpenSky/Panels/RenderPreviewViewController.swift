// Render Preview: the sidebar side of `openskycli preview`. One record, reference,
// mesh, or cell, on the studio or cell stage, from one angle or all five. The scene
// builds on `PreviewSceneWorker`; only the render runs here. docs/tools/preview-render.md.

import AppKit
import Metal
import OpenSkyGameData
import OpenSkyPreview
import OpenSkyRendering

final class RenderPreviewViewController: NSViewController, FullContentReloadable {
    var gameDataRoot: GameDataRoot?

    private var worker: PreviewSceneWorker?
    private var renderTask: Task<Void, Never>?

    let kindControl = NSPopUpButton()
    let targetControl = NSTextField()
    let cellControl = NSTextField()
    let stageControl = NSPopUpButton()
    let angleControl = NSPopUpButton()
    let timeControl = NSTextField(string: "13")
    let weatherControl = NSTextField()
    let renderControl = NSButton(title: "Render", target: nil, action: nil)
    let statsLabel = NSTextField(labelWithString: "Views: none")
    let imageStack = NSStackView()

    /// Menu titles of `stageControl`, after "Auto".
    static let stages = PreviewStage.allCases
    /// Menu titles of `angleControl`: each angle, then all of them.
    static let angleTitles = PreviewAngle.allCases.map(\.rawValue) + ["all"]

    override func loadView() {
        view = makeContentView()
        view.setAccessibilityIdentifier("RenderPreview")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reload()
    }

    func reloadFullContent(context: FullContentContext) {
        gameDataRoot = context.gameDataRoot
        reload()
    }

    private func reload() {
        renderTask?.cancel()
        worker = nil
        guard let root = gameDataRoot else {
            statsLabel.stringValue = "Views: game data not located"
            renderControl.isEnabled = false
            return
        }
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            statsLabel.stringValue = "Views: no Metal 4 GPU"
            renderControl.isEnabled = false
            return
        }
        worker = PreviewSceneWorker(
            root: root, device: device, settings: PlayerSettingsFile.savedData()
        )
        renderControl.isEnabled = true
    }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        kindControl.addItems(withTitles: PreviewTargetKind.allCases.map(\.title))
        stageControl.addItems(withTitles: ["Auto"] + Self.stages.map(\.rawValue.capitalized))
        angleControl.addItems(withTitles: Self.angleTitles.map(\.capitalized))
        angleControl.selectItem(withTitle: PreviewAngle.threeQuarter.rawValue.capitalized)
        targetControl.placeholderString = "FormID, editor ID, or mesh path"
        cellControl.placeholderString = "Cell: editor ID, or Tamriel 8 25"
        weatherControl.placeholderString = "Weather editor ID"
        renderControl.bezelStyle = .rounded
        renderControl.target = self
        renderControl.action = #selector(render)
        identify()
        let fields = NSStackView(views: [
            row("Target", kindControl, targetControl), row("In cell", cellControl),
            row("Stage", stageControl, angleControl),
            row("Hour", timeControl, weatherControl), row("", renderControl, statsLabel)
        ])
        fields.orientation = .vertical
        fields.alignment = .leading
        fields.spacing = 6
        imageStack.orientation = .vertical
        imageStack.alignment = .leading
        imageStack.spacing = 8
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = imageStack
        imageStack.translatesAutoresizingMaskIntoConstraints = false
        imageStack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        let stack = NSStackView(views: [fields, scroll])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        return stack
    }

    private func identify() {
        tag(kindControl, "RenderPreviewKindControl", "What the target text names.")
        tag(targetControl, "RenderPreviewTargetControl", "A FormID, an editor ID, or a mesh path.")
        tag(cellControl, "RenderPreviewCellControl", "The cell a record or mesh stands in.")
        tag(stageControl, "RenderPreviewStageControl", "Studio light, or the cell's own light.")
        tag(angleControl, "RenderPreviewAngleControl", "One camera angle, or all five.")
        tag(timeControl, "RenderPreviewHourControl", "The hour of day on the cell stage.")
        tag(weatherControl, "RenderPreviewWeatherControl", "Force a weather on the cell stage.")
        tag(renderControl, "RenderPreviewRenderControl", "Build the scene and render each angle.")
        tag(statsLabel, "RenderPreviewStatsLabel")
        tag(imageStack, "RenderPreviewImages")
        for field in [targetControl, cellControl, weatherControl] {
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        }
        timeControl.widthAnchor.constraint(equalToConstant: 48).isActive = true
    }

    private func tag(_ control: NSView, _ identifier: String, _ tip: String? = nil) {
        control.setAccessibilityIdentifier(identifier)
        control.toolTip = tip
    }

    private func row(_ title: String, _ views: NSView...) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 56).isActive = true
        let row = NSStackView(views: [label] + views)
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    // MARK: - Render

    /// The request the controls describe; nil with the reason shown.
    func currentRequest() -> PreviewRequest? {
        do {
            let kind = PreviewTargetKind.allCases[max(kindControl.indexOfSelectedItem, 0)]
            var options = try PreviewOptions(
                kind: kind, target: targetControl.stringValue, inCell: cellControl.stringValue
            )
            let stage = stageControl.indexOfSelectedItem
            options.stage = stage > 0 ? Self.stages[stage - 1].rawValue : nil
            options.angles = Self.angleTitles[max(angleControl.indexOfSelectedItem, 0)]
            options.timeOfDay = min(max(Float(timeControl.stringValue) ?? 13, 0), 24)
            let weather = weatherControl.stringValue.trimmingCharacters(in: .whitespaces)
            options.weather = weather.isEmpty ? nil : weather
            options.width = 960
            options.height = 540
            return try options.request()
        } catch {
            statsLabel.stringValue = "Views: \(error.description)"
            return nil
        }
    }

    @objc private func render() {
        guard let worker, let request = currentRequest() else { return }
        renderControl.isEnabled = false
        statsLabel.stringValue = "Views: building…"
        renderTask = Task { [weak self] in
            let result = await worker.build(request)
            guard let self, !Task.isCancelled else { return }
            renderControl.isEnabled = true
            switch result {
            case let .success(built):
                show(built, request: request)
            case let .failure(error):
                statsLabel.stringValue = "Views: \(error.description)"
            }
        }
    }

    private func show(_ built: PreviewSceneResult, request: PreviewRequest) {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let frames: [PreviewFrame]
        do {
            frames = try PreviewRenderJob.render(
                built.scene, request: request,
                sources: PreviewRenderSources(
                    device: device, loadOrder: built.loadOrder, fileSystem: built.fileSystem
                )
            )
        } catch {
            statsLabel.stringValue = "Views: \(String(describing: error))"
            return
        }
        imageStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for frame in frames {
            let caption = NSTextField(labelWithString: Self.caption(frame.measure))
            imageStack.addArrangedSubview(caption)
            guard let image = FrameScreenshot.image(from: frame.texture) else { continue }
            let imageView = NSImageView(image: NSImage(cgImage: image, size: .zero))
            imageView.imageScaling = .scaleProportionallyDown
            imageStack.addArrangedSubview(imageView)
        }
        let drawn = frames.filter { !$0.measure.isBlank }.count
        statsLabel.stringValue = "Views: \(drawn) of \(frames.count) drawn"
    }

    static func caption(_ measure: PreviewViewMeasure) -> String {
        let coverage = String(format: "%.1f", measure.coverage * 100)
        return "\(measure.view.name): \(measure.drawnInstances) instances, "
            + "\(measure.triangles) triangles, \(coverage)% covered"
    }
}
