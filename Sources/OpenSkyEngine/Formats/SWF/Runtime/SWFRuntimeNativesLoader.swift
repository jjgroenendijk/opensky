// The remaining `MovieClip` geometry methods and `MovieClipLoader` (milestone
// 8.3.2 phase 3).
//
// `getBounds`, `localToGlobal`, and `globalToLocal` are what a CLIK component
// uses to place a focus indicator or a tooltip relative to itself, and they are
// exactly the machinery the phase-3 hit test already needs — a node's
// accumulated transform and its bounds box — so they cost almost nothing here.
//
// `MovieClipLoader` loads an external `.swf` or image into a clip. OpenSky
// implements the object and the listener protocol but never loads anything:
// there is no second movie to load, and reaching outside the movie is
// explicitly out of scope (`ActionGetURL` never appears in vanilla either). A
// load reports failure through `onLoadError` on the next tick, which is what
// lets CLIK's icon loader give up cleanly instead of waiting forever. The
// deferral is a logged no-op plus a tally entry, per the binding rule in the
// AS2 scope decision.

import Foundation
import simd

nonisolated extension SWFRuntimeNatives {
    static func installClipGeometry(_ runtime: AS2Runtime, prototype: AS2Object) {
        AS2Natives.method(runtime, on: prototype, name: "getBounds") { context in
            boundsObject(context)
        }
        AS2Natives.method(runtime, on: prototype, name: "localToGlobal") { context in
            try mapPoint(context, toGlobal: true)
        }
        AS2Natives.method(runtime, on: prototype, name: "globalToLocal") { context in
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
        AS2Natives.method(runtime, on: prototype, name: "duplicateMovieClip") { context in
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

    /// `new MovieClipLoader()`: a broadcaster whose `loadClip` always fails.
    static func installMovieClipLoader(_ runtime: AS2Runtime) {
        let prototype = AS2Object(prototype: runtime.objectPrototype)
        AS2Natives.constructor(runtime, name: "MovieClipLoader", prototype: prototype) { context in
            guard let instance = context.thisObject else {
                return .undefined
            }
            installListenerList(context.runtime, on: instance)
            return .undefined
        }
        AS2Natives.method(runtime, on: prototype, name: "loadClip") { context in
            failLoad(context)
        }
        AS2Natives.method(runtime, on: prototype, name: "unloadClip") { _ in .boolean(true) }
        // Deferred failure delivery. Named rather than anonymous because the
        // timer wheel resolves a callback by name at fire time.
        AS2Natives.method(runtime, on: prototype, name: "onDeferredLoadError") { context in
            guard let owner = movieRuntime(context), let loader = context.thisObject else {
                return .undefined
            }
            owner.broadcast(
                "onLoadError", from: loader,
                arguments: [context.argument(0), .string("URLNotFound")]
            )
            return .undefined
        }
        AS2Natives.method(runtime, on: prototype, name: "getProgress") { context in
            let progress = context.runtime.makeObject()
            progress.define(.integer(0), for: "bytesLoaded")
            progress.define(.integer(0), for: "bytesTotal")
            return .object(progress)
        }
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
        _ = owner.timers.add(
            callee: .object(loader),
            method: "onDeferredLoadError",
            arguments: [target],
            period: 1,
            repeats: false
        )
        return .boolean(false)
    }
}

nonisolated extension SWFRuntimeNatives {
    /// `flash.geom.Point` and the deprecated global `random(n)`. Both are Flash
    /// player built-ins the vanilla level meter in `tweenmenu.swf` leans on: a
    /// probe measured 930 `Point` and 620 `add` misses in a single menu once its
    /// meter started animating.
    static func installGeometry(_ runtime: AS2Runtime) {
        let prototype = AS2Object(prototype: runtime.objectPrototype)
        let constructor = AS2Natives.constructor(
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
        let flash = runtime.globalObject.lookup("flash")?.property.value.objectValue
            ?? runtime.makeObject()
        flash.define(.object(geometry), for: "geom", flags: .dontEnumerate)
        runtime.globalObject.define(.object(flash), for: "flash", flags: .dontEnumerate)
        AS2Natives.method(runtime, on: runtime.globalObject, name: "random") { context in
            let bound = try context.number(0)
            guard bound.isFinite, bound >= 1 else {
                return .integer(0)
            }
            return .integer(Int(context.runtime.nextRandom() * bound.rounded(.down)))
        }
    }

    private static func installPointMethods(_ runtime: AS2Runtime, prototype: AS2Object) {
        AS2Natives.method(runtime, on: prototype, name: "add") { context in
            try combine(context, sign: 1)
        }
        AS2Natives.method(runtime, on: prototype, name: "subtract") { context in
            try combine(context, sign: -1)
        }
        AS2Natives.method(runtime, on: prototype, name: "clone") { context in
            try combine(context, sign: 0)
        }
        AS2Natives.method(runtime, on: prototype, name: "toString") { context in
            let point = try coordinates(context.thisObject, context)
            return .string("(x=\(point.0), y=\(point.1))")
        }
        AS2Natives.method(runtime, on: prototype, name: "equals") { context in
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
