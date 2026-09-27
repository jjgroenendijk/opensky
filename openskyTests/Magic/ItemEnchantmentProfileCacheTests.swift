// The memoized side of `enchantmentProfile(of:)` (issue #489): an equipped item
// is resolved out of the records once, every later ask reuses that answer, and a
// rewire drops the lot.
//
// Asserted through the same synthetic plugin the runtime suites use, so what is
// cached is a real resolution rather than a stand-in.

@testable import opensky
import Testing

@MainActor
struct ItemEnchantmentProfileCacheTests {
    /// Counts how often the cache had to go to the records, which is the whole
    /// claim: once per item, however many frames ask.
    private struct Resolver {
        let world: EnchantmentRuntimeFixture.World
        private(set) var calls = 0

        mutating func profile(
            of item: FormID,
            in cache: inout ItemEnchantmentProfileCache
        ) -> ItemEnchantmentProfile? {
            cache.profile(of: item) { item in
                calls += 1
                guard let definition = world.items.definition(item) else { return nil }
                return ItemEnchantmentProfile.resolve(definition, using: world.enchantments)
            }
        }
    }

    @Test
    func anItemIsResolvedOnceAndReusedAfterwards() throws {
        var resolver = try Resolver(world: EnchantmentRuntimeFixture.world())
        var cache = ItemEnchantmentProfileCache()
        let blade = FormID(EnchantmentRuntimeFixture.enchantedBlade)

        let first = try #require(resolver.profile(of: blade, in: &cache))
        for _ in 0 ..< 9 {
            #expect(resolver.profile(of: blade, in: &cache) == first)
        }

        #expect(resolver.calls == 1)
        #expect(cache.resolvedCount == 1)
        #expect(cache.reuseCount == 9)
        #expect(cache.count == 1)
    }

    /// The lookups the frame hooks repeat most are the ones that answer nothing:
    /// an unenchanted weapon must not walk the records again every frame.
    @Test
    func anItemCarryingNoEnchantmentIsCachedToo() throws {
        var resolver = try Resolver(world: EnchantmentRuntimeFixture.world())
        var cache = ItemEnchantmentProfileCache()
        let plain = FormID(EnchantmentRuntimeFixture.plainBlade)

        #expect(resolver.profile(of: plain, in: &cache) == nil)
        #expect(resolver.profile(of: plain, in: &cache) == nil)

        #expect(resolver.calls == 1)
        #expect(cache.count == 1)
        #expect(cache.reuseCount == 1)
    }

    /// Each item gets its own entry, and the profile handed back is the one that
    /// item resolves to rather than whichever was asked for first.
    @Test
    func separateItemsKeepSeparateEntries() throws {
        var resolver = try Resolver(world: EnchantmentRuntimeFixture.world())
        var cache = ItemEnchantmentProfileCache()
        let blade = FormID(EnchantmentRuntimeFixture.enchantedBlade)
        let ring = FormID(EnchantmentRuntimeFixture.enchantedRing)

        let bladeProfile = try #require(resolver.profile(of: blade, in: &cache))
        let ringProfile = try #require(resolver.profile(of: ring, in: &cache))

        #expect(bladeProfile.isContact)
        #expect(ringProfile.isWorn)
        #expect(resolver.profile(of: blade, in: &cache) == bladeProfile)
        #expect(resolver.calls == 2)
        #expect(cache.count == 2)
    }

    /// What rewiring the ENCH store does: every entry goes, and the tallies go
    /// with them so the readout describes the wiring in front of it.
    @Test
    func invalidationDropsEveryEntryAndBothTallies() throws {
        var resolver = try Resolver(world: EnchantmentRuntimeFixture.world())
        var cache = ItemEnchantmentProfileCache()
        let blade = FormID(EnchantmentRuntimeFixture.enchantedBlade)

        _ = resolver.profile(of: blade, in: &cache)
        _ = resolver.profile(of: blade, in: &cache)
        cache.invalidate()

        #expect(cache.isEmpty)
        #expect(cache.resolvedCount == 0)
        #expect(cache.reuseCount == 0)
        #expect(cache.readout == .empty)

        _ = resolver.profile(of: blade, in: &cache)
        #expect(resolver.calls == 2)
    }

    @Test
    func theReadoutLineStatesHoldingsResolutionsAndReuse() {
        let readout = EnchantmentCacheReadout(itemCount: 3, resolvedCount: 3, reuseCount: 412)
        #expect(readout.describedLine == "Enchantment cache: 3 item(s), 3 resolved, 412 reused")
        #expect(EnchantmentCacheReadout.empty.describedLine
            == "Enchantment cache: 0 item(s), 0 resolved, 0 reused")
    }
}
