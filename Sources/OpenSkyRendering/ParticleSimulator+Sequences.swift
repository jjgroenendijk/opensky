// An effect graph plays a NIF sequence by name; the particle controllers that sequence
// feeds take its keys and timing (docs/rendering/particles.md#sequences).

import OpenSkyFormatsMesh

nonisolated extension ParticleSimulator {
    /// Switches to the controllers `name` feeds and restarts their clock. A sequence that
    /// feeds none of this system's controllers changes nothing; the same name again is a no-op.
    public mutating func play(sequence name: String) {
        let key = name.lowercased()
        guard key != sequence else { return }
        sequence = key
        guard let set = definition.sequenceControllers[key] else { return }
        setControllers(set)
    }
}
