// The port the `MusicType` natives reach the music director through. The app's script
// adapter conforms. See docs/engine/music.md.

import Foundation
import OpenSkyFormatsESM

@MainActor
public protocol PapyrusMusicControlling: AnyObject {
    /// `MusicType.Add`. False when the form is no music type with a playable track.
    @discardableResult
    func addMusic(_ music: ReferenceKey) -> Bool

    /// `MusicType.Remove`. A type that was never added changes nothing.
    func removeMusic(_ music: ReferenceKey)
}
