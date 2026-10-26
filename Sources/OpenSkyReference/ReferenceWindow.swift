// Which on-screen window is the reference game. Wine names its processes after itself
// or after the Windows program, so both count. A window of the size the game was given
// wins; otherwise the biggest such window wins over Steam's.

import Foundation

nonisolated public struct ReferenceWindowInfo: Equatable, Sendable {
    public var id: UInt32
    public var ownerName: String
    public var layer: Int
    public var width: Double
    public var height: Double
    /// The top left corner, in top-left screen points.
    public var x: Double
    public var y: Double
    /// The process that owns the window, whose windows the launcher moves.
    public var ownerPID: Int32

    public init(
        id: UInt32, ownerName: String, layer: Int, width: Double, height: Double,
        x: Double = 0, y: Double = 0, ownerPID: Int32 = 0
    ) {
        self.id = id
        self.ownerName = ownerName
        self.layer = layer
        self.width = width
        self.height = height
        self.x = x
        self.y = y
        self.ownerPID = ownerPID
    }

    public func isPlaced(at frame: ReferenceWindowFrame) -> Bool {
        Int(x) == frame.x && Int(y) == frame.y
            && Int(width) == frame.width && Int(height) == frame.height
    }
}

nonisolated public enum ReferenceWindow {
    static let ownerHints = ["wine", "skyrim"]

    public static func pick(
        _ windows: [ReferenceWindowInfo], expected: ReferenceWindowFrame? = nil
    ) -> ReferenceWindowInfo? {
        let candidates = windows.filter { window in
            window.layer == 0
                && ownerHints.contains { window.ownerName.lowercased().contains($0) }
        }
        if
            let expected,
            let match = candidates.first(where: {
                Int($0.width) == expected.width && Int($0.height) == expected.height
            })
        {
            return match
        }
        return candidates.max { $0.width * $0.height < $1.width * $1.height }
    }

    /// `appmanifest_489830.acf` two folders above a Steam game folder.
    public static func manifest(forInstall install: URL) -> URL {
        install.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "appmanifest_\(ReferencePrefix.appID).acf")
    }
}
