import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

nonisolated public struct PackageActorReadout: Equatable, Sendable {
    public let actor: ReferenceKey
    public let actorBase: FormID
    public let currentPackage: FormID?
    public let editorID: String?
    public let schedule: Package.Schedule?
    public let procedure: PackageProcedureKind?
    public let lastEvaluationGameSeconds: Double?
    /// True while something outside the schedule holds this actor, such as a
    /// conversation. It keeps its package and is not re-evaluated until released.
    public var isSuspended = false
    /// The scene action whose packages run ahead of the schedule, if any.
    public var override: PackageOverrideOwner?

    public init(
        actor: ReferenceKey,
        actorBase: FormID,
        currentPackage: FormID?,
        editorID: String?,
        schedule: Package.Schedule?,
        procedure: PackageProcedureKind?,
        lastEvaluationGameSeconds: Double?,
        isSuspended: Bool = false,
        override: PackageOverrideOwner? = nil
    ) {
        self.actor = actor
        self.actorBase = actorBase
        self.currentPackage = currentPackage
        self.editorID = editorID
        self.schedule = schedule
        self.procedure = procedure
        self.lastEvaluationGameSeconds = lastEvaluationGameSeconds
        self.isSuspended = isSuspended
        self.override = override
    }
}

/// What holds an actor's packages ahead of its schedule: a scene action.
nonisolated public struct PackageOverrideOwner: Hashable, Sendable {
    public let source: FormID
    public let slot: UInt32

    public init(source: FormID, slot: UInt32) {
        self.source = source
        self.slot = slot
    }
}

/// Packages that override an actor's own stack, as a scene package action does
/// (<https://ck.uesp.net/wiki/Category:Scenes>, "Actors in Scenes").
nonisolated public struct PackageOverride: Equatable, Sendable {
    public let packages: [FormID]
    public let owner: PackageOverrideOwner
    /// The quest whose aliases the package locations name.
    public let aliasQuest: FormID?

    public init(packages: [FormID], owner: PackageOverrideOwner, aliasQuest: FormID?) {
        self.packages = packages
        self.owner = owner
        self.aliasQuest = aliasQuest
    }
}
