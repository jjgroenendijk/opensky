// The steps and `--dump` lines both movie probes share: a pointer move or click, and
// one display node with its text field facts and where it is placed.

import Foundation
import OpenSkyFormatsSWF

/// The steps and dump lines both movie probes share.
enum SWFMovieProbeSteps {
    static func printNode(_ path: String, runtime: SWFMovieRuntime) {
        guard let node = runtime.node(atPath: path, from: runtime.root) else {
            print("[INFO] swf probe dump \(path): not found")
            return
        }
        print("[INFO] swf probe dump \(path):")
        for property in [AS2DisplayProperty.visible, .alpha] {
            let value = runtime.displayProperty(property, of: node)
            print("[INFO]   \(property.actionScriptName) = \(SWFInvokeLog.describe(value))")
        }
        for name in node.object.ownPropertyNames.sorted() {
            let value = node.object.lookup(name)?.property.value ?? .undefined
            print("[INFO]   \(name) = \(SWFInvokeLog.describe(value))")
            if ["EntriesA", "entryList", "HUDModes", "HudElements"].contains(name) {
                printArguments("\(path).\(name)", [value])
            }
        }
        if let id = node.characterId, let sprite = runtime.movie.sprite(id) {
            print("[INFO]   sprite \(id) frame \(node.currentFrame) of \(sprite.frameCount)")
            for (index, frame) in sprite.timeline.frames.enumerated() {
                let names = frame.steps.compactMap { step -> String? in
                    guard case let .place(placement) = step else { return "remove" }
                    let id = placement.characterId.map { "#\($0)" } ?? ""
                    return "\(placement.depth):\(placement.name ?? "-")\(id)"
                }
                print(
                    "[INFO]   frame \(index) \(frame.label ?? "") \(names.joined(separator: " "))"
                )
            }
        }
        if let text = runtime.text(of: node) {
            print("[INFO]   text = \"\(text)\"")
        }
        if
            let id = node.characterId, let field = runtime.movie.editText(id),
            let fontID = field.fontID
        {
            let font = runtime.movie.font(fontID)
            let imported = runtime.movie.importedNames[fontID] ?? "-"
            print(
                "[INFO]   font #\(fontID) \(font?.name ?? "-") glyphs \(font?.glyphs.count ?? 0)"
                    + " imported \(imported) height \(field.fontHeight ?? 0)"
            )
            let flags = field.flags
            print(
                "[INFO]   field colour \(field.color.map { "\($0)" } ?? "-") html \(flags.html)"
                    + " wordWrap \(flags.wordWrap) multiline \(flags.multiline)"
                    + " autoSize \(flags.autoSize) align \(field.layout?.align ?? 0)"
            )
            printLayout(field, content: runtime.text(of: node), runtime: runtime)
        }
        printPlacement(node, runtime: runtime)
        for child in node.children {
            print("[INFO]   child \(child.depth) \(child.name ?? "-") \(child.content)")
            if let id = child.characterId, let shape = runtime.movie.shape(id) {
                print("[INFO]     fills \(shape.fillStyles)")
            }
        }
    }

    /// The node's matrix and its bounds on the stage, in pixels.
    static func printPlacement(_ node: SWFDisplayObject, runtime: SWFMovieRuntime) {
        let matrix = node.matrix
        print(
            "[INFO]   matrix scale \(matrix.scaleX) \(matrix.scaleY) rotate "
                + "\(matrix.rotateSkew0) \(matrix.rotateSkew1) translate "
                + "\(Float(matrix.translateX) / SWFMovieRuntime.twipsPerPixel) "
                + "\(Float(matrix.translateY) / SWFMovieRuntime.twipsPerPixel)"
        )
        if node.colorTransform != .identity {
            let colour = node.colorTransform
            print("[INFO]   colour multiply \(colour.multiply) add \(colour.add)")
        }
        guard let transform = runtime.transform(of: node) else {
            return
        }
        let box = runtime.localBounds(of: node).transformed(by: transform)
        let pixels = [box.minX, box.minY, box.maxX, box.maxY]
            .map { unsafe String(format: "%.1f", $0 / SWFMovieRuntime.twipsPerPixel) }
        print("[INFO]   stage bounds px \(pixels.joined(separator: " "))")
    }

    /// The field's text laid out as the renderer lays it out: runs, glyphs, and the
    /// first glyph's place in the field, in twips.
    static func printLayout(_ field: SWFEditText, content: String?, runtime: SWFMovieRuntime) {
        guard let font = runtime.movieScene.resolvedFont(for: field) else {
            print("[INFO]   layout: the font does not resolve")
            return
        }
        let layout = SWFTextLayout.editText(field, font: font, content: content)
        let glyphs = layout.runs.flatMap(\.glyphs)
        let first = glyphs.first.map { "\($0.x),\($0.y)" } ?? "-"
        print(
            "[INFO]   layout: \(layout.runs.count) runs, \(glyphs.count) glyphs, first at \(first),"
                + " \(layout.missingGlyphs) missing, font \(font.name) glyphs \(font.glyphs.count),"
                + " bounds \(field.bounds)"
        )
    }

    /// Moves the cursor to a stage point in pixels, presses and releases for a click,
    /// and prints what a press reaches and the clip on top.
    static func pointer(_ step: String, runtime: SWFMovieRuntime) throws {
        let numbers = step.dropFirst(6).split { $0 == "," || $0 == "/" }.compactMap { Double($0) }
        guard numbers.count == 2 else {
            throw CLIError.usage("swf movie-probe: \(step) needs <x>,<y>")
        }
        let (pointX, pointY) = (numbers[0], numbers[1])
        runtime.handle(.pointerMoved(x: pointX, y: pointY))
        print(
            "[INFO] swf probe pointer \(pointX),\(pointY): target "
                + "\(runtime.pointerTarget?.targetPath ?? "none"), top "
                + "\(runtime.topMostEntity()?.targetPath ?? "none")"
        )
        if step.hasPrefix("click:") {
            runtime.handle(.pointerPressed(x: pointX, y: pointY))
            runtime.handle(.pointerReleased(x: pointX, y: pointY))
        }
    }

    /// Each argument, and one level into every array element's own properties.
    /// An array prints its elements, so a stepper's option list shows.
    nonisolated static func describeDeep(_ value: AS2Value) -> String {
        guard case let .object(object) = value, object.lookup("0") != nil else {
            return SWFInvokeLog.describe(value)
        }
        let items = object.ownPropertyNames.compactMap { name in Int(name).map { ($0, name) } }
            .sorted { $0.0 < $1.0 }
            .map { SWFInvokeLog.describe(object.lookup($0.1)?.property.value ?? .undefined) }
        return "[\(items.joined(separator: ", "))]"
    }

    nonisolated static func printArguments(_ name: String, _ arguments: [AS2Value]) {
        print("[INFO] swf probe capture \(name): \(arguments.count) arguments")
        for (index, argument) in arguments.enumerated() {
            print("[INFO]   arg \(index) = \(SWFInvokeLog.describe(argument))")
            guard case let .object(array) = argument else { continue }
            for key in array.ownPropertyNames.sorted() {
                let element = array.lookup(key)?.property.value ?? .undefined
                guard case let .object(row) = element else {
                    print("[INFO]     [\(key)] = \(SWFInvokeLog.describe(element))")
                    continue
                }
                if row.lookup("value") == nil {
                    row.assign(.number(0), for: "value")
                }
                let fields = row.ownPropertyNames.sorted().map { field in
                    let value = row.lookup(field)?.property.value ?? .undefined
                    return "\(field)=\(describeDeep(value))"
                }
                print("[INFO]     [\(key)] \(fields.joined(separator: " "))")
            }
        }
    }
}
