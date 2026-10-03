// The idle selector, clip cache, and report book-keeping of `IdleCoordinator`.

import OpenSkyConditions
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData

extension IdleCoordinator {
    func selector(for actor: ReferenceKey) -> IdleSelector {
        var context = world?.idleConditionContext() ?? ConditionContext()
        context.subject = actor
        let base = context
        let check: IdleSelector.Check = { idle in
            var evaluator = ConditionEvaluator(context: base)
            return evaluator.firstFailure(in: idle.conditions).map(evaluator.functionName(of:))
        }
        guard let store else {
            return IdleSelector(children: { _ in [] }, check: check)
        }
        return IdleSelector(store: store, check: check)
    }

    static func attachment(_ prop: IdleProp) -> ActorPropAttachment? {
        guard case let .attached(_, modelPath, bone) = prop else { return nil }
        return ActorPropAttachment(modelPath: modelPath, bone: bone)
    }

    /// Drops the prop of the idle that ends; the clip retires on its own.
    func endIdle(of actor: ReferenceKey) {
        guard sessions[actor]?.playing?.hasProp == true else { return }
        world?.setProp(nil, on: actor)
    }

    func clip(_ path: String, skeleton: String) -> ActorAnimationClip? {
        let key = "\(skeleton)#\(path)"
        if let cached = clips[key] {
            return cached
        }
        guard let files, !failedClips.contains(key) else { return nil }
        guard
            let clip = try? ActorAnimationClipLoader.clip(
                skeletonMeshPath: skeleton,
                animationPath: path,
                readHKX: { try HKXFile(data: files.contents(forPath: $0)) }
            )
        else {
            failedClips.insert(key)
            return nil
        }
        clips[key] = clip
        return clip
    }

    func failed(_ actor: ReferenceKey, source: String, _ reason: String) -> IdleReport {
        record(IdleReport(
            actor: actor, source: source, trace: [], chosen: nil, plan: nil, seconds: 0,
            failure: reason
        ))
    }

    func record(_ report: IdleReport) -> IdleReport {
        reports[report.actor] = report
        return report
    }
}
