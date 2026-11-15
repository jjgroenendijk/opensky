// Replacing a render target while earlier frames are still on the GPU. A Metal 4 command
// buffer keeps no resource alive, so a target freed or made non-resident at once can
// fault the GPU. See docs/rendering/metal4-renderer.md.

import Metal

/// Makes new targets resident now and hands the replaced ones to the retire list, which
/// keeps them until every frame that may read them has finished.
struct TargetResidency {
    let set: any MTLResidencySet
    let retire: ([any MTLAllocation]) -> Void

    func replace(_ old: [any MTLAllocation], with new: [any MTLAllocation]) {
        set.addAllocations(new)
        set.commit()
        retire(old)
    }
}

extension Renderer {
    var targetResidency: TargetResidency {
        TargetResidency(set: residencySet) { [unowned self] old in retireAllocations(old) }
    }
}
