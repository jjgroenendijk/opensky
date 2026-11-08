// A condition context built on its first read and kept after it. Copies of a
// `DialogueRuntime` share one, so they read the same views.

import OpenSkyConditions

@MainActor
final class LazyConditionContext {
    private enum State {
        case pending(() -> ConditionContext)
        case built(ConditionContext)
    }

    private var state: State

    init(_ build: @escaping () -> ConditionContext) {
        state = .pending(build)
    }

    var context: ConditionContext {
        switch state {
        case let .built(context):
            return context
        case let .pending(build):
            let context = build()
            state = .built(context)
            return context
        }
    }
}
