// What the launcher's Continue button offers: the newest OpenSky save and its
// summary, or why there is nothing to continue. Skyrim saves join when M29 lands.

import Foundation

nonisolated public struct ContinueOffer: Equatable, Sendable {
    /// The slot Continue loads; nil when the button is disabled.
    public let slot: String?
    /// `Lydia, level 12, Whiterun` for a save with a summary.
    public let title: String
    public let date: Date?
    /// Why the button is disabled.
    public let disabledReason: String?

    public var isEnabled: Bool {
        slot != nil
    }

    public static let noSaves = Self(
        slot: nil, title: "No saves yet", date: nil, disabledReason: "No saves yet"
    )

    /// The newest listing by file date decides, even when it cannot be read: an
    /// older save would silently lose the player's latest progress.
    public init(listings: [OpenSkySaveSlotListing]) {
        guard let newest = listings.max(by: { ($0.modified, $1.slot) < ($1.modified, $0.slot) })
        else {
            self = .noSaves
            return
        }
        guard newest.error == nil, newest.summary != nil else {
            self.init(
                slot: nil, title: newest.slot, date: newest.modified,
                disabledReason: "The newest save, \(newest.slot), cannot be read"
            )
            return
        }
        let title = newest.summary?.summary.map { summary in
            [summary.characterName, "level \(summary.level)", summary.locationName]
                .filter { !$0.isEmpty }.joined(separator: ", ")
        } ?? newest.slot
        self.init(slot: newest.slot, title: title, date: newest.modified, disabledReason: nil)
    }

    public init(slot: String?, title: String, date: Date?, disabledReason: String?) {
        self.slot = slot
        self.title = title
        self.date = date
        self.disabledReason = disabledReason
    }
}

nonisolated extension OpenSkySaveStore {
    /// Reads the list chunks of every slot off the main actor.
    @concurrent
    public static func continueOffer() async -> ContinueOffer {
        guard let store = try? defaultStore(), let listings = try? store.listings() else {
            return .noSaves
        }
        return ContinueOffer(listings: listings)
    }
}
