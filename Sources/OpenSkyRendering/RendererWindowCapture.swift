// Copies the frame the window presents into a CPU-readable texture, so a
// screenshot shows exactly what the window shows, debug view included.

import Metal

enum WindowCaptureState {
    case idle
    case requested
    /// The copy is readable once the GPU has finished `frame`.
    case copied(MTLTexture, frame: Int)
}

extension Renderer {
    /// Asks the next live frame to copy what it presents. An untaken older copy
    /// is dropped.
    public func requestWindowCapture() {
        if case let .copied(texture, _) = windowCapture {
            residencySet.removeAllocation(texture)
            residencySet.commit()
        }
        windowCapture = .requested
    }

    /// The copied frame once the GPU has finished it, else nil. Taking it ends
    /// the capture.
    public func takeWindowCapture() -> MTLTexture? {
        guard
            case let .copied(texture, frame) = windowCapture,
            endFrameEvent.signaledValue >= UInt64(frame)
        else { return nil }
        residencySet.removeAllocation(texture)
        residencySet.commit()
        windowCapture = .idle
        return texture
    }

    /// Encodes the copy after the last pass that writes `target`.
    func encodeWindowCapture(of target: MTLTexture) {
        guard case .requested = windowCapture else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: target.pixelFormat,
            width: target.width,
            height: target.height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard
            let copy = device.makeTexture(descriptor: descriptor),
            let blit = commandBuffer.makeComputeCommandEncoder()
        else { return }
        copy.label = "WindowCapture"
        residencySet.addAllocation(copy)
        residencySet.commit()
        blit.label = "WindowCapture"
        blit.barrier(afterQueueStages: .fragment, beforeStages: .blit, visibilityOptions: .device)
        blit.copy(sourceTexture: target, destinationTexture: copy)
        blit.endEncoding()
        windowCapture = .copied(copy, frame: frameIndex)
    }
}
