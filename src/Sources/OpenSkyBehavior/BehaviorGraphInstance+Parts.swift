// The parts of a graph instance, one per node family. A part calls the parts after it in
// this list directly, and an earlier one only through the instance.

import OpenSkyFormatsAnimation

nonisolated extension BehaviorGraphInstance {
    var generators: Generators {
        Generators(graph: self)
    }

    var blenders: Blenders {
        Blenders(graph: self)
    }

    public var clipPlayback: Clips {
        Clips(graph: self)
    }

    var childGraphs: ChildGraphs {
        ChildGraphs(graph: self)
    }

    var stateMachines: StateMachines {
        StateMachines(graph: self)
    }

    var modifiers: Modifiers {
        Modifiers(graph: self)
    }

    var boneModifiers: BoneModifiers {
        BoneModifiers(graph: self)
    }

    var variableModifiers: VariableModifiers {
        VariableModifiers(graph: self)
    }

    /// Generator dispatch, selectors, and the Bethesda generators.
    struct Generators {
        let graph: BehaviorGraphInstance
    }

    /// Blender children and pose matching.
    struct Blenders {
        let graph: BehaviorGraphInstance
    }

    /// Clip playback, annotations, and clip synchronization.
    public struct Clips {
        let graph: BehaviorGraphInstance
    }

    /// Behavior references: the child graphs this one runs.
    struct ChildGraphs {
        let graph: BehaviorGraphInstance
    }

    /// State machines: states, events, transitions, and wildcards.
    struct StateMachines {
        let graph: BehaviorGraphInstance
    }

    /// Modifier dispatch and the event and ragdoll modifiers.
    struct Modifiers {
        let graph: BehaviorGraphInstance
    }

    /// The modifiers that move bones: keyframes, twists, aiming, and foot IK.
    struct BoneModifiers {
        let graph: BehaviorGraphInstance
    }

    /// The modifiers that read and write graph variables and expressions.
    struct VariableModifiers {
        let graph: BehaviorGraphInstance
    }
}
