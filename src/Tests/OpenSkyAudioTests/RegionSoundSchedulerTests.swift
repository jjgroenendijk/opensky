import OpenSkyAudio
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import Testing

struct RegionSoundSchedulerTests {
    private let wind = RegionSound(entry: AmbienceBed.Entry(sound: FormID(1)), loops: true)
    private let gust = RegionSound(
        entry: AmbienceBed.Entry(sound: FormID(2), chance: 0.5), loops: false
    )
    private let bird = RegionSound(
        entry: AmbienceBed.Entry(sound: FormID(3), chance: 1), loops: false
    )

    @Test func onlyLoopingSoundsStartAsLoops() {
        var scheduler = RegionSoundScheduler(seed: 7)
        let commands = scheduler.replace([wind, gust, bird]) { _ in true }
        #expect(commands.startLoops == [FormID(1)])
        #expect(commands.oneShot == nil)
    }

    @Test func oneShotsWaitForARoll() {
        var scheduler = RegionSoundScheduler(seed: 7)
        _ = scheduler.replace([bird]) { _ in true }
        let early = scheduler.advance(deltaTime: 0.5) { _ in true }
        #expect(early.oneShot == nil)
        let late = scheduler.advance(deltaTime: 5) { _ in true }
        #expect(late.oneShot == FormID(3))
    }

    @Test func aRareOneShotPlaysAboutAsOftenAsItsChance() {
        var scheduler = RegionSoundScheduler(seed: 11)
        _ = scheduler.replace([gust]) { _ in true }
        let plays = (0 ..< 1000).count { _ in
            scheduler.advance(deltaTime: 5) { _ in true }.oneShot != nil
        }
        #expect((400 ... 600).contains(plays))
    }

    @Test func aBlockedLoopStopsAtTheNextRoll() {
        var scheduler = RegionSoundScheduler(seed: 7)
        _ = scheduler.replace([wind]) { _ in true }
        let commands = scheduler.advance(deltaTime: 5) { _ in false }
        #expect(commands.stopLoops == [FormID(1)])
        #expect(scheduler.playingLoops.isEmpty)
    }

    @Test func aNewBedStopsTheOldLoops() {
        var scheduler = RegionSoundScheduler(seed: 7)
        _ = scheduler.replace([wind]) { _ in true }
        let commands = scheduler.replace([]) { _ in true }
        #expect(commands.stopLoops == [FormID(1)])
        #expect(commands.startLoops.isEmpty)
    }

    @Test func pickStaysInsideTheList() {
        var scheduler = RegionSoundScheduler(seed: 3)
        let picks = (0 ..< 100).map { _ in scheduler.pick(count: 3) }
        #expect(Set(picks) == [0, 1, 2])
        #expect(scheduler.pick(count: 0) == 0)
    }
}
