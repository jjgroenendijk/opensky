// MetalFX builds a temporal scaler through the Neural Engine compiler, a system
// service that can stop answering. The renderer builds it on the main actor, so a
// stuck service blocks every main-actor test of the run (docs/tools/environment.md).

import Metal
import MetalFX
import Synchronization
import Testing

nonisolated public enum MetalFXCompilerProbe {
    /// One answer for the whole run; a stuck service costs the time limit once.
    public static let firstAnswer = Task { await answers(within: .seconds(60)) }

    /// Fails the calling test, instead of blocking the main actor, when the service is stuck.
    public static func requireAnswer() async throws {
        try #require(
            await firstAnswer.value,
            "the Neural Engine compiler did not answer; MetalFX cannot build a temporal scaler"
        )
    }

    /// True when a temporal scaler build returns in time, whether MetalFX built one or not.
    public static func answers(within limit: Duration) async -> Bool {
        await withCheckedContinuation { continuation in
            let reply = Reply(continuation)
            Task { await reply.send(buildTemporalScaler()) }
            Task {
                try? await Task.sleep(for: limit)
                reply.send(false)
            }
        }
    }

    /// The upscale tests' sizes, so a working service has their model compiled before they run.
    @concurrent
    private static func buildTemporalScaler() async -> Bool {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let compiler = try? device.makeCompiler(descriptor: MTL4CompilerDescriptor())
        else { return true }
        let descriptor = MTLFXTemporalScalerDescriptor()
        descriptor.colorTextureFormat = .rgba16Float
        descriptor.depthTextureFormat = .depth32Float_stencil8
        descriptor.motionTextureFormat = .rg16Float
        descriptor.outputTextureFormat = .rgba16Float
        descriptor.inputWidth = 322
        descriptor.inputHeight = 214
        descriptor.outputWidth = 480
        descriptor.outputHeight = 320
        _ = descriptor.makeTemporalScaler(device: device, compiler: compiler)
        return true
    }
}

nonisolated private final class Reply: Sendable {
    private let continuation: Mutex<CheckedContinuation<Bool, Never>?>

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = Mutex(continuation)
    }

    func send(_ answer: Bool) {
        continuation.withLock { $0.take() }?.resume(returning: answer)
    }
}
