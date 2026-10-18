// App side of the Traps section: reads the trap scripts, trigger occupancy, the
// enable-parent chain, and the hazards from the session systems, and fires or
// disarms through the same paths a walk or a use-key press takes. No trap rules
// live here; the shipped scripts decide (docs/engine/traps.md).

import OpenSkyDiagnostics
import OpenSkyFormatsESM
import OpenSkyMagic
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What the Traps section reads. The streamer is a closure, because a reload
/// replaces it.
struct TrapControlDependencies {
    let hazards: HazardCoordinator
    let scripts: ScriptCoordinator
    let worldState: WorldStateStore
    let streamer: () -> CellStreamer?
}

final class TrapControlAdapter {
    static let markerSize: Float = 48
    static let markerColor = SIMD4<Float>(1, 0.3, 0.2, 1)

    private let dependencies: TrapControlDependencies
    private(set) var selected: ReferenceKey?
    private(set) var lastAction = TrapActionOutcome.idle

    init(_ dependencies: TrapControlDependencies) {
        self.dependencies = dependencies
    }

    func wire(renderer: Renderer) {
        renderer.worldOverlaySources.register(identifier: "trap-selection") { [weak self] _, list in
            guard let position = self?.selectedEntry?.placedReference?.placement.position else {
                return
            }
            list.addMarker(at: position, size: Self.markerSize, color: Self.markerColor)
        }
    }

    var snapshot: TrapControlSnapshot {
        guard
            let streamer = dependencies.streamer(),
            let bridge = dependencies.scripts.bridge
        else {
            return .unavailable
        }
        let resolver = enableResolver(streamer)
        let triggers = streamer.residentReferences
            .compactMap { row(for: $0, bridge: bridge, resolver: resolver) }
            .sorted { ($0.name, $0.key.description) < ($1.name, $1.key.description) }
        return TrapControlSnapshot(
            isAvailable: true,
            triggers: triggers,
            selected: selected,
            chain: chain(streamer: streamer, resolver: resolver),
            hazards: dependencies.hazards.hazardRows,
            hazardHits: dependencies.hazards.hitTotal,
            lastText: lastAction.text
        )
    }

    func select(_ key: ReferenceKey?) {
        selected = key
    }

    func fire() -> TrapActionOutcome {
        guard let streamer = dependencies.streamer(), let entry = selectedEntry else {
            return note(.noSelection)
        }
        streamer.onTriggerTransition(TriggerTransitionEvent(reference: entry.key, phase: .enter))
        streamer.onTriggerTransition(TriggerTransitionEvent(reference: entry.key, phase: .leave))
        return note(.fired(trap: name(of: entry)))
    }

    func disarm() -> TrapActionOutcome {
        guard let bridge = dependencies.scripts.bridge, let entry = selectedEntry else {
            return note(.noSelection)
        }
        let outcome = bridge.activate(entry.key, by: .player, togglesOpen: false)
        return note(.activated(trap: name(of: entry), queuedEvents: outcome.queuedEvents))
    }

    private var selectedEntry: RuntimeReferenceEntry? {
        selected.flatMap { dependencies.streamer()?.referenceEntry(key: $0) }
    }

    private func note(_ outcome: TrapActionOutcome) -> TrapActionOutcome {
        lastAction = outcome
        return outcome
    }

    private func enableResolver(_ streamer: CellStreamer) -> EnableParentResolver {
        let store = dependencies.worldState
        return EnableParentResolver(
            delta: { store.delta(for: $0) },
            parent: { [weak streamer] in streamer?.referenceEntry(formID: $0) }
        )
    }

    private func row(
        for entry: RuntimeReferenceEntry,
        bridge: PapyrusWorldStateBridge,
        resolver: EnableParentResolver
    ) -> TrapTriggerRow? {
        let scripts = entry.scripts.filter { !$0.isRemoved }
            .map(\.name)
            .filter(TrapScriptFamily.contains)
        guard !scripts.isEmpty else { return nil }
        return TrapTriggerRow(
            key: entry.key,
            name: name(of: entry),
            scripts: scripts.map { "\($0): \(state(of: entry.key, script: $0))" },
            occupants: bridge.triggerOccupants[entry.key]?.count ?? 0,
            isEnabled: resolver.isEnabled(entry)
        )
    }

    /// The Papyrus state name; the empty state reads as `default`.
    private func state(of key: ReferenceKey, script: String) -> String {
        guard
            let runtime = dependencies.scripts.runtime,
            let handle = runtime.instancesByKey[PapyrusInstanceKey(
                reference: key,
                scriptName: script
            )]
        else { return "not attached" }
        let state = runtime.runtime.instances[handle]?.activeState ?? ""
        return state.isEmpty ? "default" : state
    }

    private func chain(streamer: CellStreamer, resolver: EnableParentResolver) -> [TrapChainLink] {
        var links: [TrapChainLink] = []
        var current = selectedEntry
        while let entry = current, links.count <= EnableParentResolver.maximumDepth {
            links.append(TrapChainLink(
                name: name(of: entry),
                isEnabled: resolver.isEnabled(entry),
                isOppositeOfParent: entry.enableParent?.isOppositeOfParent ?? false
            ))
            current = entry.enableParent.flatMap { streamer.referenceEntry(formID: $0.parent) }
        }
        return links
    }

    private func name(of entry: RuntimeReferenceEntry) -> String {
        guard
            let interaction = dependencies.streamer()?
                .residentInteraction(reference: entry.formID)
        else {
            return entry.formID.description
        }
        return "\(interaction.name) \(entry.formID)"
    }
}
