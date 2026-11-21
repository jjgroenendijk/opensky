// The static half of a movie's GPU package, built once per movie: tessellated shapes
// with their fill-run table, bitmap textures, and the gradient ramp atlas.

public import Metal
public import OpenSkyFormatsSWF
import OpenSkyRenderResources
public import OpenSkyShaderTypes
import simd

nonisolated extension SWFMovieResources {
    /// CPU-side shape build: tessellates every dictionary shape into one shared
    /// vertex list and resolves its fills, collecting gradient rows as it goes.
    public struct ShapeBuilder {
        public let scene: SWFMovieScene
        public var vertices: [SWFVertex] = []
        public var shapes: [UInt16: SWFMovieResources.ShapeEntry] = [:]
        public var gradientRows: [SWFGradient] = []
        public var skipped = 0
        private let shapeCache = SWFShapeCache()

        /// Gradient square half-extent in twips (spec chapter 7, p. 134).
        private static let gradientSquareHalfExtent: Float = 16384

        public mutating func buildShapes() {
            let movie = scene.movie
            for id in movie.characters.keys.sorted() {
                guard case let .shape(shape) = movie.characters[id] else { continue }
                let mesh = shapeCache.mesh(for: shape)
                let start = vertices.count
                vertices.append(contentsOf: mesh.vertices.map {
                    SWFVertex(position: $0, uv: .zero)
                })
                var runs: [SWFMovieResources.RunEntry] = []
                for run in mesh.runs {
                    guard
                        run.fillStyleIndex >= 1,
                        run.fillStyleIndex <= shape.fillStyles.count,
                        let fill = resolveFill(shape.fillStyles[run.fillStyleIndex - 1])
                    else {
                        skipped += 1
                        continue
                    }
                    runs.append(SWFMovieResources.RunEntry(
                        vertexStart: start + run.triangleRange.lowerBound * 3,
                        vertexCount: run.triangleRange.count * 3,
                        fill: fill
                    ))
                }
                for run in mesh.strokeRuns {
                    let style = shape.lineStyles[run.lineStyleIndex - 1]
                    guard let fill = resolveFill(style.fill ?? .solid(style.color)) else {
                        skipped += 1
                        continue
                    }
                    runs.append(SWFMovieResources.RunEntry(
                        vertexStart: start + run.triangleRange.lowerBound * 3,
                        vertexCount: run.triangleRange.count * 3,
                        fill: fill
                    ))
                }
                shapes[id] = SWFMovieResources.ShapeEntry(
                    vertexStart: start, vertexCount: mesh.vertices.count, runs: runs
                )
            }
        }

        /// Resolves one FILLSTYLE to renderer terms; nil for degenerate fill
        /// matrices (counted as skipped).
        private mutating func resolveFill(_ style: SWFFillStyle) -> SWFMovieResources
            .ResolvedFill?
        {
            switch style {
            case let .solid(color):
                return .solid(SWFMovieResources.TextPlanner.straightColor(color))
            case let .bitmap(characterId, matrix, tiled, _):
                guard
                    let bitmap = scene.movie.bitmap(characterId),
                    bitmap.width > 0, bitmap.height > 0,
                    let inverse = SWFTransform(matrix: matrix).inverted else { return nil }
                let toUV = SWFTransform(
                    scaleX: 1 / Float(bitmap.width), scaleY: 1 / Float(bitmap.height)
                ).concatenating(inverse)
                return .bitmap(characterId: characterId, toUV: toUV, tiled: tiled)
            case let .linearGradient(matrix, gradient),
                 let .radialGradient(matrix, gradient),
                 let .focalRadialGradient(matrix, gradient):
                guard let inverse = SWFTransform(matrix: matrix).inverted else { return nil }
                let toSquare = SWFTransform(
                    scaleX: 1 / Self.gradientSquareHalfExtent,
                    scaleY: 1 / Self.gradientSquareHalfExtent
                ).concatenating(inverse)
                let radial = if case .linearGradient = style {
                    false
                } else {
                    true
                }
                gradientRows.append(gradient)
                return .gradient(
                    row: gradientRows.count - 1,
                    toSquare: toSquare,
                    radial: radial,
                    focal: gradient.focalPoint,
                    spread: Self.spread(gradient.spreadMode)
                )
            }
        }

        private static func spread(_ mode: SWFGradient.SpreadMode) -> SWFGradientSpread {
            switch mode {
            case .pad, .reserved: .pad
            case .reflect: .reflect
            case .repeating: .repeat
            }
        }
    }
}

nonisolated extension SWFMovieResources {
    /// Bitmap and gradient texture uploads.
    public enum Textures: Sendable {
        public static func makeBitmaps(
            device: any MTLDevice,
            movie: SWFMovie
        ) throws -> [UInt16: SWFMovieResources.BitmapEntry] {
            var result: [UInt16: SWFMovieResources.BitmapEntry] = [:]
            for id in movie.characters.keys.sorted() {
                guard
                    case let .bitmap(bitmap) = movie.characters[id],
                    bitmap.width > 0, bitmap.height > 0 else { continue }
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .rgba8Unorm,
                    width: bitmap.width,
                    height: bitmap.height,
                    mipmapped: false
                )
                descriptor.usage = .shaderRead
                descriptor.storageMode = .shared
                guard let texture = device.makeTexture(descriptor: descriptor) else {
                    throw RendererError.textureAllocationFailed
                }
                texture.label = "SWFBitmap\(id)"
                unsafe bitmap.pixels.withUnsafeBytes { bytes in
                    guard let base = bytes.baseAddress else { return }
                    unsafe texture.replace(
                        region: MTLRegionMake2D(0, 0, bitmap.width, bitmap.height),
                        mipmapLevel: 0,
                        withBytes: base,
                        bytesPerRow: bitmap.width * 4
                    )
                }
                result[id] = SWFMovieResources.BitmapEntry(
                    texture: texture, premultiplied: bitmap.premultipliedAlpha
                )
            }
            return result
        }

        /// One 256-texel row per gradient fill (`SWFGradient.rampColors`).
        public static func makeGradientRamp(
            device: any MTLDevice,
            rows: [SWFGradient]
        ) throws -> any MTLTexture? {
            guard !rows.isEmpty else { return nil }
            let width = 256
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: width, height: rows.count, mipmapped: false
            )
            descriptor.usage = .shaderRead
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw RendererError.textureAllocationFailed
            }
            texture.label = "SWFGradientRamp"
            var pixels = [UInt8](repeating: 0, count: width * rows.count * 4)
            for (row, gradient) in rows.enumerated() {
                writeRampRow(gradient, into: &pixels, row: row, width: width)
            }
            pixels.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                unsafe texture.replace(
                    region: MTLRegionMake2D(0, 0, width, rows.count),
                    mipmapLevel: 0,
                    withBytes: base,
                    bytesPerRow: width * 4
                )
            }
            return texture
        }

        private static func writeRampRow(
            _ gradient: SWFGradient,
            into pixels: inout [UInt8],
            row: Int,
            width: Int
        ) {
            for (texel, color) in gradient.rampColors(width: width).enumerated() {
                let base = (row * width + texel) * 4
                pixels[base] = color.red
                pixels[base + 1] = color.green
                pixels[base + 2] = color.blue
                pixels[base + 3] = color.alpha
            }
        }
    }
}
