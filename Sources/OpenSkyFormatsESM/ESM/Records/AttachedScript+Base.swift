// A reference runs its base object's scripts as well as its own. Source: the Creation
// Kit wiki pages "Script" and "Reference" on scripts attached to base objects.

import Foundation

nonisolated extension [AttachedScript] {
    /// These reference scripts over `base`. A same-named reference script keeps its
    /// flags and overrides the base's property values one property at a time.
    public func overlaying(base: [AttachedScript]) -> [AttachedScript] {
        guard !base.isEmpty else { return self }
        let own = Dictionary(map { ($0.name.lowercased(), $0) }) { first, _ in first }
        let merged = base.map { script in
            own[script.name.lowercased()].map { $0.overriding(script) } ?? script
        }
        let baseNames = Set(base.map { $0.name.lowercased() })
        return merged + filter { !baseNames.contains($0.name.lowercased()) }
    }
}

nonisolated extension AttachedScript {
    fileprivate func overriding(_ base: AttachedScript) -> AttachedScript {
        let names = Set(properties.map { $0.name.lowercased() })
        let kept = base.properties.filter { !names.contains($0.name.lowercased()) }
        return AttachedScript(name: name, flags: flags, properties: kept + properties)
    }
}
