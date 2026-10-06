// The Library destinations: full-content pages over files, not over the running world.
// Split out of `DestinationRegistry.swift` for the type-length cap.

import AppKit

extension DestinationRegistry {
    static let libraryDestinations: [DestinationDescriptor] = [
        DestinationDescriptor(
            id: "assetBrowser",
            title: "Asset Browser",
            section: .library,
            symbolName: "archivebox",
            content: .fullContent { context in
                let controller = PreviewViewController()
                controller.gameDataRoot = context.gameDataRoot
                controller.startupErrorMessage = context.startupErrorMessage
                return controller
            }
        ),
        DestinationDescriptor(
            id: "loadOrder",
            title: "Load Order",
            section: .library,
            symbolName: "list.number",
            content: .fullContent { context in
                let controller = LoadOrderViewController()
                controller.gameDataRoot = context.gameDataRoot
                controller.startupErrorMessage = context.startupErrorMessage
                return controller
            }
        ),
        DestinationDescriptor(
            id: "skyrimSaves",
            title: "Skyrim Saves",
            section: .library,
            symbolName: "tray.and.arrow.down",
            content: .fullContent { context in
                let controller = SkyrimSavesViewController()
                controller.gameDataRoot = context.gameDataRoot
                return controller
            }
        )
    ]
}
