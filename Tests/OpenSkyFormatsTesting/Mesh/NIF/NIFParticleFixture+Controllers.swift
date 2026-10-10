// A particle system with an emitter controller chain, for the controller decode tests.

import Foundation

extension NIFParticleFixture {
    /// Blocks 0-5: node, system, data, box emitter "Emit" (string 1), update controller,
    /// and `emitterType` holding `emitter`. `extraBlocks` start at index 6.
    public static func controlledSystemFile(
        emitterType: String = "NiPSysEmitterCtlr",
        emitter: Data,
        updateTail: Data,
        extraBlocks: [NIFFixture.Block],
        strings: [String]
    ) -> Data {
        var update = Data()
        update.appendUInt32(5)
        update.append(updateTail)
        let system = particleSystemSSE(
            prefix: NIFFixture.avObjectPrefix(nameIndex: 0, controllerRef: 4),
            dataRef: 2, modifierRefs: [3]
        )
        return NIFFixture.file(
            blocks: [
                NIFFixture.Block("NiNode", NIFFixture.niNode(
                    prefix: NIFFixture.avObjectPrefix(), children: [1]
                )),
                NIFFixture.Block("NiParticleSystem", system),
                NIFFixture.Block("NiPSysData", psysData(maxParticles: 64)),
                NIFFixture.Block("NiPSysBoxEmitter", boxEmitter(
                    base: modifierBase(nameIndex: 1),
                    emitter: emitterBase(),
                    width: 1, height: 1, depth: 1
                )),
                NIFFixture.Block("NiPSysUpdateCtlr", update),
                NIFFixture.Block(emitterType, emitter)
            ] + extraBlocks,
            strings: strings,
            roots: [0]
        )
    }
}
