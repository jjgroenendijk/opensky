// The witness seam: which observers have fully detected a target. Crime asks it
// who saw an act, without depending on the perception runtime.

import OpenSkyFormatsESM

@MainActor
public protocol DetectionObserving: AnyObject {
    /// Every observer whose detection level alone has `target` detected, without
    /// stealth points: who saw a crime.
    func observersWitnessing(_ target: ReferenceKey) -> [ReferenceKey]
}
