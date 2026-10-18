// The tour's scenes. Positions come from the install's map markers and cell
// lists, read with `openskycli record` and `cell --refs`; see docs/tools/benchmark.md.

import Foundation
import simd

nonisolated public enum BenchmarkTour {
    /// One scene of each base-game group, in tour order.
    public static let quickSceneIDs = ["whiterun", "whiterunPlains", "dragonsreach"]

    /// Each shot runs this long, so every scene weighs the same in the tour total.
    static let shotSeconds = 16.0

    public static let scenes: [BenchmarkScene] = cities + wilderness + interiors + dlc

    public static func scene(id: String) -> BenchmarkScene? {
        scenes.first { $0.id == id }
    }

    static let cities: [BenchmarkScene] = [
        BenchmarkScene(
            id: "whiterun", title: "Whiterun streets", group: .city,
            place: .exterior(worldspace: "WhiterunWorld", x: 19855, y: -7422),
            hour: 10, weather: "SkyrimClear",
            shot: .dolly(
                path: [[0, 0, 300], [2300, 2600, 700], [4600, 5200, 1300], [5800, 6500, 1900]],
                focus: [[3500, 3800, 900], [7016, 7631, 2200], [7016, 7631, 2600]],
                seconds: shotSeconds
            )
        ),
        BenchmarkScene(
            id: "solitude", title: "Solitude from above", group: .city,
            place: .exterior(worldspace: "SolitudeWorld", x: -58300, y: 102_800),
            hour: 16, weather: "SkyrimCloudy",
            shot: .orbit(
                center: [0, 0, 400], radius: 4500, height: 2500,
                startDegrees: 200, sweepDegrees: 120, seconds: shotSeconds
            )
        ),
        BenchmarkScene(
            id: "riften", title: "Riften canal", group: .city,
            place: .exterior(worldspace: "RiftenWorld", x: 173_415, y: -96600),
            hour: 19, weather: "SkyrimFog",
            shot: .dolly(
                path: [[0, 0, 350], [1200, -900, 300], [2500, -1900, 350], [3400, -2900, 450]],
                focus: [[1500, -1200, 250], [3426, -1708, 400], [3426, -3378, 500]],
                seconds: shotSeconds
            )
        ),
        BenchmarkScene(
            id: "markarth", title: "Markarth stone city", group: .city,
            place: .exterior(worldspace: "MarkarthWorld", x: -174_024, y: 5255),
            hour: 13, weather: "SkyrimClear",
            shot: .pan(
                eye: [0, 0, 250], fromYawDegrees: 140, toYawDegrees: 260,
                pitchDegrees: 14, seconds: shotSeconds
            )
        ),
        BenchmarkScene(
            id: "windhelm", title: "Windhelm in snow", group: .city,
            place: .exterior(worldspace: "WindhelmWorld", x: 135_025, y: 35596),
            hour: 9, weather: "SkyrimStormSnow",
            shot: .dolly(
                path: [[0, 0, 300], [-50, 2000, 500], [-100, 4000, 800], [-126, 5600, 1100]],
                focus: [[-60, 2500, 500], [-126, 6083, 900], [-126, 6600, 1300]],
                seconds: shotSeconds
            )
        )
    ]

    static let wilderness: [BenchmarkScene] = [
        BenchmarkScene(
            id: "whiterunPlains", title: "Tundra to Riverwood", group: .wilderness,
            place: .exterior(worldspace: "Tamriel", x: 18312, y: -10665),
            hour: 8, weather: "SkyrimClear",
            shot: .flyover(
                from: [0, 0, 1500], to: [3629, -34127, 3500], pitchDegrees: 12,
                seconds: shotSeconds
            )
        ),
        BenchmarkScene(
            id: "riftForest", title: "Autumn forest of the Rift", group: .wilderness,
            place: .exterior(worldspace: "Tamriel", x: 162_923, y: -60529),
            hour: 15, weather: "SkyrimClear",
            shot: .flyover(
                from: [0, 0, 1800], to: [7000, -23500, 2600], pitchDegrees: 10,
                seconds: shotSeconds
            )
        ),
        BenchmarkScene(
            id: "falkreathPines", title: "Falkreath pine forest", group: .wilderness,
            place: .exterior(worldspace: "Tamriel", x: -30296, y: -86283),
            hour: 6.5, weather: "SkyrimFog",
            shot: .orbit(
                center: [0, 0, 300], radius: 3000, height: 1200,
                startDegrees: 0, sweepDegrees: 150, seconds: shotSeconds
            )
        ),
        BenchmarkScene(
            id: "throatOfTheWorld", title: "Throat of the World", group: .wilderness,
            place: .exterior(worldspace: "Tamriel", x: 56368, y: -48511),
            hour: 11, weather: "SkyrimClearSN",
            shot: .orbit(
                center: [0, 0, 200], radius: 6000, height: 1500,
                startDegrees: 90, sweepDegrees: 180, seconds: shotSeconds
            )
        ),
        BenchmarkScene(
            id: "hjaalmarchMarsh", title: "Hjaalmarch marsh", group: .wilderness,
            place: .exterior(worldspace: "Tamriel", x: -38639, y: 66734),
            hour: 21, weather: "SkyrimOvercastRain",
            shot: .dolly(
                path: [[-3000, -2500, 400], [-1500, -1000, 300], [0, 500, 350], [1500, 2000, 500]],
                focus: [[0, 0, 200], [1500, 1500, 250], [3500, 3500, 400]],
                seconds: shotSeconds
            )
        ),
        BenchmarkScene(
            id: "winterholdCoast", title: "Winterhold and the Sea of Ghosts", group: .wilderness,
            place: .exterior(worldspace: "Tamriel", x: 109_207, y: 102_864),
            hour: 17, weather: "SkyrimStormSnow",
            shot: .flyover(
                from: [-2000, -3000, 1400], to: [9000, 21000, 1800], pitchDegrees: 8,
                seconds: shotSeconds
            )
        ),
        BenchmarkScene(
            id: "blackreach", title: "Blackreach cavern", group: .wilderness,
            place: .exterior(worldspace: "Blackreach", x: 14336, y: 14336),
            hour: 12, weather: nil,
            shot: .orbit(
                center: [0, 0, 300], radius: 3000, height: 1200,
                startDegrees: 0, sweepDegrees: 160, seconds: shotSeconds
            )
        )
    ]

    /// Interior shots stand where the door puts the player and turn on the spot.
    static let interiors: [BenchmarkScene] = [
        interior(
            id: "dragonsreach",
            title: "Dragonsreach great hall",
            cell: "WhiterunDragonsreach"
        ),
        interior(id: "bleakFalls", title: "Bleak Falls Barrow", cell: "BleakFallsBarrow01"),
        interior(id: "mzinchaleft", title: "Mzinchaleft Dwemer ruin", cell: "Mzinchaleft01"),
        interior(id: "bluePalace", title: "Blue Palace", cell: "SolitudeBluePalace"),
        interior(id: "raggedFlagon", title: "The Ragged Flagon", cell: "RiftenRaggedFlagon")
    ]

    static let dlc: [BenchmarkScene] = [
        BenchmarkScene(
            id: "forgottenVale", title: "Forgotten Vale", group: .dlc,
            place: .exterior(worldspace: "DLC01FalmerValley", x: 20252, y: 5160),
            hour: 10, weather: nil,
            shot: .flyover(
                from: [-4000, -6000, 1600], to: [6000, 9000, 2200], pitchDegrees: 10,
                seconds: shotSeconds
            ),
            requiredPlugin: "Dawnguard.esm"
        ),
        BenchmarkScene(
            id: "soulCairn", title: "Soul Cairn", group: .dlc,
            place: .exterior(worldspace: "DLC01SoulCairn", x: 26624, y: 2048),
            hour: 12, weather: nil,
            shot: .flyover(
                from: [0, 0, 2200], to: [-24576, -24576, 2600], pitchDegrees: 12,
                seconds: shotSeconds
            ),
            requiredPlugin: "Dawnguard.esm"
        ),
        BenchmarkScene(
            id: "ravenRock", title: "Raven Rock", group: .dlc,
            place: .exterior(worldspace: "DLC2SolstheimWorld", x: 30883, y: 35049),
            hour: 14, weather: nil,
            shot: .orbit(
                center: [0, 0, 300], radius: 3500, height: 1400,
                startDegrees: 270, sweepDegrees: 140, seconds: shotSeconds
            ),
            requiredPlugin: "Dragonborn.esm"
        ),
        BenchmarkScene(
            id: "telMithryn", title: "Tel Mithryn mushroom tower", group: .dlc,
            place: .exterior(worldspace: "DLC2SolstheimWorld", x: 75484, y: 23834),
            hour: 18, weather: nil,
            shot: .orbit(
                center: [0, 0, 800], radius: 2200, height: 600,
                startDegrees: 0, sweepDegrees: 200, seconds: shotSeconds
            ),
            requiredPlugin: "Dragonborn.esm"
        )
    ]

    private static func interior(id: String, title: String, cell: String) -> BenchmarkScene {
        BenchmarkScene(
            id: id, title: title, group: .interior, place: .interior(cell: cell),
            hour: 20, weather: nil,
            shot: .pan(
                eye: [0, 0, 120], fromYawDegrees: 0, toYawDegrees: 330,
                pitchDegrees: 6, seconds: shotSeconds
            )
        )
    }
}
