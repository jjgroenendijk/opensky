// Developer > Rendering Performance: one section per GPU performance feature, each
// with its switch and the numbers that show its effect.

import AppKit
import OpenSkyRendering

final class RenderingPerformancePanelViewController: InspectorPanelViewController {
    let renderTargetsSection = RenderTargetsSection()
    let pipelineCacheSection = PipelineCacheSection()
    let gpuCullingSection = GPUCullingSection()
    let roomCullingSection = RoomCullingSection()
    let textureStreamingSection = TextureStreamingSection()
    let rayTracedShadowsSection = RayTracedShadowsSection()
    let upscalingSection = UpscalingSection()
    let frameInterpolationSection = FrameInterpolationSection()
    let meshShaderGrassSection = MeshShaderGrassSection()

    weak var provider: (any RenderPerformanceControlProviding)? {
        didSet {
            renderTargetsSection.provider = provider
            pipelineCacheSection.provider = provider
            gpuCullingSection.provider = provider
            roomCullingSection.provider = provider
            textureStreamingSection.provider = provider
            rayTracedShadowsSection.provider = provider
            upscalingSection.provider = provider
            frameInterpolationSection.provider = provider
            meshShaderGrassSection.provider = provider
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [
            renderTargetsSection, pipelineCacheSection, gpuCullingSection,
            roomCullingSection, textureStreamingSection, rayTracedShadowsSection, upscalingSection,
            frameInterpolationSection, meshShaderGrassSection
        ]
    }
}
