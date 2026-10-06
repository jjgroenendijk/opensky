// The main menu movie's Load list: characters, their saves, the picture of the
// highlighted save, and the confirmed load. See docs/engine/main-menu.md.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyRendering

extension TitleMenuCoordinator {
    /// One answer can make the movie call again, such as the first highlight after
    /// the save list fills, so this repeats a few rounds.
    static let loadCallRounds = 4

    /// Steps the movie, then answers what it asked for in those frames.
    public func tick(now: Double) {
        guard movieLoaded, let renderer = world?.renderer else {
            framePacer = MenuMovieFramePacer()
            return
        }
        let rate = Double(renderer.swfRuntime?.movie.frameRate ?? 0)
        do {
            for _ in 0 ..< framePacer.ticks(at: now, frameRate: rate) {
                try renderer.advanceSWFRuntime()
            }
            renderer.swfRuntime.map(TitleMenuMovieBridge.followStateFocus(runtime:))
        } catch {
            movieError = String(describing: error)
        }
        answerLoadCalls(renderer: renderer)
        if let request = pendingRequest {
            pendingRequest = nil
            apply(request)
        }
    }

    func answerLoadCalls(renderer: Renderer) {
        for _ in 0 ..< Self.loadCallRounds where !pendingLoadCalls.isEmpty {
            let calls = pendingLoadCalls
            pendingLoadCalls = []
            for call in calls {
                answer(call, renderer: renderer)
            }
        }
    }

    private func answer(_ call: TitleMenuLoadBridge.Call, renderer: Renderer) {
        let rows = saves?.saveRows ?? []
        let index = call.index
        switch call.request {
        case .characters:
            let names = TitleMenuLoadBridge.characters(rows)
            try? renderer.updateSWFRuntime {
                TitleMenuLoadBridge.fillCharacters(names, runtime: $0)
            }
        case .characterSelected:
            let names = TitleMenuLoadBridge.characters(rows)
            let name = index.flatMap { names.indices.contains($0) ? names[$0] : nil }
            loadListRows = name.map { TitleMenuLoadBridge.saves(of: $0, in: rows) } ?? []
            let saves = loadListRows
            try? renderer.updateSWFRuntime {
                TitleMenuLoadBridge.fillSaves(saves, runtime: $0)
            }
        case .screenshot:
            renderer.replaceSWFImage(
                TitleMenuLoadBridge.screenshotSlot,
                rgba: TitleMenuLoadBridge.screenshotPixels(loadListRow(index)?.picture),
                width: TitleMenuLoadBridge.screenshotWidth,
                height: TitleMenuLoadBridge.screenshotHeight
            )
            try? renderer.updateSWFRuntime { $0.callMovie("ScreenshotReady") }
        case .confirmLoad:
            try? renderer.updateSWFRuntime { $0.callMovie("ConfirmOKToLoad") }
        case .load:
            guard let row = loadListRow(index) else { return }
            load(row.slot)
        case .delete:
            lastResult = "Delete: use the System menu"
        case .back, .stopLoading:
            break
        }
    }

    private func loadListRow(_ index: Int?) -> SaveSlotRow? {
        index.flatMap { loadListRows.indices.contains($0) ? loadListRows[$0] : nil }
    }
}
