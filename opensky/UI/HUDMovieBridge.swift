// Engine-owned state for vanilla `Interface\hudmenu.swf` (M8.4.2). The movie
// exposes direct functions on `/HUDMovieBaseInstance`, so this bridge converts
// typed engine values into that observed AS2 contract. It owns no renderer or
// movie lifetime; the caller batches mutations through `Renderer.updateSWFRuntime`.

import Foundation

nonisolated struct HUDMeterValues: Equatable, Sendable {
    var health: Float
    var magicka: Float
    var stamina: Float

    static let full = HUDMeterValues(health: 1, magicka: 1, stamina: 1)
}

nonisolated enum HUDCompassMarkerKind: Equatable, Sendable {
    case location
    case quest
    case questDoor
    case enemy
    case undiscovered
    case playerSet

    var movieProperty: String {
        switch self {
        case .location: "CompassMarkerLocations"
        case .quest: "CompassMarkerQuest"
        case .questDoor: "CompassMarkerQuestDoor"
        case .enemy: "CompassMarkerEnemy"
        case .undiscovered: "CompassMarkerUndiscovered"
        case .playerSet: "CompassMarkerPlayerSet"
        }
    }
}

nonisolated struct HUDCompassMarker: Equatable, Sendable {
    let headingDegrees: Float
    let opacityPercent: Float
    let kind: HUDCompassMarkerKind
    let scalePercent: Float

    init(
        headingDegrees: Float,
        opacityPercent: Float = 100,
        kind: HUDCompassMarkerKind,
        scalePercent: Float = 100
    ) {
        self.headingDegrees = headingDegrees
        self.opacityPercent = opacityPercent
        self.kind = kind
        self.scalePercent = scalePercent
    }
}

nonisolated enum HUDMovieError: Error, Equatable {
    case movieLoaderUnavailable
    case missingDisplayObject(String)
    case missingEntryPoint(String)
}

nonisolated enum HUDMovieBridge {
    static let moviePath = "interface\\hudmenu.swf"
    static let targetPath = "/HUDMovieBaseInstance"
    static let requiredEntryPoints = [
        "SetCompassAngle",
        "SetCompassMarkers",
        "SetCrosshairEnabled",
        "SetCrosshairTarget",
        "SetHealthMeterPercent",
        "SetMagickaMeterPercent",
        "SetStaminaMeterPercent"
    ]
    private static let meterPaths = [
        "/HUDMovieBaseInstance/Health",
        "/HUDMovieBaseInstance/Magica",
        "/HUDMovieBaseInstance/Stamina"
    ]

    static func validate(runtime: SWFMovieRuntime) throws {
        guard let target = runtime.node(atPath: targetPath, from: runtime.root) else {
            throw HUDMovieError.missingDisplayObject(targetPath)
        }
        for name in requiredEntryPoints
            where target.object.lookup(name)?.property.value.functionValue == nil
        {
            throw HUDMovieError.missingEntryPoint(name)
        }
    }

    static func initialize(
        runtime: SWFMovieRuntime,
        meters: HUDMeterValues = .full,
        headingDegrees: Float = 0,
        markers: [HUDCompassMarker] = [],
        activationPrompt: String? = nil
    ) {
        setCrosshairEnabled(true, runtime: runtime)
        setMeters(meters, runtime: runtime)
        setCompassMarkers(markers, runtime: runtime)
        setCompassHeading(headingDegrees, runtime: runtime)
        setActivationPrompt(activationPrompt, runtime: runtime)
    }

    static func setCrosshairEnabled(_ enabled: Bool, runtime: SWFMovieRuntime) {
        call("SetCrosshairEnabled", [.boolean(enabled)], runtime: runtime)
    }

    static func setMeters(_ meters: HUDMeterValues, runtime: SWFMovieRuntime) {
        meter("SetHealthMeterPercent", value: meters.health, runtime: runtime)
        meter("SetMagickaMeterPercent", value: meters.magicka, runtime: runtime)
        meter("SetStaminaMeterPercent", value: meters.stamina, runtime: runtime)
    }

    static func setMetersEnabled(_ enabled: Bool, runtime: SWFMovieRuntime) {
        for path in meterPaths {
            guard let meter = runtime.node(atPath: path, from: runtime.root) else {
                continue
            }
            runtime.setDisplayProperty(.visible, of: meter, to: .boolean(enabled))
        }
    }

    static func setActivationPrompt(_ prompt: String?, runtime: SWFMovieRuntime) {
        let visible = prompt?.isEmpty == false
        call(
            "SetCrosshairTarget",
            [
                .boolean(visible),
                .string(prompt ?? ""),
                .boolean(visible),
                .boolean(false),
                .boolean(false),
                .boolean(true),
                .number(0),
                .number(0),
                .number(0),
                .string("")
            ],
            runtime: runtime
        )
    }

    static func setCompassMarkers(
        _ markers: [HUDCompassMarker],
        runtime: SWFMovieRuntime
    ) {
        guard let target = runtime.node(atPath: targetPath, from: runtime.root) else {
            runtime.runtime.noteMissing(targetPath)
            return
        }
        let values = markers.flatMap { marker -> [AS2Value] in
            guard let type = target.object.lookup(marker.kind.movieProperty)?.property.value else {
                return []
            }
            return [
                .number(Double(normalizedDegrees(marker.headingDegrees))),
                .number(Double(clampedPercent(marker.opacityPercent))),
                type,
                .number(Double(clampedPercent(marker.scalePercent)))
            ]
        }
        let movieArray = runtime.runtime.makeArray(values)
        target.object.assign(.object(movieArray), for: "CompassTargetDataA")
        runtime.markDirty()
        call("SetCompassMarkers", runtime: runtime)
    }

    static func setCompassHeading(
        _ headingDegrees: Float,
        visible: Bool = true,
        runtime: SWFMovieRuntime
    ) {
        let heading = Double(normalizedDegrees(headingDegrees))
        call(
            "SetCompassAngle",
            [.number(heading), .number(heading), .boolean(visible)],
            runtime: runtime
        )
    }

    static func normalizedDegrees(_ degrees: Float) -> Float {
        guard degrees.isFinite else {
            return 0
        }
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    private static func meter(
        _ name: String,
        value: Float,
        runtime: SWFMovieRuntime
    ) {
        call(
            name,
            [.number(Double(clampedUnit(value))), .boolean(true)],
            runtime: runtime
        )
    }

    private static func call(
        _ name: String,
        _ arguments: [AS2Value] = [],
        runtime: SWFMovieRuntime
    ) {
        runtime.callMovie(name, atPath: targetPath, arguments: arguments)
    }

    private static func clampedPercent(_ percent: Float) -> Float {
        guard percent.isFinite else {
            return 0
        }
        return max(0, min(100, percent))
    }

    private static func clampedUnit(_ value: Float) -> Float {
        guard value.isFinite else {
            return 0
        }
        return max(0, min(1, value))
    }
}
