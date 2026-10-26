// The shell of the riding rules in `MountRules`: mounts and dismounts the player, runs
// the paired clips on both graphs, and steps the mount drive. It returns commands; the
// app applies them to the vehicles, the streamer, and crime. See docs/engine/riding.md.

import Foundation
import OpenSkyActorPresentation
import OpenSkyFormatsESM
import OpenSkyRendering
import simd

/// What the mount coordinator reads from the session.
@MainActor
public protocol MountWorld: AnyObject {
    /// What the world says about one actor, or nil when it is not loaded.
    func mountCandidate(_ key: ReferenceKey) -> MountCandidate?
    /// Takes the actor from its packages and its graph runner, for the drive.
    func takeMount(_ key: ReferenceKey, kind: MountKind, saddleBone: String)
        -> PlayerMountDriveStart?
    /// The race's dismount offset in the mount's frame: x right, y forward.
    func dismountOffset(of key: ReferenceKey) -> SIMD3<Float>
    /// The actor in view a ridden dragon's rider locks, or nil.
    func lockCandidate() -> ReferenceKey?
    /// Where a living, loaded actor stands; nil once it is dead or gone.
    func livingActorFeet(_ key: ReferenceKey) -> SIMD3<Float>?
}

nonisolated public enum MountCommand: Equatable, Sendable {
    /// Links the player to the mount's root, for the paired clips.
    case boardPlayer(ReferenceKey)
    /// Links the player's root to the saddle bone.
    case seatPlayer(ReferenceKey, bone: String)
    case detachPlayer
    /// Stands the player at `feet`, facing walk yaw `yaw`.
    case placePlayer(feet: SIMD3<Float>, yaw: Float)
    case raiseOnPlayer(String)
    case steerMount(ReferenceKey, feet: SIMD3<Float>, yaw: Float)
    case reportMountEvents(ReferenceKey, [String])
    /// Gives the mount back to its packages and its graph runner.
    case releaseMount(ReferenceKey)
    /// Riding somebody else's horse is a theft: ask first, with `sStealHorse`.
    case askToSteal(ReferenceKey)
    case reportTheft(ReferenceKey)
    case refused(MountRefusal)
    /// A short message on screen, such as the landing order.
    case notify(String)
    /// The ridden dragon breathes at its locked target.
    case dragonBreath(ReferenceKey, at: ReferenceKey)
}

nonisolated public enum MountPhase: Equatable, Sendable {
    case none
    case mounting(elapsed: Float)
    case riding
    case dismounting(elapsed: Float)
}

@MainActor
public final class MountCoordinator {
    public private(set) var drive: PlayerMountDrive?
    public private(set) var phase = MountPhase.none
    /// The last actor the player mounted, kept after the dismount.
    public private(set) var lastMount: ReferenceKey?
    /// What the rider asked of a ridden dragon.
    public internal(set) var dragonOrders = RiddenDragonOrders()
    public let settings: MountSettings
    public let flightSettings: DragonFlightSettings
    weak let world: (any MountWorld)?

    public init(
        world: any MountWorld, settings: MountSettings = .vanilla,
        flightSettings: DragonFlightSettings = .standard
    ) {
        self.world = world
        self.settings = settings
        self.flightSettings = flightSettings
    }

    /// A mount is under the player, in any phase.
    public var isActive: Bool {
        drive != nil
    }

    /// Mounts `key`. A horse somebody else owns needs `stealConfirmed`; without it the
    /// answer is `askToSteal`.
    public func mount(_ key: ReferenceKey, stealConfirmed: Bool = false) -> [MountCommand] {
        let decision = MountRules.decide(world?.mountCandidate(key), isRiding: isActive)
        switch decision {
        case let .refuse(reason):
            return [.refused(reason)]
        case let .mount(kind, saddle, steals):
            if steals, !stealConfirmed {
                return [.askToSteal(key)]
            }
            guard let start = world?.takeMount(key, kind: kind, saddleBone: saddle) else {
                return [.refused(.notLoaded)]
            }
            let drive = PlayerMountDrive(start)
            drive.settings = settings
            drive.flightSettings = flightSettings
            dragonOrders = RiddenDragonOrders()
            drive.bridge.raise(kind.events.mountEnter)
            self.drive = drive
            lastMount = key
            phase = .mounting(elapsed: 0)
            return [.boardPlayer(key), .raiseOnPlayer(kind.events.riderEnter)]
                + (steals ? [.reportTheft(key)] : [])
        }
    }

    /// Starts the dismount clips. Only a seated rider dismounts; on a dragon in the air
    /// the same key orders the landing or calls it off.
    public func dismount() -> [MountCommand] {
        guard let drive, phase == .riding else { return [] }
        if drive.flight?.phase.isFlying == true {
            return orderLanding(drive)
        }
        drive.isSteerable = false
        drive.bridge.raise(drive.kind.events.mountExit)
        phase = .dismounting(elapsed: 0)
        return [.boardPlayer(drive.mount), .raiseOnPlayer(drive.kind.events.riderExit)]
    }

    /// Reads the events the player's graph fired: they end the mount and the dismount.
    public func handleRiderEvents(_ names: [String]) -> [MountCommand] {
        guard let drive else { return [] }
        let events = drive.kind.events
        var commands: [MountCommand] = []
        for name in names {
            if case .mounting = phase, Self.matches(name, MountGraphNames.pairedStop) {
                commands += finishMount()
            } else if case .dismounting = phase, Self.matches(name, events.riderExitDone) {
                commands += finishDismount()
            }
        }
        return commands
    }

    /// Steps the mount by one input frame. A phase whose end event never came ends on
    /// `MountRules.phaseTimeout`; a mount that died or unloaded drops the rider.
    public func advance(
        input: CameraInput, cameraYaw: Float, weaponDrawn: Bool, world stepWorld: MountStepWorld
    ) -> [MountCommand] {
        guard let drive else { return [] }
        guard let candidate = world?.mountCandidate(drive.mount), !candidate.isDead else {
            return finishDismount()
        }
        if phase == .riding, drive.kind == .dragon {
            return advanceDragon(drive, input: input, world: stepWorld)
        }
        let events = drive.advance(
            input: input, cameraYaw: cameraYaw, weaponDrawn: weaponDrawn, world: stepWorld
        )
        let pose = drive.transform
        var commands: [MountCommand] = [
            .steerMount(drive.mount, feet: pose.feet, yaw: pose.yaw),
            .reportMountEvents(drive.mount, events)
        ]
        let step = max(input.dt, 0)
        switch phase {
        case let .mounting(elapsed):
            phase = .mounting(elapsed: elapsed + step)
            if elapsed + step >= MountRules.phaseTimeout {
                commands += finishMount()
            }
        case let .dismounting(elapsed):
            phase = .dismounting(elapsed: elapsed + step)
            if elapsed + step >= MountRules.phaseTimeout {
                commands += finishDismount()
            }
        case .none, .riding:
            break
        }
        return commands
    }

    private func finishMount() -> [MountCommand] {
        guard let drive else { return [] }
        phase = .riding
        drive.isSteerable = true
        dragonOrders.home = drive.transform.feet
        return [.seatPlayer(drive.mount, bone: drive.saddleBone)]
    }

    private func finishDismount() -> [MountCommand] {
        guard let drive else { return [] }
        let pose = drive.transform
        let offset = world?.dismountOffset(of: drive.mount) ?? SIMD3()
        let feet = pose.feet + SIMD3(MountRules.dismountPosition(offset: offset, yaw: pose.yaw), 0)
        self.drive = nil
        phase = .none
        return [
            .detachPlayer, .placePlayer(feet: feet, yaw: pose.yaw), .releaseMount(drive.mount)
        ]
    }

    private static func matches(_ name: String, _ wanted: String) -> Bool {
        name.caseInsensitiveCompare(wanted) == .orderedSame
    }
}
