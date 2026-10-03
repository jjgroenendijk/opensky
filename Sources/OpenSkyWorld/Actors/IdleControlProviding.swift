// The Idles section's seam: the idle markers of the loaded cell, their idle
// lists and trees, and the last selection for one actor with its trace.

import OpenSkyFormatsESM

/// One placed idle marker, as the panel lists it.
nonisolated public struct IdleMarkerReadout: Equatable, Sendable {
    public let reference: ReferenceKey
    public let editorID: String
    /// IDLA editor IDs, in file order.
    public let idles: [String]
    public let idleIDs: [ResolvedFormID]
    public let inSequence: Bool
    public let doOnce: Bool
    /// IDLT, seconds.
    public let timer: Float
    /// The actor standing at or walking to it.
    public let claimedBy: ReferenceKey?
}

/// One line of the related-idle tree below an idle.
nonisolated public struct IdleTreeLine: Equatable, Sendable {
    public let editorID: String
    public let depth: Int
    public let event: String?
}

/// What the last selection for one actor did.
nonisolated public struct IdleReport: Sendable {
    public let actor: ReferenceKey
    /// The marker's editor ID, or "fired" for a panel request.
    public let source: String
    public let trace: [IdleCandidateTrace]
    public let chosen: String?
    public let plan: IdlePlaybackPlan?
    /// Seconds the clip plays, after the loop count.
    public let seconds: Float
    /// Why nothing played, when nothing did.
    public let failure: String?
}

nonisolated public struct IdleControlSnapshot: Sendable {
    public let isAvailable: Bool
    public let usesIdleMarkers: Bool
    public let markers: [IdleMarkerReadout]
    /// Actors standing at a marker.
    public let idlingActorCount: Int
    public let report: IdleReport?

    public static let unavailable = IdleControlSnapshot(
        isAvailable: false, usesIdleMarkers: false, markers: [], idlingActorCount: 0, report: nil
    )

    public init(
        isAvailable: Bool,
        usesIdleMarkers: Bool,
        markers: [IdleMarkerReadout],
        idlingActorCount: Int,
        report: IdleReport?
    ) {
        self.isAvailable = isAvailable
        self.usesIdleMarkers = usesIdleMarkers
        self.markers = markers
        self.idlingActorCount = idlingActorCount
        self.report = report
    }
}

@MainActor
public protocol IdleControlProviding: AnyObject {
    /// The snapshot with `actor`'s last report.
    func idleSnapshot(for actor: ReferenceKey?) -> IdleControlSnapshot
    /// Off stops sending sandboxing actors to markers; a playing idle finishes.
    func setUsesIdleMarkers(_ enabled: Bool)
    func idleTree(below idle: ResolvedFormID) -> [IdleTreeLine]
    /// Plays one idle on `actor`. Its conditions run, and a failure plays
    /// nothing unless `ignoringConditions`.
    @discardableResult
    func fireIdle(
        _ idle: ResolvedFormID, on actor: ReferenceKey, ignoringConditions: Bool
    ) -> IdleReport?
    /// Runs the marker's selection for `actor` where it stands, and plays the result.
    @discardableResult
    func pickIdle(at marker: ReferenceKey, for actor: ReferenceKey) -> IdleReport?
}

/// Lets the app's provider object stand in for its `IdleCoordinator`.
public protocol IdleControlForwarding: IdleControlProviding {
    var idles: IdleCoordinator { get }
}

extension IdleControlForwarding {
    public func idleSnapshot(for actor: ReferenceKey?) -> IdleControlSnapshot {
        idles.idleSnapshot(for: actor)
    }

    public func setUsesIdleMarkers(_ enabled: Bool) {
        idles.setUsesIdleMarkers(enabled)
    }

    public func idleTree(below idle: ResolvedFormID) -> [IdleTreeLine] {
        idles.idleTree(below: idle)
    }

    @discardableResult
    public func fireIdle(
        _ idle: ResolvedFormID, on actor: ReferenceKey, ignoringConditions: Bool
    ) -> IdleReport? {
        idles.fireIdle(idle, on: actor, ignoringConditions: ignoringConditions)
    }

    @discardableResult
    public func pickIdle(at marker: ReferenceKey, for actor: ReferenceKey) -> IdleReport? {
        idles.pickIdle(at: marker, for: actor)
    }
}
