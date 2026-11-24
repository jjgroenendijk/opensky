// The `--dump` lines of the movie probes: one display node with its text field
// facts, and where it is placed.

import Foundation
import OpenSkyFormatsSWF

extension SWFSystemMenuCommand {
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
}
