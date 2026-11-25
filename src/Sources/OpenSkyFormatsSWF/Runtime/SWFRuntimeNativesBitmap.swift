// `flash.display.BitmapData`: only what vanilla menus use. `loadBitmap(name)` answers a
// bitmap the movie exports under `name`, such as the key art "E.png" in the help text,
// with its `width` and `height` in pixels. The pixels stay with the renderer.

nonisolated extension SWFMovieRuntime {
    static func installBitmapData(_ runtime: AS2Runtime, movie: SWFMovie) {
        BitmapNatives.installBitmapData(runtime, movie: movie)
    }
}

extension SWFMovieRuntime {
    /// Installs the `BitmapData` class.
    nonisolated enum BitmapNatives {
        static func installBitmapData(_ runtime: AS2Runtime, movie: SWFMovie) {
            var sizes: [String: (width: Int, height: Int)] = [:]
            for (name, id) in movie.exportedNames {
                if let bitmap = movie.bitmap(id) {
                    sizes[name] = (bitmap.width, bitmap.height)
                }
            }
            let prototype = AS2Object(prototype: runtime.objectPrototype)
            let constructor = AS2Runtime.constructor(
                runtime, name: "BitmapData", prototype: prototype
            ) { context in
                guard let instance = context.thisObject else { return .undefined }
                try instance.assign(.number(context.number(0)), for: "width")
                try instance.assign(.number(context.number(1)), for: "height")
                return .undefined
            }
            AS2Runtime.method(runtime, on: constructor, name: "loadBitmap") { context in
                guard let size = try sizes[context.string(0)] else { return .undefined }
                let bitmap = AS2Object(prototype: prototype)
                bitmap.assign(.integer(size.width), for: "width")
                bitmap.assign(.integer(size.height), for: "height")
                return .object(bitmap)
            }
            let display = runtime.makeObject()
            display.define(.object(constructor), for: "BitmapData", flags: .dontEnumerate)
            let flash = runtime.globalObject.lookup("flash")?.property.value.objectValue
                ?? runtime.makeObject()
            flash.define(.object(display), for: "display", flags: .dontEnumerate)
            runtime.globalObject.define(.object(flash), for: "flash", flags: .dontEnumerate)
        }
    }
}
