// One comparison run: both captures at one size, their difference, the batch file of the
// view, and a report. The app's Reference Game page and `openskycli reference capture` share
// it. Captures show game assets, so they never enter the repo (root AGENTS.md).

import Foundation
import OpenSkyReference
import OpenSkyRenderResources

nonisolated public enum ReferenceComparisonCapture {
    /// `captureOpenSky` writes OpenSky's world, without the interface, to the URL at `frame`'s
    /// size. The reference window is captured after it and scaled to the same size.
    public static func capture(
        into run: ReferenceComparisonRun, view: ReferenceView, frame: ReferenceWindowFrame,
        captureOpenSky: (URL) throws -> Void
    ) throws -> ReferenceComparisonReport {
        let size = (width: frame.width, height: frame.height)
        try captureOpenSky(run.openskyImage)
        let raw = run.directory.appending(path: "reference-window.png")
        try ReferenceWindowCapture.capture(to: raw, expected: frame)
        let reference = try TexturePixels(contentsOf: raw, size: size)
        try? FileManager.default.removeItem(at: raw)
        let opensky = try TexturePixels(contentsOf: run.openskyImage, size: size)
        try write(reference, to: run.referenceImage)
        let difference = try TextureImageDifference.compare(
            reference: reference, candidate: opensky, normals: false
        )
        try write(
            TexturePixels.difference(reference: reference, candidate: opensky),
            to: run.differenceImage
        )
        let report = ReferenceComparisonReport(
            view: view, width: size.width, height: size.height,
            rgbPSNR: difference.rgbPSNR, maxChannelError: difference.maxChannelError
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: run.report)
        ReferenceSettings.storeLatestRun(run.directory)
        return report
    }

    private static func write(_ pixels: TexturePixels, to url: URL) throws {
        guard let image = pixels.cgImage() else {
            throw ReferenceCaptureError.encodeFailed(url.lastPathComponent)
        }
        try FrameScreenshot.write(image: image, to: url)
    }
}
