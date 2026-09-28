// `TextField`, `Stage`, and `Selection` (milestone 8.3.2 phase 2). Split from
// `SWFRuntimeNatives.swift` to stay inside the file-size limit.
//
// `SetText` and `SetTextHTML` are Scaleform GFx extensions to `TextField`, not
// Flash methods — the vanilla install calls `SetText` 595 times across 31
// movies, which is why they are here rather than deferred. There is no public
// specification for the GFx object model, so they are reimplemented from
// observed usage.
//
// `Selection` records focus but does not implement focus *behavior*: nothing
// routes keyboard input to the focused object, nothing draws a focus
// indicator, and no `onSetFocus` event is dispatched. That is phase 3. Focus is
// recorded here so `setFocus`/`getFocus` round-trip and stay off the
// missing-API tally, and so the phase-3 focus manager has state to adopt.

import Foundation

nonisolated extension SWFRuntimeNatives {
    // MARK: - TextField

    static func installTextField(_ runtime: AS2Runtime, prototype: AS2Object) {
        AS2Natives.constructor(runtime, name: "TextField", prototype: prototype) { _ in .undefined }
        AS2Natives.method(runtime, on: prototype, name: "SetText") { context in
            try assignText(context, html: false)
        }
        AS2Natives.method(runtime, on: prototype, name: "SetTextHTML") { context in
            try assignText(context, html: true)
        }
        AS2Natives.method(runtime, on: prototype, name: "toString") { context in
            .string(node(context)?.targetPath ?? "[object TextField]")
        }
        // Formatting is accepted and ignored: the text layout path renders one
        // font and color per field, so a format object has nothing to change.
        AS2Natives.method(runtime, on: prototype, name: "setTextFormat") { _ in .undefined }
        AS2Natives.method(runtime, on: prototype, name: "getTextFormat") { context in
            .object(context.runtime.makeObject())
        }
    }

    private static func assignText(_ context: AS2CallContext, html: Bool) throws -> AS2Value {
        guard let owner = movieRuntime(context), let node = node(context) else {
            return .undefined
        }
        let text = try context.string(0)
        owner.setText(html ? SWFEditText.stripHTML(text) : text, of: node)
        return .undefined
    }

    // MARK: - Stage

    /// `Stage` is a plain global object, not a constructor. Its size is the
    /// movie's own `FrameSize` in pixels: OpenSky letterboxes the movie into the
    /// viewport rather than reflowing it, so the stage a menu lays itself out
    /// against never changes size.
    static func installStage(_ runtime: AS2Runtime, movie: SWFMovie) {
        let stage = runtime.makeObject()
        let widthTwips = Float(movie.frameSize.xMax - movie.frameSize.xMin)
        let heightTwips = Float(movie.frameSize.yMax - movie.frameSize.yMin)
        stage.define(
            .number(Double(widthTwips / SWFMovieRuntime.twipsPerPixel)),
            for: "width", flags: .dontEnumerate
        )
        stage.define(
            .number(Double(heightTwips / SWFMovieRuntime.twipsPerPixel)),
            for: "height", flags: .dontEnumerate
        )
        stage.define(.string("noScale"), for: "scaleMode", flags: .dontEnumerate)
        stage.define(.string("TL"), for: "align", flags: .dontEnumerate)
        stage.define(.boolean(false), for: "showMenu", flags: .dontEnumerate)
        stage.define(
            .object(stageRectangle(runtime, width: widthTwips, height: heightTwips)),
            for: "visibleRect", flags: .dontEnumerate
        )
        stage.define(
            .object(stageRectangle(runtime, width: widthTwips, height: heightTwips)),
            for: "safeRect", flags: .dontEnumerate
        )
        installListenerList(runtime, on: stage)
        runtime.globalObject.define(.object(stage), for: "Stage", flags: .dontEnumerate)
    }

    /// Scaleform GFx exposes both rectangles in stage pixels. OpenSky has no
    /// overscan crop or safe-area inset, so each covers the movie FrameSize.
    /// They remain separate objects because menu bytecode may mutate one.
    private static func stageRectangle(
        _ runtime: AS2Runtime,
        width: Float,
        height: Float
    ) -> AS2Object {
        let rectangle = runtime.makeObject()
        rectangle.define(.number(0), for: "x")
        rectangle.define(.number(0), for: "y")
        rectangle.define(
            .number(Double(width / SWFMovieRuntime.twipsPerPixel)),
            for: "width"
        )
        rectangle.define(
            .number(Double(height / SWFMovieRuntime.twipsPerPixel)),
            for: "height"
        )
        return rectangle
    }

    // MARK: - Selection

    static func installSelection(_ runtime: AS2Runtime) {
        let selection = runtime.makeObject()
        AS2Natives.method(runtime, on: selection, name: "setFocus") { context in
            guard let owner = movieRuntime(context) else {
                return .boolean(false)
            }
            return .boolean(owner.setFocus(context.argument(0)))
        }
        AS2Natives.method(runtime, on: selection, name: "getFocus") { context in
            guard let owner = movieRuntime(context), let focus = owner.focusTarget else {
                return .null
            }
            return .string(focus.targetPath)
        }
        // Caret and selection ranges need a text-input implementation, which is
        // phase 3. Flash reports -1 when nothing has a text focus, so that is
        // what these answer.
        for name in ["getBeginIndex", "getEndIndex", "getCaretIndex"] {
            AS2Natives.method(runtime, on: selection, name: name) { _ in .integer(-1) }
        }
        AS2Natives.method(runtime, on: selection, name: "setSelection") { _ in .undefined }
        installListenerList(runtime, on: selection)
        runtime.globalObject.define(.object(selection), for: "Selection", flags: .dontEnumerate)
    }
}

nonisolated extension SWFMovieRuntime {
    /// `Selection.setFocus(target)`: accepts a display object or a path string.
    /// Passing null clears focus, which Flash treats as a successful call.
    @discardableResult
    func setFocus(_ target: AS2Value) -> Bool {
        switch target {
        case .null, .undefined:
            focusTarget = nil
            focusChanges += 1
            return true
        case let .object(object):
            guard let node = SWFDisplayObject.resolve(object) else {
                return false
            }
            focusTarget = node
            focusChanges += 1
            return true
        case let .string(path):
            guard let node = node(atPath: path, from: root) else {
                return false
            }
            focusTarget = node
            focusChanges += 1
            return true
        default:
            return false
        }
    }
}
