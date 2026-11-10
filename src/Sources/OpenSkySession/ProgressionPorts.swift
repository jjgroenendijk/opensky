public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyProgression
public import OpenSkyProgressionInterface
public import OpenSkySessionInterface

extension PerkCoordinator: PerkPort {
    public func modified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        given conditions: (subjects: PerkEvaluationSubjects, seams: ConditionContext)
    ) -> Float {
        modified(
            value, at: entryPoint, on: key, subjects: { _ in conditions.subjects },
            seams: conditions.seams
        )
    }
}

extension PerkRuntime: PerkRuntimePort {}
extension PlayerLevelRuntime: PlayerLevelRuntimePort {}
extension ProgressionCoordinator: ProgressionPort {}
