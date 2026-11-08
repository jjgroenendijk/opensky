import Foundation
import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Witnesses that forward to the narrow parts of `DialogueMenuController`.
extension DialogueMenuController {
    func close() {
        speech.close()
    }
}
