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

    /// Steam's browser draws nothing under Wine with its sandbox or a separate GPU
    /// process. `-noverifyfiles` keeps Steam from restoring its own web helper, but
    /// the first start needs the check to download the client.
    public static func steamArguments(clientDownloaded: Bool) -> [String] {
        [ReferencePrefix.steamWindowsPath, "-no-cef-sandbox", "-cef-single-process"]
            + (clientDownloaded ? ["-noverifyfiles"] : [])
    }

    /// Wine's own `bcrypt` and `ncrypt` keep Steam's login working. The Steam overlay
    /// stays off, and `winemenubuilder` cannot write into the macOS home folder. The Metal HUD
    /// stays off, because it changes the captured image.
    public static func environment(prefix: URL, base: [String: String]) -> [String: String] {
        var environment = base
        environment["WINEPREFIX"] = prefix.path(percentEncoded: false)
        environment["WINEDEBUG"] = "-all"
        environment["WINEDLLOVERRIDES"] =
            "bcrypt=b;ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d;winemenubuilder.exe=d"
        environment["MTL_HUD_ENABLED"] = "0"
        return environment
    }

    public init(
        prefix: ReferencePrefix, wine: URL, baseEnvironment: [String: String],
        clientDownloaded: Bool
    ) {
        steam = ReferenceProcess(
            executable: wine, arguments: Self.steamArguments(clientDownloaded: clientDownloaded),
            workingDirectory: prefix.steamDirectory
        )
        game = ReferenceProcess(
            executable: wine, arguments: [ReferencePrefix.gameWindowsPath],
            workingDirectory: prefix.gameDirectory
        )
        environment = Self.environment(prefix: prefix.root, base: baseEnvironment)
    }
}
