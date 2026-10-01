// `MovieClip` and the global objects the display layer owns. These are Flash
// and Scaleform GFx built-ins that no spec defines, so they follow public API
// docs and vanilla usage (docs/engine/as2-display-runtime.md). Methods reach
// the tree through `AS2Runtime.host`, because the built-ins install first.

import Foundation
import simd

nonisolated public enum SWFRuntimeNatives: Sendable {
    /// The prototypes a `SWFMovieRuntime` needs back after installation.
    public struct Installed {
        public let movieClipPrototype: AS2Object
        public let textFieldPrototype: AS2Object
    }

    public static func install(into runtime: AS2Runtime, movie: SWFMovie) -> Installed {
        let movieClipPrototype = AS2Object(prototype: runtime.objectPrototype)
        installMovieClip(runtime, prototype: movieClipPrototype)
        let textFieldPrototype = AS2Object(prototype: runtime.objectPrototype)
        installTextField(runtime, prototype: textFieldPrototype)
        installStage(runtime, movie: movie)
        installSelection(runtime)
        installKey(runtime)
        installMouse(runtime)
        installExternalInterface(runtime)
        installTimers(runtime)
        installMovieClipLoader(runtime)
        installGeometry(runtime)
        return Installed(
            movieClipPrototype: movieClipPrototype,
            textFieldPrototype: textFieldPrototype
        )
    }

    /// The movie runtime behind a call, or nil when the host is not ours.
    public static func movieRuntime(_ context: AS2CallContext) -> SWFMovieRuntime? {
        (context.runtime.host as? SWFRuntimeHost)?.owner
    }

    /// The display object a method was called on.
    public static func node(_ context: AS2CallContext) -> SWFDisplayObject? {
        SWFDisplayObject.resolve(context.thisObject)
    }

    /// A listener list recorded on a built-in. Nothing dispatches to it yet —
    /// event routing is phase 3 — but recording keeps `addListener` off the
    /// missing-API tally and leaves the list where the dispatcher will find it.
    public static func installListenerList(_ runtime: AS2Runtime, on object: AS2Object) {
        let listeners = runtime.makeArray()
        object.define(.object(listeners), for: "_listeners", flags: .dontEnumerate)
        AS2Natives.method(runtime, on: object, name: "addListener") { context in
            guard let listener = context.argument(0).objectValue else {
                return .boolean(false)
            }
            listeners.appendElement(.object(listener))
            return .boolean(true)
        }
        AS2Natives.method(runtime, on: object, name: "removeListener") { context in
            guard let listener = context.argument(0).objectValue else {
                return .boolean(false)
            }
            let before = listeners.elements
            let kept = before.filter { $0.objectValue !== listener }
            listeners.resizeArray(to: 0)
            for element in kept {
                listeners.appendElement(element)
            }
            return .boolean(kept.count < before.count)
        }
    }

    // MARK: - MovieClip

    private static func installMovieClip(_ runtime: AS2Runtime, prototype: AS2Object) {
        AS2Natives.constructor(runtime, name: "MovieClip", prototype: prototype) { _ in .undefined }
        installPlayback(runtime, prototype: prototype)
        installDepths(runtime, prototype: prototype)
        installInstancing(runtime, prototype: prototype)
        installClipGeometry(runtime, prototype: prototype)
        installDuplicate(runtime, prototype: prototype)
        AS2Natives.method(runtime, on: prototype, name: "toString") { context in
            .string(node(context)?.targetPath ?? "[object MovieClip]")
        }
        AS2Natives.method(runtime, on: prototype, name: "hitTest") { context in
            .boolean(hitTest(context))
        }
    }

    private static func installPlayback(_ runtime: AS2Runtime, prototype: AS2Object) {
        AS2Natives.method(runtime, on: prototype, name: "play") { context in
            timeline(context) { owner, node in owner.perform(.play, on: node) }
        }
        AS2Natives.method(runtime, on: prototype, name: "stop") { context in
            timeline(context) { owner, node in owner.perform(.stop, on: node) }
        }
        AS2Natives.method(runtime, on: prototype, name: "gotoAndPlay") { context in
            try goto(context, play: true)
        }
        AS2Natives.method(runtime, on: prototype, name: "gotoAndStop") { context in
            try goto(context, play: false)
        }
        AS2Natives.method(runtime, on: prototype, name: "nextFrame") { context in
            timeline(context) { owner, node in
                owner.gotoFrame(node.currentFrame + 1, of: node, play: false)
            }
        }
        AS2Natives.method(runtime, on: prototype, name: "prevFrame") { context in
            timeline(context) { owner, node in
                owner.gotoFrame(node.currentFrame - 1, of: node, play: false)
            }
        }
    }

    private static func installDepths(_ runtime: AS2Runtime, prototype: AS2Object) {
        AS2Natives.method(runtime, on: prototype, name: "getDepth") { context in
            node(context).map { .integer(Int($0.depth)) } ?? .undefined
        }
        AS2Natives.method(runtime, on: prototype, name: "getNextHighestDepth") { context in
            guard let node = node(context) else {
                return .undefined
            }
            return .integer(Int(node.children.last?.depth ?? 0) + 1)
        }
        AS2Natives.method(runtime, on: prototype, name: "getInstanceAtDepth") { context in
            guard let node = node(context) else {
                return .undefined
            }
            let depth = try depthValue(context.number(0))
            return node.child(atDepth: depth).map { .object($0.object) } ?? .undefined
        }
        AS2Natives.method(runtime, on: prototype, name: "swapDepths") { context in
            try swapDepths(context)
        }
        AS2Natives.method(runtime, on: prototype, name: "removeMovieClip") { context in
            guard
                let owner = movieRuntime(context), let node = node(context),
                let parent = node.parent
            else {
                return .undefined
            }
            parent.removeChild(atDepth: node.depth)
            owner.markDirty()
            return .undefined
        }
    }

    private static func installInstancing(_ runtime: AS2Runtime, prototype: AS2Object) {
        AS2Natives.method(runtime, on: prototype, name: "attachMovie") { context in
            guard let owner = movieRuntime(context), let node = node(context) else {
                return .undefined
            }
            let linkage = try context.string(0)
            let name = try context.string(1)
            let depth = try depthValue(context.number(2))
            guard
                let attached = owner.attach(
                    linkage: linkage, into: node, depth: depth, name: name
                )
            else {
                return .undefined
            }
            return .object(attached.object)
        }
        AS2Natives.method(runtime, on: prototype, name: "createEmptyMovieClip") { context in
            guard let owner = movieRuntime(context), let node = node(context) else {
                return .undefined
            }
            let created = SWFDisplayObject(content: .clip(nil), frameCount: 1)
            created.object.prototype = owner.movieClipPrototype
            owner.globalMouseHandlers.observe(created)
            created.name = try context.string(0)
            try node.addChild(created, atDepth: depthValue(context.number(1)))
            owner.markDirty()
            return .object(created.object)
        }
    }

    // MARK: - Method bodies

    private static func timeline(
        _ context: AS2CallContext,
        _ body: (SWFMovieRuntime, SWFDisplayObject) -> Void
    ) -> AS2Value {
        guard let owner = movieRuntime(context), let node = node(context) else {
            return .undefined
        }
        body(owner, node)
        return .undefined
    }

    /// `gotoAndStop(frame)` takes a one-based frame number or a label, unlike
    /// `ActionGotoFrame`, whose operand the specification defines as zero-based.
    private static func goto(_ context: AS2CallContext, play: Bool) throws -> AS2Value {
        guard let owner = movieRuntime(context), let node = node(context) else {
            return .undefined
        }
        if case let .string(label) = context.argument(0), Double(label) == nil {
            owner.gotoLabel(label, of: node, play: play)
            return .undefined
        }
        let number = try context.number(0)
        guard number.isFinite else {
            return .undefined
        }
        owner.gotoFrame(Int(number) - 1, of: node, play: play)
        return .undefined
    }

    private static func swapDepths(_ context: AS2CallContext) throws -> AS2Value {
        guard
            let owner = movieRuntime(context), let node = node(context),
            let parent = node.parent
        else {
            return .undefined
        }
        if
            let other = SWFDisplayObject.resolve(context.argument(0).objectValue),
            other.parent === parent
        {
            parent.swapChild(node, toDepth: other.depth)
        } else {
            try parent.swapChild(node, toDepth: depthValue(context.number(0)))
        }
        owner.markDirty()
        return .undefined
    }

    /// Bounding-box hit test in the clip's parent space. Shape-level hit
    /// testing is not implemented; vanilla CLIK uses the box form.
    private static func hitTest(_ context: AS2CallContext) -> Bool {
        guard let owner = movieRuntime(context), let node = node(context) else {
            return false
        }
        let box = owner.parentBounds(of: node)
        guard let other = SWFDisplayObject.resolve(context.argument(0).objectValue) else {
            let point = SIMD2(
                Float(owner.runtime.coercion.toNumber(context.argument(0)))
                    * SWFMovieRuntime.twipsPerPixel,
                Float(owner.runtime.coercion.toNumber(context.argument(1)))
                    * SWFMovieRuntime.twipsPerPixel
            )
            return box.contains(point)
        }
        let target = owner.parentBounds(of: other)
        guard !box.isEmpty, !target.isEmpty else {
            return false
        }
        return box.minX <= target.maxX && box.maxX >= target.minX
            && box.minY <= target.maxY && box.maxY >= target.minY
    }

    /// A depth argument clamped into the SWF `UI16` depth domain.
    public static func depthValue(_ number: Double) -> UInt16 {
        guard number.isFinite else {
            return 0
        }
        return UInt16(max(0, min(Double(UInt16.max), number.rounded())))
    }
}
