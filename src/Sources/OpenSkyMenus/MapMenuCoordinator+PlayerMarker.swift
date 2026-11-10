// The player's own marker on the world map: place it, move it, or remove it.
// The rules live in `PlayerMarkerRule`. See docs/engine/world-map.md#custom-marker.

import Foundation
import OpenSkyGameData
import OpenSkyMenusInterface
public import OpenSkyWorldInterface

extension MapMenuCoordinator {
    /// The marker in the map's worldspace; one in another worldspace stays hidden.
    public var playerMarker: PlayerSetMapMarker? {
        guard
            let world, let marker = world.playerSetMarker,
            marker.worldspace == world.mapWorldspaceName
        else { return nil }
        return marker
    }

    var playerMarkerName: String {
        world?.playerMarkerTexts[.name] ?? PlayerMarkerText.name.fallback
    }

    /// The `PlacePlayerMarker` key. It aims at the map centre, as the cursor does.
    public func placePlayerMarker() {
        guard mode == .world, let camera else {
            lastOutcome = .playerMarkerNeedsWorldMap
            return
        }
        let target = PlayerMarkerRule.target(
            focus: camera.focus, cameraHeight: camera.height, nearest: selected
        )
        run(PlayerMarkerRule.step(target, hasMarker: playerMarker != nil), target: target)
    }

    /// Travel to an undiscovered marker offers to place the custom marker there instead.
    func offerMarker(on site: MapMarkerSite) {
        run(.askUndiscovered(site.position), target: .site(site))
    }

    func setPlayerMarker(at position: SIMD3<Float>) {
        guard let world, let worldspace = world.mapWorldspaceName else { return }
        world.playerSetMarker = PlayerSetMapMarker(worldspace: worldspace, position: position)
        lastOutcome = .playerMarkerPlaced(world.playerMarkerTexts[.placeMarker], position)
        world.showPlayerSetMarker(position)
    }

    func removePlayerMarker() {
        guard let world else { return }
        world.playerSetMarker = nil
        lastOutcome = .playerMarkerAnswered(world.playerMarkerTexts[.remove])
        world.showPlayerSetMarker(nil)
    }

    /// "Custom Destination at x, y", or nil without a marker here.
    var playerMarkerLine: String? {
        playerMarker.map {
            "\(playerMarkerName) at \(Int($0.position.x)), \(Int($0.position.y))"
        }
    }

    private func run(_ step: PlayerMarkerStep, target: PlayerMarkerTarget) {
        guard let world else { return }
        let texts = world.playerMarkerTexts
        switch step {
        case let .place(position):
            setPlayerMarker(at: position)
        case let .askUndiscovered(position):
            world.ask(texts[.placeUndiscovered], buttons: [
                texts[.yes],
                texts[.no]
            ]) { [weak self] in
                if $0 == 0 {
                    self?.setPlayerMarker(at: position)
                } else {
                    self?.lastOutcome = .playerMarkerAnswered(texts[.no])
                }
            }
        case .askMoveOrRemove:
            let buttons = PlayerMarkerMoveAnswer.allCases.map { texts[$0.text] }
            world.ask(texts[.moveQuestion], buttons: buttons) { [weak self] in
                self?.answerMove($0, target: target)
            }
        }
    }

    private func answerMove(_ index: Int, target: PlayerMarkerTarget) {
        switch PlayerMarkerMoveAnswer(rawValue: index) {
        case .move:
            run(PlayerMarkerRule.step(target, hasMarker: false), target: target)
        case .remove:
            removePlayerMarker()
        case .leave, nil:
            lastOutcome = .playerMarkerAnswered(
                world?.playerMarkerTexts[.leave] ?? PlayerMarkerText.leave.fallback
            )
        }
    }
}

nonisolated extension PlayerMarkerMoveAnswer {
    var text: PlayerMarkerText {
        switch self {
        case .move: .move
        case .remove: .remove
        case .leave: .leave
        }
    }
}
