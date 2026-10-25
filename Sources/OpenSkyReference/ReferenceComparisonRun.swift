// One comparison run: the files `openskycli reference capture` writes into its run
// folder and the launcher page reads back.

import Foundation

nonisolated public struct ReferenceComparisonRun: Equatable, Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var openskyImage: URL {
        directory.appending(path: "opensky.png")
    }

    public var referenceImage: URL {
        directory.appending(path: "reference.png")
    }

    public var differenceImage: URL {
        directory.appending(path: "difference.png")
    }

    public var batchFile: URL {
        directory.appending(path: ReferenceConsoleBatch.defaultName + ".txt")
    }

    public var report: URL {
        directory.appending(path: "report.json")
    }

    public func readReport() -> ReferenceComparisonReport? {
        guard let data = try? Data(contentsOf: report) else { return nil }
        return try? JSONDecoder().decode(ReferenceComparisonReport.self, from: data)
    }
}

nonisolated public struct ReferenceComparisonReport: Codable, Equatable, Sendable {
    public var view: ReferenceView
    public var width: Int
    public var height: Int
    /// Over R, G, and B. Only a rough signal between two engines.
    public var rgbPSNR: Double
    public var maxChannelError: Int

    public init(
        view: ReferenceView,
        width: Int,
        height: Int,
        rgbPSNR: Double,
        maxChannelError: Int
    ) {
        self.view = view
        self.width = width
        self.height = height
        self.rgbPSNR = rgbPSNR
        self.maxChannelError = maxChannelError
    }

    public var summary: String {
        String(
            format: "%d x %d, PSNR %.1f dB, largest channel error %d",
            width, height, rgbPSNR, maxChannelError
        )
    }
}
