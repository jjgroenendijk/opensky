// A material's own depth test, depth write, and decal bias, from its shader flags.
// The scene lists set them per group while the frame honours them
// (docs/formats/nif-materials.md, "Draw state").

@preconcurrency @unsafe import Metal
import OpenSkyFormatsCore
import OpenSkyRenderResources
import OpenSkyShaderTypes

/// Whether the list that draws may write depth at all. The blended list may not.
enum MaterialDepthMode: Sendable {
    case writes
    case readOnly
}

/// One depth state per test and write pair, all with the scene's `.less` compare. The
/// skin variants also set the skin stencil bit, which keeps skin decals on the body.
struct MaterialDepthStates: Sendable {
    /// The stencil bit a skinned mesh sets; the SWF clip counts use the bits below it.
    static let skinStencilBit: UInt32 = 0x80

    private let states: [any MTLDepthStencilState]

    init(device: any MTLDevice) throws {
        states = try [false, true].flatMap { skin in
            try [false, true].flatMap { test in
                try [false, true].map { write in
                    try Self.make(device: device, test: test, write: write, skin: skin)
                }
            }
        }
    }

    private static func make(
        device: any MTLDevice,
        test: Bool,
        write: Bool,
        skin: Bool
    ) throws -> any MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.label = "MaterialDepth test \(test) write \(write) skin \(skin)"
        descriptor.depthCompareFunction = test ? .less : .always
        descriptor.isDepthWriteEnabled = write
        if skin {
            let stencil = MTLStencilDescriptor()
            stencil.stencilCompareFunction = .always
            stencil.depthStencilPassOperation = .replace
            stencil.writeMask = skinStencilBit
            descriptor.frontFaceStencil = stencil
            descriptor.backFaceStencil = stencil
        }
        guard let state = device.makeDepthStencilState(descriptor: descriptor) else {
            throw RendererError.depthStateAllocationFailed
        }
        return state
    }

    func state(test: Bool, write: Bool, skin: Bool = false) -> any MTLDepthStencilState {
        states[(skin ? 4 : 0) + (test ? 2 : 0) + (write ? 1 : 0)]
    }
}

extension Renderer {
    /// The decal pass uses the same pull toward the eye.
    static let decalDepthBias: (constant: Float, slope: Float) = (-1, -1)

    /// A skinned mesh that writes depth marks its pixels for the skin decals.
    func applyDrawState(
        of material: RenderMaterial,
        mode: MaterialDepthMode,
        skinned: Bool,
        state: ScenePassState
    ) {
        let honoured = shadingTerms.contains(.materialDrawState)
        let flags = honoured ? material.drawState : .standard
        let write = flags.depthWrite && mode == .writes
        let marksSkin = skinned && write
        if marksSkin {
            state.encoder.setStencilReferenceValue(MaterialDepthStates.skinStencilBit)
        }
        state.encoder.setDepthStencilState(
            materialDepthStates.state(test: flags.depthTest, write: write, skin: marksSkin)
        )
        let bias = flags.decal ? Self.decalDepthBias : (constant: 0, slope: 0)
        state.encoder.setDepthBias(bias.constant, slopeScale: bias.slope, clamp: 0)
    }

    /// Back to the scene depth state and no bias, once a list has drawn.
    func endMaterialDrawState(state: inout ScenePassState) {
        state.materialDepth = nil
        state.encoder.setDepthStencilState(depthState)
        state.encoder.setDepthBias(0, slopeScale: 0, clamp: 0)
    }
}
