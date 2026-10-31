// `dds <key> --out <folder>`: uploads the texture through the engine's texture
// library the way an effect shape asks for its source, prints what reached the GPU,
// and writes the chosen level back out as PNGs, one per volume slice.

import Foundation
import Metal
import OpenSkyCLIArguments
import OpenSkyFormatsMesh
import OpenSkyRendering
import OpenSkyRenderResources

extension AssetCommand {
    static func writeUploadedDDS(
        context: CLIContext, arguments: DDSArguments, file: DDSFile, out: String
    ) throws {
        guard arguments.level < file.mipCount else {
            throw CLIError
                .usage("--level \(arguments.level) is past the last level \(file.mipCount - 1)")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw CLIError.failure("no Metal GPU")
        }
        let library = try TextureLibrary(fileSystem: context.makeFileSystem(), device: device)
        let texture = library.texture(key: arguments.asset.path, usage: .effectSource)
        let isPlaceholder = texture.label?.hasPrefix("placeholder-") ?? true
        print("[INFO] uploaded: \(typeName(texture.textureType)) "
            + "\(texture.width)x\(texture.height)x\(texture.depth), "
            + "\(texture.mipmapLevelCount) levels, pixel format \(texture.pixelFormat.rawValue), "
            + "placeholder: \(isPlaceholder ? "yes" : "no")")
        guard !isPlaceholder else {
            throw CLIError.failure("\(arguments.asset.path) loaded as a placeholder")
        }
        let folder = URL(filePath: out, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let images = try texture.textureType == .type3D
            ? TextureReadback.volumeSlices(of: texture, level: arguments.level)
            : [TextureReadback(
                device: device, library: Renderer.makeBundledShaderLibrary(device: device)
            ).pixels(of: texture, level: arguments.level)]
        for (index, pixels) in images.enumerated() {
            let name = images.count > 1
                ? String(format: "level-%d-slice-%03d.png", arguments.level, index)
                : "level-\(arguments.level).png"
            guard let image = pixels.cgImage() else {
                throw CLIError.failure("cannot make an image of \(name)")
            }
            try FrameScreenshot.write(image: image, to: folder.appending(path: name))
        }
        print("[INFO] wrote \(images.count) PNG(s) to \(folder.path(percentEncoded: false))")
    }

    private static func typeName(_ type: MTLTextureType) -> String {
        switch type {
        case .type3D: "3D"
        case .typeCube: "cube"
        case .type2D: "2D"
        default: "type \(type.rawValue)"
        }
    }
}
