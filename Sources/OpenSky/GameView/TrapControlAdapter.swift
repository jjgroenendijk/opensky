// App side of the Traps section: reads the trap scripts, trigger occupancy, the
// enable-parent chain, and the hazards from the session systems, and fires or
// disarms through the same paths a walk or a use-key press takes. No trap rules
// live here; the shipped scripts decide (docs/engine/traps.md).

import OpenSkyDiagnostics
import OpenSkyFormatsESM
import OpenSkyMagic
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

final class TrapControlAdapter {
    static let markerSize: Float = 48
    static let markerColor = SIMD4<Float>(1, 0.3, 0.2, 1)

    unowned let game: GameViewController
    private(set) var selected: ReferenceKey?
    private(set) var lastText = "No trap action yet."

    init(game: GameViewController) {
        self.game = game
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
        guard let streamer = game.streamer, let bridge = game.scripts.bridge else {
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
            hazards: game.hazards.hazardRows,
            hazardHits: game.hazards.hitTotal,
            lastText: lastText
        )
    }

    func select(_ key: ReferenceKey?) {
        selected = key
    }

    func fire() -> String {
        guard let streamer = game.streamer, let entry = selectedEntry else {
            return note("No trap selected.")
        }
        streamer.onTriggerTransition(TriggerTransitionEvent(reference: entry.key, phase: .enter))
        streamer.onTriggerTransition(TriggerTransitionEvent(reference: entry.key, phase: .leave))
        return note("Stepped into and out of \(name(of: entry)).")
    }

    func disarm() -> String {
        guard let bridge = game.scripts.bridge, let entry = selectedEntry else {
            return note("No trap selected.")
        }
        let outcome = bridge.activate(entry.key, by: .player, togglesOpen: false)
        return note("Activated \(name(of: entry)): \(outcome.queuedEvents) script events.")
    }

    private var selectedEntry: RuntimeReferenceEntry? {
        selected.flatMap { game.streamer?.referenceEntry(key: $0) }
    }

    private func note(_ text: String) -> String {
        lastText = text
        return text
    }

    private func enableResolver(_ streamer: CellStreamer) -> EnableParentResolver {
        let store = game.worldState
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
        let scripts = (entry.placedReference?.scriptData.scripts ?? [])
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
            let runtime = game.scripts.runtime,
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
        guard let interaction = game.streamer?.residentInteraction(reference: entry.formID) else {
            return entry.formID.description
        }
        return "\(interaction.name) \(entry.formID)"
    }
}
