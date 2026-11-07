// The body idles a dialogue line plays: its response's speaker idle (`SNAM`) on the
// speaker and listener idle (`LNAM`) on the actor spoken to. See docs/engine/scenes.md.

import OpenSkyActorPresentation
import OpenSkyDialogue
import OpenSkyFormatsESM
import OpenSkyGameData

extension StoryWorldAdapter {
    /// The author named these idles, so they play without their own conditions.
    func playResponseIdles(of info: FormID, speaker: ReferenceKey, listener: ReferenceKey?) {
        guard
            let dialogue = game.dialogue.runtime?.dialogue,
            let source = dialogue.responseSource(ofInfo: info)
        else { return }
        let resolver = dialogue.sourceResolver(ofInfo: source.formID)
        let responses = source.responses
        if let idle = responses.lazy.compactMap(\.speakerIdle).first.flatMap(resolver.resolve) {
            game.idles.fireIdle(idle, on: speaker, ignoringConditions: true)
        }
        if
            let listener, listener != speaker,
            let idle = responses.lazy.compactMap(\.listenerIdle).first.flatMap(resolver.resolve)
        {
            game.idles.fireIdle(idle, on: listener, ignoringConditions: true)
        }
    }
}
