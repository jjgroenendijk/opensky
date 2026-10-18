// Texture streaming on the cell build worker: the library that builds cells also reads
// a streamed texture's levels again, in the same queue, so it needs no lock.

import Dispatch
import OpenSkyRendering
import Synchronization

nonisolated extension SerialCellBuildRunner: TextureLevelReading {
    /// Cells queued before this build without streaming; later cells stream.
    public func attachTextureStreaming(_ mailbox: TextureStreamMailbox) {
        queue.async { [self] in
            provider.withLock { $0.attachTextureStreaming(mailbox) }
        }
    }

    public func requestTextureLevels(
        _ request: TextureLevelRequest,
        mailbox: TextureStreamMailbox
    ) {
        queue.async { [self] in
            let levels = provider.withLock { $0.readTextureLevels(request) }
            if let levels {
                mailbox.post(levels: levels, for: request.texture)
            }
        }
    }
}
