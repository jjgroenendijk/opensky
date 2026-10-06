// Engine pictures inside a running movie, such as the save screenshot on the main
// menu's Load list. The movie reserves the slot (`SWFImageSlot`); this writes it.

import Foundation
import Metal
import OpenSkyFormatsSWF

extension Renderer {
    /// Writes straight-alpha RGBA pixels into the current movie's image slot. False
    /// when the movie has no such slot or the size does not match it.
    @discardableResult
    public func replaceSWFImage(_ name: String, rgba: Data, width: Int, height: Int) -> Bool {
        guard
            let movie = swf.movie, let slot = movie.scene.movie.imageSlots[name],
            slot.width == width, slot.height == height, rgba.count == width * height * 4,
            let texture = movie.bitmaps[slot.bitmapId]?.texture
        else { return false }
        rgba.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: width * 4
            )
        }
        return true
    }
}
