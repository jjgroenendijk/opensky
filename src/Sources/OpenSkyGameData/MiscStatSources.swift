// The default objects some misc stats read: the bunny faction and the two globals
// that say the player is a vampire or a werewolf. See docs/engine/statistics.md.

public import OpenSkyFormatsESM

nonisolated public struct MiscStatSources: Equatable, Sendable {
    /// `AWWW`: a kill of a member raises Bunnies Slaughtered.
    public var bunnyFaction: ReferenceKey?
    /// `PIVV` and `PIWV`, in the load-order FormID space the globals use.
    public var playerIsVampire: FormID?
    public var playerIsWerewolf: FormID?

    public init(
        bunnyFaction: ReferenceKey? = nil,
        playerIsVampire: FormID? = nil,
        playerIsWerewolf: FormID? = nil
    ) {
        self.bunnyFaction = bunnyFaction
        self.playerIsVampire = playerIsVampire
        self.playerIsWerewolf = playerIsWerewolf
    }

    public init(loadOrder: LoadOrderPlugins) {
        let defaults = DefaultObjectStore(plugins: loadOrder.files)
        self.init(
            bunnyFaction: defaults.object(tag: "AWWW").map(ReferenceKey.init(resolved:)),
            playerIsVampire: defaults.object(tag: "PIVV")
                .flatMap { loadOrder.space.localFormID(of: $0) },
            playerIsWerewolf: defaults.object(tag: "PIWV")
                .flatMap { loadOrder.space.localFormID(of: $0) }
        )
    }
}
