// Per-frame FaceGen morph-buffer preparation shared by scene and shadow
// passes. One guard spans both passes so an actor-local stream is copied once.

import Metal

extension Renderer {
    func bindFaceMorph(_ morph: FaceMorphBuffer?, slot: Int) {
        bindMorph(morph, slot: slot)
    }

    func bindShadowMorph(_ morph: FaceMorphBuffer?, slot: Int) {
        bindMorph(morph, slot: slot)
    }

    private func bindMorph(_ morph: FaceMorphBuffer?, slot: Int) {
        guard let morph else { return }
        let key = ObjectIdentifier(morph)
        if frameMorphPrepared.insert(key).inserted {
            morph.prepare(slot: slot)
        }
        argumentTable.setAddress(
            morph.buffer.gpuAddress + UInt64(morph.byteOffset(slot: slot)),
            index: BufferIndex.morphDeltas.rawValue
        )
    }
}
