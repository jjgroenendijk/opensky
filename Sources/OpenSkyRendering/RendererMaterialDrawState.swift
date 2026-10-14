// A material's own depth test, depth write, and decal bias, from its shader flags.
// The scene lists set them per group while the frame honours them
// (docs/formats/nif-materials.md, "Draw state").

@preconcurrency import Metal
import OpenSkyFormatsCore
import OpenSkyShaderTypes

/// Whether the list that draws may write depth at all. The blended list may not.
enum MaterialDepthMode: Sendable {
    case writes
    case readOnly
}

/// One depth state per test and write pair, all with the scene's `.less` compare.
struct MaterialDepthStates: Sendable {
    private let states: [MTLDepthStencilState]

    init(device: MTLDevice) throws {
        states = try [false, true].flatMap { test in
            try [false, true].map { write in
                let descriptor = MTLDepthStencilDescriptor()
                descriptor.label = "MaterialDepth test \(test) write \(write)"
                descriptor.depthCompareFunction = test ? .less : .always
                descriptor.isDepthWriteEnabled = write
                guard let state = device.makeDepthStencilState(descriptor: descriptor) else {
                    throw RendererError.depthStateAllocationFailed
                }
                return state
            }
        }
    }

    func state(test: Bool, write: Bool) -> MTLDepthStencilState {
        states[(test ? 2 : 0) + (write ? 1 : 0)]
    }
}

extension Renderer {
    /// The decal pass uses the same pull toward the eye.
    static let decalDepthBias: (constant: Float, slope: Float) = (-1, -1)

    func applyDrawState(
        of material: RenderMaterial,
        mode: MaterialDepthMode,
        state: ScenePassState
    ) {
        let honoured = shadingTerms.contains(.materialDrawState)
        let flags = honoured ? material.drawState : .standard
        let write = flags.depthWrite && mode == .writes
        state.encoder.setDepthStencilState(
            materialDepthStates.state(test: flags.depthTest, write: write)
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
