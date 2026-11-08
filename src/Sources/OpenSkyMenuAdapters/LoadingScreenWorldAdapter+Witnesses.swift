import Foundation
import OpenSkyCells
public import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
public import OpenSkyGameData
public import OpenSkyLoading
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuests
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkySession
import OpenSkySessionInterface
import OpenSkyTerrain
import OpenSkyWorld
import OpenSkyWorldInterface
import simd

/// Witnesses that forward to the narrow parts of `LoadingScreenWorldAdapter`.
extension LoadingScreenWorldAdapter {
    public var isMovieLoaded: Bool {
        presentation.isMovieLoaded
    }

    public var presentationRecords: PresentationRecordStore? {
        presentation.presentationRecords
    }

    public func loadingConditionContext() -> ConditionContext {
        presentation.loadingConditionContext()
    }

    public func loadingText(of screen: ResolvedRecord<LoadScreen>) -> String? {
        presentation.loadingText(of: screen)
    }

    public func presentLoadingCover(_ frame: LoadingCoverFrame?) {
        presentation.presentLoadingCover(frame)
    }

    public func setLoadingPaused(_ paused: Bool) {
        presentation.setLoadingPaused(paused)
    }
}
