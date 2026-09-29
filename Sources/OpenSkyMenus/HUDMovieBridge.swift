// Engine-owned state for vanilla `Interface\hudmenu.swf` (M8.4.2). The movie
// exposes direct functions on `/HUDMovieBaseInstance`, so this bridge converts
// typed engine values into that observed AS2 contract. It owns no renderer or
// movie lifetime; the caller batches mutations through `Renderer.updateSWFRuntime`.

import Foundation
import OpenSkyFormatsSWF

nonisolated public struct HUDMeterValues: Equatable, Sendable {
    public var health: Float
    public var magicka: Float
    public var stamina: Float

    public static let full = HUDMeterValues(health: 1, magicka: 1, stamina: 1)
}

nonisolated public enum HUDCompassMarkerKind: Equatable, Sendable {
    case location
    case quest
    case questDoor
    case enemy
    case undiscovered
    case playerSet

    public var movieProperty: String {
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

nonisolated public struct HUDCompassMarker: Equatable, Sendable {
    public let headingDegrees: Float
    public let opacityPercent: Float
    public let kind: HUDCompassMarkerKind
    public let scalePercent: Float

    public init(
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

nonisolated public enum HUDMovieError: Error, Equatable {
    case movieLoaderUnavailable
    case missingDisplayObject(String)
    case missingEntryPoint(String)
}

nonisolated public enum HUDMovieBridge: Sendable {
    public static let moviePath = "interface\\hudmenu.swf"
    public static let targetPath = "/HUDMovieBaseInstance"
    public static let requiredEntryPoints = [
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
    private static let authoredPlaceholderPaths = [
        "/HUDMovieBaseInstance/RolloverInfoInstance",
        "/HUDMovieBaseInstance/SubtitleTextHolder"
    ]

    public static func validate(runtime: SWFMovieRuntime) throws {
        guard let target = runtime.node(atPath: targetPath, from: runtime.root) else {
            throw HUDMovieError.missingDisplayObject(targetPath)
        }
        for name in requiredEntryPoints
            where target.object.lookup(name)?.property.value.functionValue == nil
        {
            throw HUDMovieError.missingEntryPoint(name)
        }
    }

    public static func initialize(
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
        setAuthoredPlaceholderTextEnabled(false, runtime: runtime)
    }

    public static func setCrosshairEnabled(_ enabled: Bool, runtime: SWFMovieRuntime) {
        call("SetCrosshairEnabled", [.boolean(enabled)], runtime: runtime)
    }

    public static func setMeters(_ meters: HUDMeterValues, runtime: SWFMovieRuntime) {
        meter("SetHealthMeterPercent", value: meters.health, runtime: runtime)
        meter("SetMagickaMeterPercent", value: meters.magicka, runtime: runtime)
        meter("SetStaminaMeterPercent", value: meters.stamina, runtime: runtime)
    }

    public static func setMetersEnabled(_ enabled: Bool, runtime: SWFMovieRuntime) {
        for path in meterPaths {
            guard let meter = runtime.node(atPath: path, from: runtime.root) else {
                continue
            }
            runtime.setDisplayProperty(.visible, of: meter, to: .boolean(enabled))
        }
    }

    /// The vanilla movie ships visible authoring samples in two otherwise
    /// engine-driven fields. Keep them inspectable without leaking them into
    /// normal gameplay before OpenSky publishes item info and subtitles.
    public static func setAuthoredPlaceholderTextEnabled(
        _ enabled: Bool,
        runtime: SWFMovieRuntime
    ) {
        for path in authoredPlaceholderPaths {
            guard let node = runtime.node(atPath: path, from: runtime.root) else {
                continue
            }
            runtime.setDisplayProperty(.visible, of: node, to: .boolean(enabled))
        }
    }

    public static func setActivationPrompt(_ prompt: String?, runtime: SWFMovieRuntime) {
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

    public static func setCompassMarkers(
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

    public static func setCompassHeading(
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

    public static func normalizedDegrees(_ degrees: Float) -> Float {
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
