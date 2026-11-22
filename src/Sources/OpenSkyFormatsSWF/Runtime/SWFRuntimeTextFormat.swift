// `TextFormat` and a field's `setTextFormat`, `setNewTextFormat`, `getTextFormat`, and
// `getNewTextFormat`. A field draws in one font, size, and colour, so a format applies to
// the whole field. The font name goes through the same lookup as a movie's own fields, so
// a name no font library maps draws nothing, as in the game
// (docs/formats/swf-text.md#finding-a-font-in-the-game).

import Foundation

/// The parts of a script's `TextFormat` a field draws with; nil keeps the field's own.
nonisolated public struct SWFTextFormat: Equatable, Sendable {
    public var font: String?
    /// Points, which are stage pixels.
    public var size: Double?
    public var color: SWFColor?

    public init(font: String? = nil, size: Double? = nil, color: SWFColor? = nil) {
        self.font = font
        self.size = size
        self.color = color
    }

    /// This format with every part `newer` sets laid over it.
    func merged(with newer: SWFTextFormat) -> SWFTextFormat {
        SWFTextFormat(
            font: newer.font ?? font, size: newer.size ?? size, color: newer.color ?? color
        )
    }
}

nonisolated extension SWFEditText {
    /// The same field drawn with a script's format.
    public func withFormat(_ format: SWFTextFormat) -> SWFEditText {
        SWFEditText(
            characterId: characterId, bounds: bounds, flags: flags,
            fontID: format.font == nil ? fontID : nil,
            fontClass: format.font ?? fontClass,
            fontHeight: format.size
                .map { UInt16(clamping: Int(($0 * 20).rounded())) } ?? fontHeight,
            color: format.color ?? color, maxLength: maxLength,
            layout: layout, variableName: variableName, initialText: initialText,
            htmlParse: htmlParse
        )
    }
}

nonisolated extension SWFMovieRuntime {
    /// A field with no font names this one, at 12 points in black.
    static let defaultTextFont = "Times New Roman"

    static func installTextFormat(_ runtime: AS2Runtime, fieldPrototype: AS2Object) {
        let prototype = AS2Object(prototype: runtime.objectPrototype)
        AS2Runtime.constructor(runtime, name: "TextFormat", prototype: prototype) { context in
            guard let instance = context.thisObject else { return .undefined }
            for (index, name) in ["font", "size", "color"].enumerated() {
                instance.define(context.argument(index), for: name)
            }
            return .undefined
        }
        for name in ["setTextFormat", "setNewTextFormat"] {
            AS2Runtime.method(runtime, on: fieldPrototype, name: name) { context in
                try applyTextFormat(context)
            }
        }
        for name in ["getTextFormat", "getNewTextFormat"] {
            AS2Runtime.method(runtime, on: fieldPrototype, name: name) { context in
                textFormatObject(context)
            }
        }
    }

    /// `setTextFormat(format)` sets the field's format. The forms with a character range
    /// are ignored, because a field draws in one format.
    private static func applyTextFormat(_ context: AS2CallContext) throws -> AS2Value {
        guard
            context.arguments.count == 1,
            let owner = movieRuntime(context), let node = node(context),
            let format = context.argument(0).objectValue
        else {
            return .undefined
        }
        let read = { (name: String) -> AS2Value? in
            guard let value = format.lookup(name)?.property.value else { return nil }
            switch value {
            case .undefined, .null: return nil
            default: return value
            }
        }
        var parsed = SWFTextFormat()
        if let font = read("font") {
            parsed.font = try context.interpreter.toString(font)
        }
        if let size = read("size") {
            let points = try context.interpreter.toNumber(size)
            parsed.size = points.isFinite ? max(0, points) : nil
        }
        if let color = read("color") {
            let rgb = try context.interpreter.toNumber(color)
            parsed.color = rgb.isFinite ? SWFColor(rgb: Int(rgb)) : nil
        }
        node.textFormat = (node.textFormat ?? SWFTextFormat()).merged(with: parsed)
        owner.markDirty()
        return .undefined
    }

    private static func textFormatObject(_ context: AS2CallContext) -> AS2Value {
        let result = context.runtime.makeObject()
        guard
            let owner = movieRuntime(context), let node = node(context),
            let field = owner.textField(of: node)
        else {
            return .object(result)
        }
        let font = field.fontClass ?? field.fontID.flatMap { id in
            owner.movie.font(id)?.name ?? owner.movie.importedNames[id]
        } ?? defaultTextFont
        let color = field.color.map { Int($0.red) << 16 | Int($0.green) << 8 | Int($0.blue) } ?? 0
        result.define(.string(font), for: "font")
        result.define(.number(Double(field.fontHeight ?? 240) / 20), for: "size")
        result.define(.number(Double(color)), for: "color")
        return .object(result)
    }
}

nonisolated extension SWFColor {
    /// An opaque colour from a `0xRRGGBB` number.
    init(rgb: Int) {
        self.init(
            red: UInt8(truncatingIfNeeded: rgb >> 16), green: UInt8(truncatingIfNeeded: rgb >> 8),
            blue: UInt8(truncatingIfNeeded: rgb), alpha: 255
        )
    }
}
