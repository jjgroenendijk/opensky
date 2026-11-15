// `flash.geom.Rectangle`: the four numbers `x`, `y`, `width`, and `height`, and the
// methods of the Adobe "ActionScript 2.0 Language Reference". Vanilla lists build one
// for a clip's `scale9Grid`.

nonisolated extension SWFMovieRuntime {
    struct RectangleBox: Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        static let empty = RectangleBox(x: 0, y: 0, width: 0, height: 0)
    }
}

nonisolated extension SWFMovieRuntime {
    static func installRectangle(_ runtime: AS2Runtime) -> AS2Object {
        let prototype = AS2Object(prototype: runtime.objectPrototype)
        let constructor = AS2Runtime.constructor(
            runtime, name: "Rectangle", prototype: prototype
        ) { context in
            guard let instance = context.thisObject else { return .undefined }
            try write(
                RectangleBox(
                    x: context.number(0), y: context.number(1),
                    width: context.number(2), height: context.number(3)
                ),
                to: instance
            )
            return .undefined
        }
        installRectangleQueries(runtime, prototype: prototype)
        installRectangleChanges(runtime, prototype: prototype)
        installRectangleEdges(runtime, prototype: prototype)
        return constructor
    }

    /// A new `flash.geom.Rectangle`, for a native that answers with one.
    static func makeRectangle(_ runtime: AS2Runtime, _ frame: RectangleBox) -> AS2Value {
        let geometry = runtime.globalObject.lookup("flash")?.property.value.objectValue?
            .lookup("geom")?.property.value.objectValue
        let constructor = geometry?.lookup("Rectangle")?.property.value.objectValue
        let prototype = constructor?.lookup("prototype")?.property.value.objectValue
        let instance = AS2Object(prototype: prototype ?? runtime.objectPrototype)
        write(frame, to: instance)
        return .object(instance)
    }

    /// `left`, `top`, `right`, and `bottom` read the four numbers.
    private static func installRectangleEdges(_ runtime: AS2Runtime, prototype: AS2Object) {
        let edges: [(String, (RectangleBox) -> Double)] = [
            ("left", { $0.x }), ("top", { $0.y }),
            ("right", { $0.x + $0.width }), ("bottom", { $0.y + $0.height })
        ]
        for (name, edge) in edges {
            let getter = runtime.makeNative { context in
                try .number(edge(rectangle(context.thisObject, context)))
            }
            prototype.addAccessor(name: name, getter: getter, setter: nil)
        }
    }

    private static func installRectangleQueries(_ runtime: AS2Runtime, prototype: AS2Object) {
        AS2Runtime.method(runtime, on: prototype, name: "isEmpty") { context in
            let box = try rectangle(context.thisObject, context)
            return .boolean(box.width <= 0 || box.height <= 0)
        }
        AS2Runtime.method(runtime, on: prototype, name: "contains") { context in
            let box = try rectangle(context.thisObject, context)
            let (px, py) = try (context.number(0), context.number(1))
            return .boolean(
                px >= box.x && px < box.x + box.width && py >= box.y && py < box.y + box.height
            )
        }
        AS2Runtime.method(runtime, on: prototype, name: "equals") { context in
            let lhs = try rectangle(context.thisObject, context)
            let rhs = try rectangle(context.argument(0).objectValue, context)
            return .boolean(lhs == rhs)
        }
        AS2Runtime.method(runtime, on: prototype, name: "intersects") { context in
            let lhs = try rectangle(context.thisObject, context)
            let rhs = try rectangle(context.argument(0).objectValue, context)
            return .boolean(overlap(lhs, rhs) != nil)
        }
        AS2Runtime.method(runtime, on: prototype, name: "toString") { context in
            let box = try rectangle(context.thisObject, context)
            let text = { context.runtime.coercion.toString(.number($0)) }
            return .string(
                "(x=\(text(box.x)), y=\(text(box.y)), w=\(text(box.width)), h=\(text(box.height)))"
            )
        }
    }

    private static func installRectangleChanges(_ runtime: AS2Runtime, prototype: AS2Object) {
        AS2Runtime.method(runtime, on: prototype, name: "clone") { context in
            try make(rectangle(context.thisObject, context), like: context)
        }
        AS2Runtime.method(runtime, on: prototype, name: "intersection") { context in
            let lhs = try rectangle(context.thisObject, context)
            let rhs = try rectangle(context.argument(0).objectValue, context)
            return make(overlap(lhs, rhs) ?? .empty, like: context)
        }
        AS2Runtime.method(runtime, on: prototype, name: "union") { context in
            let lhs = try rectangle(context.thisObject, context)
            let rhs = try rectangle(context.argument(0).objectValue, context)
            return make(union(lhs, rhs), like: context)
        }
        AS2Runtime.method(runtime, on: prototype, name: "offset") { context in
            guard let instance = context.thisObject else { return .undefined }
            var box = try rectangle(instance, context)
            box.x += try context.number(0)
            box.y += try context.number(1)
            write(box, to: instance)
            return .undefined
        }
        AS2Runtime.method(runtime, on: prototype, name: "inflate") { context in
            guard let instance = context.thisObject else { return .undefined }
            var box = try rectangle(instance, context)
            let (dx, dy) = try (context.number(0), context.number(1))
            box.x -= dx
            box.y -= dy
            box.width += 2 * dx
            box.height += 2 * dy
            write(box, to: instance)
            return .undefined
        }
        AS2Runtime.method(runtime, on: prototype, name: "setEmpty") { context in
            guard let instance = context.thisObject else { return .undefined }
            write(.empty, to: instance)
            return .undefined
        }
    }

    /// The shared area, or nil when the two only touch or miss.
    private static func overlap(_ lhs: RectangleBox, _ rhs: RectangleBox) -> RectangleBox? {
        let left = max(lhs.x, rhs.x)
        let top = max(lhs.y, rhs.y)
        let right = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let bottom = min(lhs.y + lhs.height, rhs.y + rhs.height)
        guard right > left, bottom > top else { return nil }
        return RectangleBox(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// An empty rectangle adds nothing, so the union is the other one.
    private static func union(_ lhs: RectangleBox, _ rhs: RectangleBox) -> RectangleBox {
        if lhs.width <= 0 || lhs.height <= 0 {
            return rhs
        }
        if rhs.width <= 0 || rhs.height <= 0 {
            return lhs
        }
        let left = min(lhs.x, rhs.x)
        let top = min(lhs.y, rhs.y)
        let right = max(lhs.x + lhs.width, rhs.x + rhs.width)
        let bottom = max(lhs.y + lhs.height, rhs.y + rhs.height)
        return RectangleBox(x: left, y: top, width: right - left, height: bottom - top)
    }

    private static func make(_ box: RectangleBox, like context: AS2CallContext) -> AS2Value {
        let result = context.runtime.makeObject()
        result.prototype = context.thisObject?.prototype ?? context.runtime.objectPrototype
        write(box, to: result)
        return .object(result)
    }

    private static func write(_ box: RectangleBox, to object: AS2Object) {
        object.assign(.number(box.x), for: "x")
        object.assign(.number(box.y), for: "y")
        object.assign(.number(box.width), for: "width")
        object.assign(.number(box.height), for: "height")
    }

    private static func rectangle(
        _ object: AS2Object?,
        _ context: AS2CallContext
    ) throws -> RectangleBox {
        guard let object else { return .empty }
        let read = { (name: String) throws -> Double in
            try context.interpreter.toNumber(object.lookup(name)?.property.value ?? .undefined)
        }
        return try RectangleBox(
            x: read("x"), y: read("y"), width: read("width"), height: read("height")
        )
    }
}
