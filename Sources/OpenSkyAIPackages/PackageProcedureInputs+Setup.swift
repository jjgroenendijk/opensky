// Builds a leaf's machine setup from its parameters. A package with no procedure
// tree keeps the one-procedure reading: its first location and its first target.

import OpenSkyFormatsESM
import OpenSkyWorldInterface
import simd

extension PackageProcedureInputs {
    /// Orbit walks this many points round its circle.
    static let orbitPoints = 8

    public func build(resolver: some PackageInputResolving) -> PackageLeafSetup {
        guard !leaf.inputIndexes.isEmpty else { return legacy(resolver: resolver) }
        let parameters = PackageProcedureParameters.table[leaf.kind] ?? PackageProcedureParameters()
        let place = place(at: parameters.place, resolver: resolver)
        let targets = references(at: parameters.target, resolver: resolver)
        let targetPoint = targets.first.flatMap(resolver.position(of:))
        var setup = PackageProcedureSetup(
            kind: leaf.kind, center: place?.point ?? start,
            destination: targetPoint ?? place?.point, radius: Float(place?.radius ?? 0)
        )
        setup.seed = seed
        setup.targets = targets
        setup.watched = references(at: parameters.watched, resolver: resolver).first
        setup.topic = topic(at: parameters.topic)
        setup.selector = target(at: parameters.selector)
        setup.seconds = number(at: parameters.seconds) ?? 0
        setup.near = number(at: parameters.near) ?? 0
        setup.far = number(at: parameters.far) ?? 0
        setup.height = number(at: parameters.height) ?? 0
        setup.flag = (number(at: parameters.flag) ?? 0) != 0
        setup.startsCombat = (number(at: parameters.combat) ?? 0) != 0
        setup.walks = setup.destination != nil
        var result = PackageLeafSetup(setup: setup)
        switch leaf.kind {
        case .patrol: result = patrol(result, resolver: resolver)
        case .sit: result.seat = targets.first.flatMap(resolver.seat(in:))
        case .orbit: result.setup = orbit(result.setup)
        case .hover: result.setup.destination = result.setup.destination.map { $0 + height }
        default: break
        }
        if let seat = result.seat {
            result.setup.destination = seat.seat.position
            result.setup.walks = true
        }
        return result
    }

    private var height: SIMD3<Float> {
        SIMD3(0, 0, number(at: PackageProcedureParameters.table[leaf.kind]?.height) ?? 0)
    }

    /// Patrol's Bool parameters: Repeatable?, Start At Nearest?, Ride Horse if Possible?,
    /// and Static Pathing?, after Patrol Start and Patrol Radius.
    private func patrol(
        _ base: PackageLeafSetup, resolver: some PackageInputResolving
    ) -> PackageLeafSetup {
        let flags = (2 ... 5).map { (number(at: $0) ?? 0) != 0 }
        let walk = target(at: 0).flatMap(resolver.patrolPath(from:)) ?? []
        return Self.patrolSetup(base, walk: walk, flags: flags, start: start)
    }

    static func patrolSetup(
        _ base: PackageLeafSetup, walk path: [SIMD3<Float>], flags: [Bool], start: SIMD3<Float>
    ) -> PackageLeafSetup {
        var result = base
        let flags = flags.count == 4 ? flags : [false, false, false, false]
        let walk = flags[1]
            ? PackageOverrideExecution.startingAtNearest(path, to: start, loops: flags[0])
            : path
        result.isDirect = flags[3]
        result.setup.repeats = flags[0]
        result.setup.destination = walk.first ?? base.setup.destination
        result.setup.path = Array(walk.dropFirst())
        result.setup.walks = result.setup.destination != nil
        return result
    }

    /// One circle round the place at the middle of the two radii, above it by the height.
    private func orbit(_ base: PackageProcedureSetup) -> PackageProcedureSetup {
        var setup = base
        let ring = max((setup.near + setup.far) / 2, setup.radius)
        let points = (0 ..< Self.orbitPoints).map { step -> SIMD3<Float> in
            let angle = Float(step) / Float(Self.orbitPoints) * 2 * Float.pi
            return setup.center + SIMD3(cos(angle) * ring, sin(angle) * ring, setup.height)
        }
        setup.destination = points.first
        setup.path = Array(points.dropFirst()) + points.prefix(1)
        setup.walks = true
        return setup
    }

    /// A package with no tree: its first location input is the place, and its first
    /// single-reference input the patrol start or the furniture.
    private func legacy(resolver: some PackageInputResolving) -> PackageLeafSetup {
        let all = values.keys.sorted().compactMap { values[$0] }
        let location = all.lazy.compactMap { value -> Package.Location? in
            if case let .location(location) = value {
                return location
            }
            return nil
        }.first
        let target = all.lazy.compactMap { value -> Package.Target? in
            if case let .target(target) = value {
                return target
            }
            return nil
        }.first
        let place = location.flatMap(resolver.place(of:))
        let seat = leaf.kind == .sit
            ? target.flatMap(resolver.reference(of:)).flatMap(resolver.seat(in:)) : nil
        var setup = PackageProcedureSetup(
            kind: leaf.kind, center: place?.point ?? start,
            destination: seat?.seat.position ?? place?.point,
            radius: Float(place?.radius ?? 0)
        )
        setup.seed = seed
        var result = PackageLeafSetup(setup: setup, seat: seat)
        if leaf.kind == .patrol {
            let flags = all.compactMap { value -> Bool? in
                if case let .boolean(flag) = value {
                    return flag
                }
                return nil
            }
            let walk = target.flatMap(resolver.patrolPath(from:)) ?? []
            result = Self.patrolSetup(result, walk: walk, flags: flags, start: start)
            result.setup.walks = true
        }
        return result
    }
}
