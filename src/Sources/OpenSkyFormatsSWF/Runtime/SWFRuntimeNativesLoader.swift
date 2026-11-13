// The `MovieClip` geometry methods and `MovieClipLoader`. The loader shows an
// engine picture for an `img://` URL with an image slot, and puts a merged movie in
// a clip for a `.swf` name. Anything else reports `onLoadError` on the next tick, so
// CLIK's icon loader gives up cleanly.

import Foundation
import simd

nonisolated extension SWFMovieRuntime {
    static func installClipGeometry(_ runtime: AS2Runtime, prototype: AS2Object) {
        AS2Runtime.method(runtime, on: prototype, name: "getBounds") { context in
            boundsObject(context)
        }
        AS2Runtime.method(runtime, on: prototype, name: "localToGlobal") { context in
            try mapPoint(context, toGlobal: true)
        }
        AS2Runtime.method(runtime, on: prototype, name: "globalToLocal") { context in
            try mapPoint(context, toGlobal: false)
        }
    }

    /// `getBounds([target])`: the node's box in the target's space, in pixels.
    /// An absent or unresolvable target means the node's own parent, which is
    /// what Flash defaults to.
    private static func boundsObject(_ context: AS2CallContext) -> AS2Value {
        guard let owner = movieRuntime(context), let node = node(context) else {
            return .undefined
        }
        var box = owner.parentBounds(of: node)
        if
            let target = SWFDisplayObject.resolve(context.argument(0).objectValue),
            let parent = node.parent,
            let toStage = owner.transform(of: parent),
            let intoTarget = owner.transform(of: target)?.inverted
        {
            box = box.transformed(by: intoTarget.concatenating(toStage))
        }
        let result = context.runtime.makeObject()
        let scale = SWFMovieRuntime.twipsPerPixel
        result.define(.number(Double(box.minX / scale)), for: "xMin")
        result.define(.number(Double(box.maxX / scale)), for: "xMax")
        result.define(.number(Double(box.minY / scale)), for: "yMin")
        result.define(.number(Double(box.maxY / scale)), for: "yMax")
        return .object(result)
    }

    /// `localToGlobal(point)` / `globalToLocal(point)`: both mutate the point
    /// object in place and return nothing, which is the ActionScript contract.
    private static func mapPoint(_ context: AS2CallContext, toGlobal: Bool) throws -> AS2Value {
        guard
            let owner = movieRuntime(context), let node = node(context),
            let point = context.argument(0).objectValue,
            let transform = owner.transform(of: node)
        else {
            return .undefined
        }
        let scale = SWFMovieRuntime.twipsPerPixel
        let local = try SIMD2(
            Float(context.interpreter.toNumber(point.lookup("x")?.property.value ?? .undefined))
                * scale,
            Float(context.interpreter.toNumber(point.lookup("y")?.property.value ?? .undefined))
                * scale
        )
        guard let mapping = toGlobal ? transform : transform.inverted else {
            return .undefined
        }
        let mapped = mapping.apply(local)
        point.assign(.number(Double(mapped.x / scale)), for: "x")
        point.assign(.number(Double(mapped.y / scale)), for: "y")
        return .undefined
    }

    /// `duplicateMovieClip(name, depth, [initObject])`: another instance of the
    /// same character in the same parent, which is how a vanilla level meter
    /// builds its row of dots.
    static func installDuplicate(_ runtime: AS2Runtime, prototype: AS2Object) {
        AS2Runtime.method(runtime, on: prototype, name: "duplicateMovieClip") { context in
            guard
                let owner = movieRuntime(context), let node = node(context),
                let parent = node.parent, let characterId = node.characterId,
                let copy = owner.makeDisplayObject(characterId: characterId)
            else {
                return .undefined
            }
            copy.name = try context.string(0)
            copy.matrix = node.matrix
            copy.colorTransform = node.colorTransform
            try parent.addChild(copy, atDepth: depthValue(context.number(1)))
            if let initializer = context.argument(2).objectValue {
                for name in initializer.ownPropertyNames {
                    copy.object.assign(
                        initializer.ownProperty(name)?.value ?? .undefined, for: name
                    )
                }
            }
            owner.bringUp(copy)
            owner.markDirty()
            return .object(copy.object)
        }
    }

    // MARK: - MovieClipLoader

    /// `new MovieClipLoader()`: a broadcaster whose `loadClip` shows image slots and
    /// merged movies.
    public static func installMovieClipLoader(_ runtime: AS2Runtime) {
        let prototype = AS2Object(prototype: runtime.objectPrototype)
        AS2Runtime.constructor(runtime, name: "MovieClipLoader", prototype: prototype) { context in
            guard let instance = context.thisObject else {
                return .undefined
            }
            installListenerList(context.runtime, on: instance)
            return .undefined
        }
        AS2Runtime.method(runtime, on: prototype, name: "loadClip") { context in
            loadImage(context) ?? loadMovie(context) ?? failLoad(context)
        }
        AS2Runtime.method(runtime, on: prototype, name: "onDeferredLoadInit") { context in
            guard let owner = movieRuntime(context), let loader = context.thisObject else {
                return .undefined
            }
            for event in ["onLoadStart", "onLoadComplete", "onLoadInit"] {
                owner.broadcast(event, from: loader, arguments: [context.argument(0)])
            }
            return .undefined
        }
        AS2Runtime.method(runtime, on: prototype, name: "unloadClip") { _ in .boolean(true) }
        // Deferred failure delivery. Named rather than anonymous because the
        // timer wheel resolves a callback by name at fire time.
        AS2Runtime.method(runtime, on: prototype, name: "onDeferredLoadError") { context in
            guard let owner = movieRuntime(context), let loader = context.thisObject else {
                return .undefined
            }
            owner.broadcast(
                "onLoadError", from: loader,
                arguments: [context.argument(0), .string("URLNotFound")]
            )
            return .undefined
        }
        AS2Runtime.method(runtime, on: prototype, name: "getProgress") { context in
            let progress = context.runtime.makeObject()
            progress.define(.integer(0), for: "bytesLoaded")
            progress.define(.integer(0), for: "bytesTotal")
            return .object(progress)
        }
    }

    static let imageScheme = "img://"

    /// Puts the slot's picture at depth 0 of the target clip, then reports the
    /// load on the next tick, as Flash does. Nil when the URL names no slot.
    private static func loadImage(_ context: AS2CallContext) -> AS2Value? {
        guard
            let owner = movieRuntime(context), let loader = context.thisObject,
            case let .string(url) = context.argument(0), url.hasPrefix(imageScheme),
            let shape = owner.movie.imageShape(named: String(url.dropFirst(imageScheme.count))),
            let target = SWFDisplayObject.resolve(context.argument(1).objectValue),
            let picture = owner.makeDisplayObject(characterId: shape)
        else { return nil }
        target.addChild(picture, atDepth: 0)
        owner.markDirty()
        owner.timers.addOnce("onDeferredLoadInit", on: loader, arguments: [context.argument(1)])
        return .boolean(true)
    }

    /// Turns the target clip into the loaded movie's root, as Flash does: a new clip
    /// of the movie's root timeline takes the target's place, name, and transform.
    /// Its DoInitAction blocks run once, before its first frame. Nil when the name
    /// is no merged movie.
    private static func loadMovie(_ context: AS2CallContext) -> AS2Value? {
        guard
            let owner = movieRuntime(context), let loader = context.thisObject,
            case let .string(url) = context.argument(0),
            let loadable = owner.movie.loadedSprite(named: url),
            let target = SWFDisplayObject.resolve(context.argument(1).objectValue),
            let parent = target.parent,
            let node = owner.makeDisplayObject(characterId: loadable.spriteId)
        else { return nil }
        node.name = target.name
        node.matrix = target.matrix
        node.colorTransform = target.colorTransform
        node.isVisible = target.isVisible
        _ = parent.removeChild(atDepth: target.depth)
        parent.addChild(node, atDepth: target.depth)
        if owner.startedLoadables.insert(loadable.spriteId).inserted {
            for initAction in loadable.initActions {
                AS2Interpreter.execute(in: owner.runtime, initAction, target: node.object)
            }
        }
        owner.bringUp(node)
        owner.markDirty()
        owner.timers.addOnce("onDeferredLoadInit", on: loader, arguments: [.object(node.object)])
        return .boolean(true)
    }

    /// Reports the failure the listeners are waiting for. It is queued on the
    /// timer wheel rather than sent inline, because Flash delivers it
    /// asynchronously and a component that calls `loadClip` from its own
    /// constructor must not be re-entered mid-construction.
    private static func failLoad(_ context: AS2CallContext) -> AS2Value {
        guard let owner = movieRuntime(context), let loader = context.thisObject else {
            return .boolean(false)
        }
        owner.runtime.noteMissing("MovieClipLoader.loadClip")
        let target = context.argument(1)
        owner.timers.addOnce("onDeferredLoadError", on: loader, arguments: [target])
        return .boolean(false)
    }
}

nonisolated extension SWFMovieRuntime {
    /// `flash.geom.Point` and the deprecated global `random(n)`. Both are Flash
    /// player built-ins the vanilla level meter in `tweenmenu.swf` leans on: a
    /// probe measured 930 `Point` and 620 `add` misses in a single menu once its
    /// meter started animating.
    public static func installGeometry(_ runtime: AS2Runtime) {
        let prototype = AS2Object(prototype: runtime.objectPrototype)
        let constructor = AS2Runtime.constructor(
            runtime, name: "Point", prototype: prototype
        ) { context in
            guard let instance = context.thisObject else {
                return .undefined
            }
            try instance.assign(.number(context.number(0)), for: "x")
            try instance.assign(.number(context.number(1)), for: "y")
            return .undefined
        }
        installPointMethods(runtime, prototype: prototype)
        let geometry = runtime.makeObject()
        geometry.define(.object(constructor), for: "Point", flags: .dontEnumerate)
        geometry.define(
            .object(installRectangle(runtime)), for: "Rectangle", flags: .dontEnumerate
        )
        let flash = runtime.globalObject.lookup("flash")?.property.value.objectValue
            ?? runtime.makeObject()
        flash.define(.object(geometry), for: "geom", flags: .dontEnumerate)
        runtime.globalObject.define(.object(flash), for: "flash", flags: .dontEnumerate)
        AS2Runtime.method(runtime, on: runtime.globalObject, name: "random") { context in
            let bound = try context.number(0)
            guard bound.isFinite, bound >= 1 else {
                return .integer(0)
            }
            return .integer(Int(context.runtime.nextRandom() * bound.rounded(.down)))
        }
    }

    private static func installPointMethods(_ runtime: AS2Runtime, prototype: AS2Object) {
        AS2Runtime.method(runtime, on: prototype, name: "add") { context in
            try combine(context, sign: 1)
        }
        AS2Runtime.method(runtime, on: prototype, name: "subtract") { context in
            try combine(context, sign: -1)
        }
        AS2Runtime.method(runtime, on: prototype, name: "clone") { context in
            try combine(context, sign: 0)
        }
        AS2Runtime.method(runtime, on: prototype, name: "toString") { context in
            let point = try coordinates(context.thisObject, context)
            let text = { context.runtime.coercion.toString(.number($0)) }
            return .string("(x=\(text(point.0)), y=\(text(point.1)))")
        }
        AS2Runtime.method(runtime, on: prototype, name: "equals") { context in
            let lhs = try coordinates(context.thisObject, context)
            let rhs = try coordinates(context.argument(0).objectValue, context)
            return .boolean(lhs == rhs)
        }
    }

    /// `add`, `subtract`, and `clone` all build a new `Point`; `sign` is 0 for
    /// the copy.
    private static func combine(_ context: AS2CallContext, sign: Double) throws -> AS2Value {
        let base = try coordinates(context.thisObject, context)
        let other = sign == 0 ? (0, 0) : try coordinates(context.argument(0).objectValue, context)
        let result = context.runtime.makeObject()
        result.prototype = context.thisObject?.prototype ?? context.runtime.objectPrototype
        result.assign(.number(base.0 + sign * other.0), for: "x")
        result.assign(.number(base.1 + sign * other.1), for: "y")
        return .object(result)
    }

    private static func coordinates(
        _ object: AS2Object?,
        _ context: AS2CallContext
    ) throws -> (Double, Double) {
        guard let object else {
            return (0, 0)
        }
        return try (
            context.interpreter.toNumber(object.lookup("x")?.property.value ?? .undefined),
            context.interpreter.toNumber(object.lookup("y")?.property.value ?? .undefined)
        )
    }
}
