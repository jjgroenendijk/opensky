// World > Map > Map: open the world or local map, move and zoom its camera,
// and travel to the marker at its center.

import AppKit
import OpenSkyMenus

final class MapMenuSection: MenuButtonSection {
    weak var provider: (any MapMenuControlProviding)?

    init() {
        super.init(statsIdentifier: "MapMenuStatsLabel")
    }

    override var sectionTitle: String {
        "Map"
    }

    override var sectionIdentifier: String {
        "mapMenu"
    }

    override var isOverridden: Bool {
        provider?.mapMenuSnapshot.mode != nil
    }

    override func resetToDefaults() {
        provider?.closeMap()
    }

    override func makeActions() -> [[Action]] {
        [
            [
                run("World Map", "MapMenuOpenWorldControl", "Open the world map.") {
                    $0.openMap(local: false)
                },
                run("Local Map", "MapMenuOpenLocalControl", "Open the local map.") {
                    $0.openMap(local: true)
                },
                run("Close", "MapMenuCloseControl", "Close the map.") { $0.closeMap() }
            ],
            [
                send("North", "MapMenuNorthControl", .move(.up)),
                send("South", "MapMenuSouthControl", .move(.down)),
                send("West", "MapMenuWestControl", .move(.left)),
                send("East", "MapMenuEastControl", .move(.right))
            ],
            [
                run("Zoom In", "MapMenuZoomInControl", "Lower the map camera.") {
                    $0.zoomMap(by: 10000)
                },
                run("Zoom Out", "MapMenuZoomOutControl", "Raise the map camera.") {
                    $0.zoomMap(by: -10000)
                },
                run("Tilt", "MapMenuTiltControl", "Tilt the camera 10 degrees down.") {
                    $0.tiltMap(by: 10)
                },
                send("Travel", "MapMenuTravelControl", .button(.accept))
            ],
            [
                run(
                    "Reveal All",
                    "MapMenuRevealAllControl",
                    "Show every marker and allow travel."
                ) {
                    $0.revealAllMapMarkers()
                },
                run("Reset Fog", "MapMenuResetFogControl", "Hide the explored local map again.") {
                    $0.resetLocalMapFog()
                }
            ]
        ]
    }

    private func run(
        _ title: String, _ id: String, _ tip: String,
        _ body: @escaping (any MapMenuControlProviding) -> Void
    ) -> Action {
        Action(title: title, identifier: id, toolTip: tip) { [weak self] in
            if let provider = self?.provider {
                body(provider)
            }
        }
    }

    private func send(_ title: String, _ id: String, _ event: MenuInputEvent) -> Action {
        run(title, id, "Send \(title) to the map.") { $0.sendMapInput(event) }
    }

    override func isEnabled(_ identifier: String) -> Bool {
        let isOpen = provider?.mapMenuSnapshot.mode != nil
        if identifier == "MapMenuRevealAllControl" || identifier == "MapMenuResetFogControl" {
            return provider != nil
        }
        return identifier.hasPrefix("MapMenuOpen") ? provider != nil && !isOpen : isOpen
    }

    override func readoutText() -> String {
        guard let snapshot = provider?.mapMenuSnapshot else { return "Map: unavailable" }
        return Self.readout(for: snapshot)
    }

    nonisolated static func readout(for snapshot: MapMenuSnapshot) -> String {
        var lines = [
            "Map: \(snapshot.mode ?? "closed")",
            "Markers: \(snapshot.discoveredCount) found, \(snapshot.visibleCount) shown "
                + "of \(snapshot.markerCount)",
            "Selected: \(snapshot.selected ?? "none")",
            "Fast travel: \(snapshot.fastTravelEnabled ? "on" : "off by script")"
        ]
        if let height = snapshot.cameraHeight, let pitch = snapshot.cameraPitch {
            lines.append("Camera: \(Int(height)) high, \(Int(pitch)) degrees")
        }
        lines.append("Quest targets: " + (snapshot.questTargets.isEmpty
                ? "none" : snapshot.questTargets.joined(separator: ", ")))
        if let result = snapshot.lastResult {
            lines.append("Last result: \(result)")
        }
        return lines.joined(separator: "\n")
    }
}
