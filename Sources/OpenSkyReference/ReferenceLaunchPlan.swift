// How the reference game starts: Windows Steam first, because the game's copy
// protection needs a logged-in client, then `SkyrimSE.exe` straight from its folder,
// so Steam does not open the game's launcher window.

import Foundation

nonisolated public struct ReferenceProcess: Equatable, Sendable {
    public var executable: URL
    public var arguments: [String]
    public var workingDirectory: URL
}

nonisolated public struct ReferenceLaunchPlan: Equatable, Sendable {
    public var steam: ReferenceProcess
    public var game: ReferenceProcess
    public var environment: [String: String]

    /// `WINEMSYNC` makes thread waits faster. The Metal HUD and MetalFX upscaling stay
    /// off, because both change the captured image.
    public static func environment(prefix: URL, base: [String: String]) -> [String: String] {
        var environment = base
        environment["WINEPREFIX"] = prefix.path(percentEncoded: false)
        environment["WINEMSYNC"] = "1"
        environment["WINEDEBUG"] = "-all"
        environment["MTL_HUD_ENABLED"] = "0"
        environment["D3DM_ENABLE_METALFX"] = "0"
        return environment
    }

    public init(prefix: ReferencePrefix, wine: URL, baseEnvironment: [String: String]) {
        steam = ReferenceProcess(
            executable: wine, arguments: [ReferencePrefix.steamWindowsPath, "-silent"],
            workingDirectory: prefix.steamDirectory
        )
        game = ReferenceProcess(
            executable: wine, arguments: [ReferencePrefix.gameWindowsPath],
            workingDirectory: prefix.gameDirectory
        )
        environment = Self.environment(prefix: prefix.root, base: baseEnvironment)
    }
}
