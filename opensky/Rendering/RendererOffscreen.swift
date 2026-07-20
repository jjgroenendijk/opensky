// Offscreen render path + sustained bench, split from Renderer.swift
// (file-length limits, RendererSetup.swift precedent). Single frames feed
// deterministic render tests and engine-output screenshots; the sustained
// loop is the milestone fps gate (todo 2.11): every frame runs through the
// FrameStats instrument (todo 2.6) with counter-heap GPU timestamps, so the
// ">30 fps" claim is measured, never eyeballed.

import Metal
import MetalKit
import simd

/// Result of a sustained offscreen render run.
nonisolated struct OffscreenBenchResult {
    /// Wall-clock duration of each synchronous frame in ms — CPU encode +
    /// GPU execution + sync, an upper bound on the pipelined loop's frame
    /// interval.
    let frameMS: [Double]
    /// FrameStats window summary lines flushed during the run (one per 120
    /// frames) — the 2.6 instrument's own view of the same frames.
    let windowSummaries: [String]
    /// CPU time spent sampling + composing + refreshing resident actor palettes.
    let animationMS: [Double]

    init(
        frameMS: [Double],
        windowSummaries: [String],
        animationMS: [Double] = []
    ) {
        self.frameMS = frameMS
        self.windowSummaries = windowSummaries
        self.animationMS = animationMS
    }

    var averageMS: Double {
        frameMS.isEmpty ? 0 : frameMS.reduce(0, +) / Double(frameMS.count)
    }

    /// Nearest-rank percentile of the per-frame times; `percentile` in
    /// 0...100. Empty run -> 0.
    func percentileMS(_ percentile: Double) -> Double {
        guard !frameMS.isEmpty else { return 0 }
        let sorted = frameMS.sorted()
        let rank = Int((percentile / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }

    var animationAverageMS: Double {
        animationMS.isEmpty ? 0 : animationMS.reduce(0, +) / Double(animationMS.count)
    }

    func animationPercentileMS(_ percentile: Double) -> Double {
        Self.percentile(animationMS, percentile: percentile)
    }

    private static func percentile(_ values: [Double], percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((percentile / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }
}

extension Renderer {
    /// Color (shared, CPU-readable) + depth (private) render targets for
    /// offscreen frames.
    private func makeOffscreenTargets(
        width: Int,
        height: Int
    ) throws -> (color: MTLTexture, depth: MTLTexture) {
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: width,
            height: height,
            mipmapped: false
        )
        colorDescriptor.usage = .renderTarget
        colorDescriptor.storageMode = .shared // CPU readback
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = .private
        guard
            let color = device.makeTexture(descriptor: colorDescriptor),
            let depth = device.makeTexture(descriptor: depthDescriptor)
        else { throw RendererError.textureAllocationFailed }
        color.label = "OffscreenColor"
        depth.label = "OffscreenDepth"
        return (color, depth)
    }

    private static func offscreenPassDescriptor(
        color: MTLTexture,
        depth: MTLTexture
    ) -> MTL4RenderPassDescriptor {
        let descriptor = MTL4RenderPassDescriptor()
        descriptor.colorAttachments[0].texture = color
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0, green: 0, blue: 0, alpha: 1
        )
        descriptor.depthAttachment.texture = depth
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .dontCare
        descriptor.depthAttachment.clearDepth = 1
        return descriptor
    }

    private static func offscreenProjection(width: Int, height: Int) -> float4x4 {
        MatrixMath.perspective(
            fovYRadians: MatrixMath.radians(fromDegrees: 65),
            aspectRatio: Float(width) / Float(height),
            nearZ: nearPlane,
            farZ: farPlane
        )
    }

    /// One synchronous frame through the normal slot/event bookkeeping:
    /// drain in-flight frames, encode with GPU timestamps around the pass,
    /// commit, block until the GPU finishes. Feeds FrameStats; returns the
    /// summary line when this frame closed a 120-frame stats window.
    @discardableResult
    private func renderOffscreenFrame(
        descriptor: MTL4RenderPassDescriptor,
        projection: float4x4,
        advanceAnimation: Bool = true
    ) throws -> String? {
        let cpuStart = frameStats.beginFrame()
        if advanceAnimation {
            updateAnimations(deltaTime: 1 / 30)
        }
        endFrameEvent.wait(untilSignaledValue: UInt64(frameIndex - 1), timeoutMS: 2000)
        let slot = frameIndex % Self.maxFramesInFlight
        let allocator = commandAllocators[slot]
        allocator.reset()
        commandBuffer.beginCommandBuffer(allocator: allocator)
        if let heap = timestampHeap {
            commandBuffer.writeTimestamp(counterHeap: heap, index: slot * 2)
        }
        let encoded = encodeScenePass(descriptor: descriptor, slot: slot, projection: projection)
        if let heap = timestampHeap {
            commandBuffer.writeTimestamp(counterHeap: heap, index: slot * 2 + 1)
        }
        commandBuffer.endCommandBuffer()
        guard encoded else { throw RendererError.encoderUnavailable }

        commandQueue.commit([commandBuffer])
        commandQueue.signalEvent(endFrameEvent, value: UInt64(frameIndex))
        let finished = endFrameEvent.wait(
            untilSignaledValue: UInt64(frameIndex),
            timeoutMS: 5000
        )
        frameIndex += 1
        guard finished else { throw RendererError.gpuTimeout }
        purgeRetiredResources()
        // Wait above proved the frame finished -> this slot's pair is valid.
        return frameStats.endFrame(
            cpuStartNS: cpuStart,
            gpuTicks: readTimestampPair(slot: slot)
        )
    }

    /// Renders one frame into an offscreen texture and blocks until the GPU
    /// finishes it — deterministic render tests and engine-output
    /// screenshots (todo 2.9) without drawable/compositor involvement.
    func renderOffscreen(width: Int, height: Int) throws -> MTLTexture {
        let (color, depth) = try makeOffscreenTargets(width: width, height: height)
        residencySet.addAllocations([color, depth])
        residencySet.commit()
        defer {
            residencySet.removeAllocations([color, depth])
            residencySet.commit()
        }
        try renderOffscreenFrame(
            descriptor: Self.offscreenPassDescriptor(color: color, depth: depth),
            projection: Self.offscreenProjection(width: width, height: height)
        )
        return color
    }

    /// Exact animation-time render for deterministic frame-delta gates.
    func renderOffscreen(width: Int, height: Int, animationTime: Float) throws -> MTLTexture {
        self.animationTime = animationTime
        updateAnimations(deltaTime: 0)
        let (color, depth) = try makeOffscreenTargets(width: width, height: height)
        residencySet.addAllocations([color, depth])
        residencySet.commit()
        defer {
            residencySet.removeAllocations([color, depth])
            residencySet.commit()
        }
        try renderOffscreenFrame(
            descriptor: Self.offscreenPassDescriptor(color: color, depth: depth),
            projection: Self.offscreenProjection(width: width, height: height),
            advanceAnimation: false
        )
        return color
    }

    /// Pumps a callback + synchronous frame loop through one reused target.
    /// Streaming tests use this instead of allocating color/depth textures on
    /// every poll tick. Optional pacing happens outside measured frame time,
    /// preventing a busy-spin without hiding main-thread stream work. Returns
    /// timing for every frame through settlement; exhausting `maxFrames`
    /// throws so a stalled build cannot false-pass.
    func pumpOffscreen(
        width: Int,
        height: Int,
        maxFrames: Int,
        minimumFrameInterval: TimeInterval = 0,
        step: () throws -> Bool
    ) throws -> OffscreenBenchResult {
        let (color, depth) = try makeOffscreenTargets(width: width, height: height)
        residencySet.addAllocations([color, depth])
        residencySet.commit()
        defer {
            residencySet.removeAllocations([color, depth])
            residencySet.commit()
        }
        let descriptor = Self.offscreenPassDescriptor(color: color, depth: depth)
        let projection = Self.offscreenProjection(width: width, height: height)
        var frameMS: [Double] = []
        frameMS.reserveCapacity(maxFrames)
        var summaries: [String] = []
        var animationMS: [Double] = []

        for _ in 1 ... maxFrames {
            if minimumFrameInterval > 0 {
                Thread.sleep(forTimeInterval: minimumFrameInterval)
            }
            let start = DispatchTime.now().uptimeNanoseconds
            let settled = try step()
            let summary = try renderOffscreenFrame(
                descriptor: descriptor,
                projection: projection
            )
            if let summary {
                summaries.append(summary)
            }
            frameMS.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            animationMS.append(lastAnimationUpdateMS)
            if settled {
                return OffscreenBenchResult(
                    frameMS: frameMS,
                    windowSummaries: summaries,
                    animationMS: animationMS
                )
            }
        }
        throw RendererError.offscreenPumpTimedOut(maxFrames: maxFrames)
    }

    /// Renders `frames` back-to-back frames into one reused offscreen
    /// target and reports per-frame wall times + FrameStats window
    /// summaries. Synchronous frames make the numbers conservative: each
    /// includes the full CPU-GPU round trip a pipelined loop overlaps.
    func renderOffscreenSustained(
        width: Int,
        height: Int,
        frames: Int
    ) throws -> OffscreenBenchResult {
        let (color, depth) = try makeOffscreenTargets(width: width, height: height)
        residencySet.addAllocations([color, depth])
        residencySet.commit()
        defer {
            residencySet.removeAllocations([color, depth])
            residencySet.commit()
        }
        let descriptor = Self.offscreenPassDescriptor(color: color, depth: depth)
        let projection = Self.offscreenProjection(width: width, height: height)

        var frameMS: [Double] = []
        frameMS.reserveCapacity(frames)
        var summaries: [String] = []
        var animationMS: [Double] = []
        for _ in 0 ..< frames {
            let start = DispatchTime.now().uptimeNanoseconds
            let summary = try renderOffscreenFrame(
                descriptor: descriptor,
                projection: projection
            )
            if let summary {
                summaries.append(summary)
            }
            frameMS.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            animationMS.append(lastAnimationUpdateMS)
        }
        return OffscreenBenchResult(
            frameMS: frameMS,
            windowSummaries: summaries,
            animationMS: animationMS
        )
    }
}
