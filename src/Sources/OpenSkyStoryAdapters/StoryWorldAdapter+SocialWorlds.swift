public import OpenSkyFormatsESM
public import OpenSkyQuests

extension StoryWorldAdapter {
    /// Answers the social event pass from the social search part.
    public final class SocialWorlds: SocialEventWorld {
        let socialSearch: StorySocialSearchAdapter

        init(socialSearch: StorySocialSearchAdapter) {
            self.socialSearch = socialSearch
        }

        public func socialFrame(partners: [ReferenceKey]) -> SocialFrame? {
            socialSearch.socialFrame(partners: partners)
        }

        public func socialCanSee(_ observer: SocialActor, _ body: SocialActor) -> Bool {
            socialSearch.socialCanSee(observer, body)
        }
    }
}
