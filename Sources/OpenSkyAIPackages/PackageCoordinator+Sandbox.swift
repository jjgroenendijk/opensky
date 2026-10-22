// What the idle runtime needs from a running sandbox: the area it takes markers in.

import OpenSkyActorPresentation
import OpenSkyFormatsESM
import OpenSkyWorldInterface

extension PackageCoordinator {
    /// The cylinder round the sandbox's place, with `fSandboxCylinderBottom` and
    /// `fSandboxCylinderTop` as its height. Nil when the actor runs no sandbox with a radius.
    public func sandboxArea(of actor: ReferenceKey) -> IdleSearchArea? {
        guard
            let machine = executions[actor]?.runner.runningMachines.first(where: {
                $0.kind == .sandbox
            }),
            machine.radius > 0
        else { return nil }
        let settings = machine.setup.sandbox?.settings ?? sandboxSettings
        var area = IdleSearchArea(
            center: machine.center, radius: machine.radius,
            height: settings.cylinderBottom ... max(settings.cylinderBottom, settings.cylinderTop),
            minimumStep: settings.interMarkerMinDistance
        )
        area.allowsMarkers = machine.setup.sandbox?.usesIdleMarkers ?? true
        return area
    }
}
