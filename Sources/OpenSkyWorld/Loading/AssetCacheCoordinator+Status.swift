// What the Asset Optimisation page and the Launch page show about the folder:
// the status, the space check, and why Convert is off.

import OpenSkyAssetCache

extension AssetCacheCoordinator {
    public var status: AssetOptimisationStatus {
        let converting = activity == .building
            ? AssetCacheReadout.buildLine(progress, isBuilding: true) : nil
        return AssetOptimisationStatus(
            check: check,
            isChecking: activity == .checking,
            conversion: converting
        )
    }

    /// Nil until a check has read the folder's disk.
    public var spaceCheck: AssetSpaceCheck? {
        guard let check, let volume else { return nil }
        return AssetSpaceCheck(check: check, output: settings.textureOutput, volume: volume)
    }

    /// Why Convert is off, or nil when a conversion can start.
    public var convertDisabledReason: String? {
        if activity != .idle {
            return "Wait for the \(activity == .building ? "conversion" : "check") to finish"
        }
        if !settings.isEnabled {
            return "Turn on asset optimisation first"
        }
        guard status.needsConversion else {
            return check == nil ? "Wait for the check to finish" : "Every file is optimised"
        }
        guard let space = spaceCheck, !space.fits else { return nil }
        return space.warnings.first(where: \.isLowFreeSpace)?.message
    }
}
