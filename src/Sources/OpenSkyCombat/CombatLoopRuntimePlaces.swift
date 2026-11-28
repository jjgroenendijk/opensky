// The runtime's side of the places around a target: what a styled fighter reads of its
// place, and the booking its step asks for.
// See docs/engine/combat-movement.md#places-around-the-target.

import Foundation
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

extension CombatLoopRuntime.BehaviorDrive {
    /// Fills the place of a styled fighter. Arcs of fighters that left the fight or turned
    /// to another target are freed first.
    func fillPlaceInputs(
        _ inputs: inout CombatBehaviorInputs,
        of fight: (actor: CombatActorObservation, target: MeleeTarget)
    ) {
        let (actor, target) = fight
        guard owner.styleTuning(of: actor.key) != nil else { return }
        let runtime = owner
        var book = runtime.places[target.key] ?? CombatPlaceBook()
        book.keep { key in
            runtime.targets[key] == target.key && runtime.behaviors[key]?.isEngaged == true
        }
        runtime.places[target.key] = book.arcs.isEmpty ? nil : book
        let offset = actor.feet - target.feet
        let bearing = atan2f(offset.y, offset.x)
        let half = CombatPlaceBook.halfWidth(radius: inputs.actorRadius, distance: inputs.reach)
        inputs.place = CombatPlaceInputs(
            bearing: bearing, halfWidth: half,
            isOutOfPosition: book.isOutOfPosition(actor.key, bearing: bearing),
            canBookHere: book.fits(.init(centre: bearing, halfWidth: half), for: actor.key),
            goalBearing: book.freeBearing(near: bearing, halfWidth: half, for: actor.key)
        )
    }

    func bookPlace(
        _ bearing: Float?, of place: CombatPlaceInputs?, by actor: ReferenceKey,
        around target: ReferenceKey
    ) {
        guard let bearing, let place else { return }
        var book = owner.places[target] ?? CombatPlaceBook()
        book.book(.init(centre: bearing, halfWidth: place.halfWidth), for: actor)
        owner.places[target] = book
    }
}

extension CombatLoopRuntime {
    /// The bearing, in degrees, of the place `key` holds around its target.
    func placeDegrees(of key: ReferenceKey) -> Float? {
        guard let target = targets[key], let arc = places[target]?.arcs[key] else { return nil }
        return arc.centre * 180 / .pi
    }
}
