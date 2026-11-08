// A heavy splash leaves the strongest ripple; lighter ones leave a smaller one.

import OpenSkyCombatInterface
import Testing

struct SplashRippleTests {
    @Test
    func onlyAHeavySplashRipplesFully() {
        #expect(SplashWeight.heavy.rippleStrength == 1)
        #expect(SplashWeight.light.rippleStrength < 1)
        #expect(SplashWeight.medium.rippleStrength == SplashWeight.light.rippleStrength)
    }
}
