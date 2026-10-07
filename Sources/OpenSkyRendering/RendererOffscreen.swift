// Offscreen render path and sustained bench. Single frames feed render tests and
// screenshots; the sustained loop is the fps gate, timed by `FrameStats` with
// commit-feedback GPU spans, so the fps claim is measured.

import Metal
import MetalKit
import OpenSkyFormatsCore
import simd

/// Result of a sustained offscreen render run.
nonisolated public struct OffscreenBenchResult: Sendable {
    /// Wall-clock duration of each synchronous frame in ms — CPU encode +
    /// GPU execution + sync, an upper bound on the pipelined loop's frame
    /// interval.
    public let frameMS: [Double]
    /// FrameStats window summary lines flushed during the run (one per 120
    /// frames) — the 2.6 instrument's own view of the same frames.
    public let windowSummaries: [String]
    /// CPU time spent sampling + composing + refreshing resident actor palettes.
    public let animationMS: [Double]
    /// CPU time of `encodeShadowPass` per frame: the sun-shadow budget metric. Mirrors
    /// `animationMS`; empty when never sampled.
    public let shadowMS: [Double]
    /// CPU time of the audio update per frame: the audio budget metric. Mirrors
    /// `animationMS`; zeros without an audio engine, empty when never sampled.
    public let audioUpdateMS: [Double]
    /// CPU wall time of the world-simulation callback per frame. The callback
    /// owns the Papyrus VM advance; every entry is zero when none is attached.
    public let scriptUpdateMS: [Double]
    /// GPU time per frame from commit feedback. Feedback can arrive after the
    /// run ends, so this may hold one entry fewer than `frameMS`.
    public let gpuMS: [Double]

    public init(
        frameMS: [Double],
        windowSummaries: [String],
        animationMS: [Double] = [],
        shadowMS: [Double] = [],
        audioUpdateMS: [Double] = [],
        scriptUpdateMS: [Double] = [],
        gpuMS: [Double] = []
    ) {
        self.frameMS = frameMS
        self.windowSummaries = windowSummaries
        self.animationMS = animationMS
        self.shadowMS = shadowMS
        self.audioUpdateMS = audioUpdateMS
        self.scriptUpdateMS = scriptUpdateMS
        self.gpuMS = gpuMS
    }

    public var averageMS: Double {
        frameMS.isEmpty ? 0 : frameMS.reduce(0, +) / Double(frameMS.count)
    }

    /// Nearest-rank percentile of the per-frame times; `percentile` in
    /// 0...100. Empty run -> 0.
    public func percentileMS(_ percentile: Double) -> Double {
        guard !frameMS.isEmpty else { return 0 }
        let sorted = frameMS.sorted()
        let rank = Int((percentile / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }

    public var animationAverageMS: Double {
        animationMS.isEmpty ? 0 : animationMS.reduce(0, +) / Double(animationMS.count)
    }

    public func animationPercentileMS(_ percentile: Double) -> Double {
        Self.percentile(animationMS, percentile: percentile)
    }

    public var shadowAverageMS: Double {
        shadowMS.isEmpty ? 0 : shadowMS.reduce(0, +) / Double(shadowMS.count)
    }

    public func shadowPercentileMS(_ percentile: Double) -> Double {
        Self.percentile(shadowMS, percentile: percentile)
    }

    public var audioUpdateAverageMS: Double {
        audioUpdateMS.isEmpty ? 0 : audioUpdateMS.reduce(0, +) / Double(audioUpdateMS.count)
    }

    public func audioUpdatePercentileMS(_ percentile: Double) -> Double {
        Self.percentile(audioUpdateMS, percentile: percentile)
    }

    public var scriptUpdateAverageMS: Double {
        scriptUpdateMS.isEmpty ? 0 : scriptUpdateMS.reduce(0, +) / Double(scriptUpdateMS.count)
    }

    public func scriptUpdatePercentileMS(_ percentile: Double) -> Double {
        Self.percentile(scriptUpdateMS, percentile: percentile)
    }

    public var gpuAverageMS: Double {
        gpuMS.isEmpty ? 0 : gpuMS.reduce(0, +) / Double(gpuMS.count)
    }

    public func gpuPercentileMS(_ percentile: Double) -> Double {
        Self.percentile(gpuMS, percentile: percentile)
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
        // Combined depth + stencil to match the drawable path: the SWF
        // layer's clip masks stencil-test inside the scene pass.
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float_stencil8,
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
        descriptor.stencilAttachment.texture = depth
        descriptor.stencilAttachment.loadAction = .clear
        descriptor.stencilAttachment.storeAction = .dontCare
        descriptor.stencilAttachment.clearStencil = 0
        return descriptor
    }

    /// The offscreen projection, from the same `activeFOVYRadians` as the live view, so a
    /// capture frames what the window frames.
    private func offscreenProjection(width: Int, height: Int) -> float4x4 {
        MatrixMath.perspective(
            fovYRadians: activeFOVYRadians,
            aspectRatio: Float(width) / Float(height),
            nearZ: Self.nearPlane,
            farZ: Self.farPlane
        )
    }

    /// One synchronous frame through the normal slot/event bookkeeping:
    /// drain in-flight frames, encode, commit, block until the GPU finishes. Feeds FrameStats;
    /// returns the
    /// summary line when this frame closed a 120-frame stats window.
    @discardableResult
    private func renderOffscreenFrame(
        descriptor: MTL4RenderPassDescriptor,
        projection: float4x4,
        advanceAnimation: Bool = true
    ) throws -> String? {
        let cpuStart = frameStats.beginFrame()
        // Debug views are dev filters, so captures and tests render the shipping frame.
        // Debug-view tests opt in through `renderDebugAppliesOffscreen`.
        let requestedDebug = renderDebug
        if !renderDebugAppliesOffscreen {
            renderDebug = .production
        }
        defer { renderDebug = requestedDebug }
        // A paused frame advances every clock by zero, so frames are byte-identical,
        // yet the pass below still encodes and presents.
        let simDelta: Float = worldSimPaused ? 0 : 1 / 30
        if advanceAnimation {
            updateAnimations(deltaTime: simDelta)
            // The world simulation runs on the same fixed step, so the Papyrus VM is
            // deterministic offscreen. The game clock never advances here.
            frameDriver?.updateWorldSim(deltaTime: simDelta)
        }
        // Weather resolves from the time of day each frame. Offscreen the game clock never
        // advances, so forced weather never rerolls.
        frameDriver?.updateWeather(deltaTime: advanceAnimation ? simDelta : 0)
        if advanceAnimation {
            updateParticles(deltaTime: simDelta)
            updatePrecipitation(deltaTime: simDelta)
            // Same per-frame audio work draw(in:) does, so the benchmark's audio
            // budget measures the shipping tick. A no-op (and unmeasured) while
            // no WorldAudioEngine is attached, which is every render test.
            frameDriver?.updateAudio(deltaTime: simDelta)
        }
        endFrameEvent.wait(untilSignaledValue: UInt64(frameIndex - 1), timeoutMS: 2000)
        let slot = frameIndex % Self.maxFramesInFlight
        let allocator = commandAllocators[slot]
        allocator.reset()
        commandBuffer.beginCommandBuffer(allocator: allocator)
        let shadowEncoded = encodeShadowPass(slot: slot, projection: projection)
        let encoded = shadowEncoded
            && encodeScenePass(descriptor: descriptor, slot: slot, projection: projection)
        commandBuffer.endCommandBuffer()
        guard encoded else { throw RendererError.encoderUnavailable }

        commitFrame()
        commandQueue.signalEvent(endFrameEvent, value: UInt64(frameIndex))
        let finished = endFrameEvent.wait(
            untilSignaledValue: UInt64(frameIndex),
            timeoutMS: 5000
        )
        frameIndex += 1
        guard finished else { throw RendererError.gpuTimeout }
        purgeRetiredResources()
        return frameStats.endFrame(cpuStartNS: cpuStart)
    }

    /// Renders one frame offscreen and waits for the GPU, for deterministic tests and
    /// screenshots without a drawable.
    public func renderOffscreen(width: Int, height: Int) throws -> MTLTexture {
        let (color, depth) = try makeOffscreenTargets(width: width, height: height)
        residencySet.addAllocations([color, depth])
        residencySet.commit()
        defer {
            residencySet.removeAllocations([color, depth])
            residencySet.commit()
        }
        try renderOffscreenFrame(
            descriptor: Self.offscreenPassDescriptor(color: color, depth: depth),
            projection: offscreenProjection(width: width, height: height)
        )
        return color
    }

    /// Exact animation-time render for deterministic frame-delta gates.
    public func renderOffscreen(
        width: Int,
        height: Int,
        animationTime: Float
    ) throws -> MTLTexture {
        self.animationTime = animationTime
        updateAnimations(deltaTime: 0)
        frameDriver?.updateWeather(deltaTime: 0)
        seekParticles(to: animationTime)
        let (color, depth) = try makeOffscreenTargets(width: width, height: height)
        residencySet.addAllocations([color, depth])
        residencySet.commit()
        defer {
            residencySet.removeAllocations([color, depth])
            residencySet.commit()
        }
        try renderOffscreenFrame(
            descriptor: Self.offscreenPassDescriptor(color: color, depth: depth),
            projection: offscreenProjection(width: width, height: height),
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
    public func pumpOffscreen(
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
        let projection = offscreenProjection(width: width, height: height)
        var frameMS: [Double] = []
        frameMS.reserveCapacity(maxFrames)
        var summaries: [String] = []
        var animationMS: [Double] = []
        var shadowMS: [Double] = []
        var audioUpdateMS: [Double] = []
        var scriptUpdateMS: [Double] = []
        let gpuLog = GPUFrameLog()
        gpuFrameLog = gpuLog
        defer { gpuFrameLog = nil }

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
            shadowMS.append(lastShadowUpdateMS)
            audioUpdateMS.append(frameDriver?.lastAudioUpdateMS ?? 0)
            scriptUpdateMS.append(frameDriver?.lastScriptUpdateMS ?? 0)
            if settled {
                return OffscreenBenchResult(
                    frameMS: frameMS,
                    windowSummaries: summaries,
                    animationMS: animationMS,
                    shadowMS: shadowMS,
                    audioUpdateMS: audioUpdateMS,
                    scriptUpdateMS: scriptUpdateMS,
                    gpuMS: gpuLog.take()
                )
            }
        }
        throw RendererError.offscreenPumpTimedOut(maxFrames: maxFrames)
    }

    /// Renders `frames` back-to-back frames into one reused offscreen
    /// target and reports per-frame wall times + FrameStats window
    /// summaries. Synchronous frames make the numbers conservative: each
    /// includes the full CPU-GPU round trip a pipelined loop overlaps.
    /// `afterFrame` runs after each frame's timing stops, so a caller can sample
    /// state without adding to the frame time.
    public func renderOffscreenSustained(
        width: Int,
        height: Int,
        frames: Int,
        afterFrame: (Int) -> Void = { _ in }
    ) throws -> OffscreenBenchResult {
        let (color, depth) = try makeOffscreenTargets(width: width, height: height)
        residencySet.addAllocations([color, depth])
        residencySet.commit()
        defer {
            residencySet.removeAllocations([color, depth])
            residencySet.commit()
        }
        let descriptor = Self.offscreenPassDescriptor(color: color, depth: depth)
        let projection = offscreenProjection(width: width, height: height)

        var frameMS: [Double] = []
        frameMS.reserveCapacity(frames)
        var summaries: [String] = []
        var animationMS: [Double] = []
        var shadowMS: [Double] = []
        var audioUpdateMS: [Double] = []
        var scriptUpdateMS: [Double] = []
        let gpuLog = GPUFrameLog()
        gpuFrameLog = gpuLog
        defer { gpuFrameLog = nil }
        for frame in 0 ..< frames {
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
            shadowMS.append(lastShadowUpdateMS)
            audioUpdateMS.append(frameDriver?.lastAudioUpdateMS ?? 0)
            scriptUpdateMS.append(frameDriver?.lastScriptUpdateMS ?? 0)
            afterFrame(frame)
        }
        return OffscreenBenchResult(
            frameMS: frameMS,
            windowSummaries: summaries,
            animationMS: animationMS,
            shadowMS: shadowMS,
            audioUpdateMS: audioUpdateMS,
            scriptUpdateMS: scriptUpdateMS,
            gpuMS: gpuLog.take()
        )
    }
}
