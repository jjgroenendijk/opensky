// What a sub-graph reads before each step: its actor's placement and the variables it
// shares with the actor's own graph. See docs/engine/effect-graphs.md.

import OpenSkyBehavior

extension EffectGraphCoordinator {
    func prepare(_ entry: Running, world: any EffectGraphWorld) {
        switch entry.attachment.anchor {
        case let .point(position):
            entry.instance.characterContext = BehaviorCharacterContext(worldPosition: position)
        case let .actor(actor):
            guard let character = world.character(of: actor) else { return }
            entry.actorRig = character.rig
            entry.instance.characterContext = character.context
            if let variables = character.variables {
                Self.share(variables, into: entry.instance, except: entry.scriptHeld)
            }
        }
    }

    /// Copies each variable both graphs declare, by name, from the actor's graph.
    static func share(
        _ actor: BehaviorVariableStore,
        into graph: BehaviorGraphInstance,
        except held: Set<String>
    ) {
        for case let name? in graph.variables.names where !held.contains(name.lowercased()) {
            if let value = actor.value(of: name) {
                graph.setVariable(value, named: name)
            }
        }
    }
}
