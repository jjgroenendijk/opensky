---
type: Subsystem
title: Celestial sky
description: The sun path and its light, the moons and their phases, the turning stars, and the
  aurora, with the settings and records they read and where OpenSky guesses.
tags: [engine, rendering, sky, weather]
---

# Celestial sky

Outdoors, with weather active, the sky draws the sun, its glare, Masser and Secunda, the stars,
and the aurora. The same sun path sets the direction of the sunlight and the shadows. Interiors
and frames without weather keep the fixed camera sun.

Sources:

- UESP "Skyrim Mod:Mod File Format/CLMT"
  (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CLMT>): the sun and glare textures
  (`FNAM`, `GNAM`), the night sky model (`MODL`, always `Sky\Stars.nif`), and `TNAM`, whose last
  byte holds the phase length in days (mask `0x3F`) and the Masser (`0x40`) and Secunda (`0x80`)
  flags.
- UESP "Skyrim Mod:Mod File Format/WTHR"
  (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WTHR>): the aurora model (`MODL`), the
  sun glare amount in `DATA`, and the `DATA` flag `0x10`, "Always Visible".
- The Creation Kit settings list (<https://ck.uesp.net/wiki/Category:Settings>): the names and
  default values of the settings below. It does not say what they mean.

`SkyrimClimate` in `Skyrim.esm` has sunrise 05:30 to 10:00, sunset 16:00 to 20:30, a moons byte
of `0xC3` (a 3-day phase, both moons), `Sky\Sun.dds`, `Sky\SunGlare.dds`, and `Sky\Stars.nif`.
The `_A` weathers, such as `SkyrimClear_A`, carry an aurora model.

## Settings

| Setting | `Skyrim.esm` | Used as |
| --- | --- | --- |
| `fSunXExtreme` | 400 | East-west reach and midday height of the sun's path, in sky units |
| `fSunYExtreme` | 40 | The path's offset to the north |
| `fSunZExtreme` | -150 | The fixed height of the light's source, negated |
| `fSunDirXExtreme` | 200 | East-west reach of the light's source |
| `fSunAlphaTransTime` | 0.5 | Game hours the sun disc fades in and out, centred on the horizon hours |
| `fSunMinimumGlareScale` | 0.25 | Lowest glare size; the weather's `DATA` sun glare raises it |
| `iMasserSize`, `iSecundaSize` | 90, 40 | Moon width in sky units, at the sun's distance |
| `fMasserAngleFadeStart`, `...End` | 35, 20 | Degrees of height along the moon's path where it starts and ends fading; Secunda's are the same |
| `fMasserSpeed`, `fSecundaSpeed` | 0.25, 0.3 (CK default) | Times 60: degrees the moon moves along its path per game hour |
| `fMasserZOffset`, `fSecundaZOffset` | 35, 50 (CK default) | Degrees the moon's path tilts east |
| `fStarsRotateDays` | 1.0027 | Days for one turn of the stars |
| `fStarsRotateXAxis`, `Y`, `Z` | -0.09, 0.35, 1 | The axis the stars turn about |
| `fAuroraFadeInStart`, `fAutoraFadeIn` | 19, 20 | Hours the aurora fades in |
| `fAuroraFadeOutStart`, `fAutoraFadeOut` | 5 (CK default), 6 | Hours the aurora fades out |
| `fWeatherTransAccel` | 16 | See [weather scripts](/engine/weather.md#scripts) |

Two settings are spelled "Autora" in the game. The game has no setting for the sun's size, so the
sun card is 0.12 and the glare card 1.0 across, as tangents at full glare. These are OpenSky values.

## The sun path

Behaviour described from a clean-room read of `SkyrimSE.exe` 1.7.104.0 on 2026-11-06
(only the behaviour was reported, no code). With `t` the game hour, `R` and `S` the middles
of the climate's sunrise and sunset windows, and `h` half of `fSunAlphaTransTime`:

```text
start = R - h, end = S + h, day = end - start
day:   s = 1 - 2 (t - start) / day                 (1 east, 0 overhead, -1 west)
night: s = 2 (hours since end) / (24 - day) - 1     (runs back from west to east)
disc  = (fSunXExtreme * s, fSunYExtreme, |fSunXExtreme| - |fSunXExtreme * s|)
light source = (disc.x * D / X, fSunYExtreme * D / X, -fSunZExtreme)
```

`X` is `fSunXExtreme` and `D` is `fSunDirXExtreme`, so with `Skyrim.esm` the source is
`(x / 2, 20, 150)`. The disc moves on a triangle, not a circle: it climbs in a straight
line from the east horizon to overhead at the middle of the day and falls to the west. By
night it runs back east above the horizon, hidden by its alpha: 0 outside `start` to `end`,
rising to 1 over `fSunAlphaTransTime` from `start`, and falling to 0 at `end`. The light
keeps a fixed height, so it never comes from lower than about 37 degrees, and by night it
swings back east with the disc. OpenSky still keeps the light above 10 degrees for settings
that would put it lower.

The reference game agrees: the sun rose at azimuth 80 to 84 and set at 276 to 281, north of
east and west, as `atan(40 / 400)` predicts (observed 2026-11-05). `GetSunPositionX/Y/Z` and
the sun gaze of `OnPlayerBowShot` read the same sun direction.

## Moons

Each moon shows when the climate's flag is set. The phase steps every phase-length days, in the
order full, three waning, half waning, one waning, new, one waxing, half waxing, three waxing. The
texture is `textures\sky\<moon>_<phase>.dds`, for example `masser_three_wan.dds`. Day 0 of the
game clock is a full moon. The reference game agreed with this on days 25, 30, and 33 (full,
half waning, one waning, with a phase length of 3). The game changes a moon's texture only while that
moon is hidden, so a phase never changes in view. OpenSky gives a moon in its visible arc the
phase of the moment it rose past its fade end. The game also allows the change in the last
half degree above the fade end by night, and at once during a cell load; OpenSky leaves both
out (clean-room read of `SkyrimSE.exe`, 2026-11-06).

A moon moves on a circle tilted east by its z offset. With `z` the offset and `a` the angle along
the path, its direction is `(sin z, cos z cos a, cos z sin a)`, with +X east, +Y north, and +Z
up. So Masser rises at azimuth 35 (north of east), is highest due east at 55 degrees, and sets at
azimuth 145. Secunda's path is lower: 40 degrees at most. The path angle does not follow the sun:

```text
a = speed * 60 degrees * game hours since day 0 + 90 degrees
```

Masser (speed 0.25) moves 15 degrees an hour, so it is highest at every midnight. Secunda
(0.3) moves 18 degrees an hour, so it comes up 4 hours earlier each day. All of this was
measured in the reference game through the bridge's `sky` state on 2026-11-05: over four game
days in 2-hour steps, the angle grew by exactly 30 and 36 degrees per step, and the east part
of each direction stayed at 0.574 and 0.766 (`.logs/issue-1678/forward.jsonl`, local only).

The game does not keep this angle in the save. It starts it at `speed * 60 * hour + 90`
degrees on its first sky update and then adds the hours that pass (clean-room read of
`SkyrimSE.exe`, 2026-11-06). For Masser both rules give the same angle. Secunda's angle in
the game depends on the hour the game was loaded, so it can stand elsewhere than in OpenSky.

A moon fades by its angle along its own tilted path: hidden below the fade end (20 degrees),
full above the fade start (35 degrees), linear in between, and the same on the way down to
180 degrees less the fade end. Its height above the horizon is
lower, because the path tilts. This was measured in the Windows reference game on 2026-11-05
through the bridge's `sky` state (`.logs/issue-1678/`, local only):

| Moon | Elevation | Path height | Alpha in the game | Rule |
| --- | --- | --- | --- | --- |
| Masser (tilt 35) | 18.3 | 22.6 | 0.173 | 0.17 |
| Masser | 24.3 | 30.2 | 0.674 | 0.68 |
| Secunda (tilt 50) | 17.0 | 27.0 | 0.475 | 0.47 |

The fade does not depend on the sun. A moon high on its path shows by day: Secunda stood at
full alpha at 17:00 in clear weather. Day moons look faint because of their colour, below.

## Stars and aurora

The stars are the climate's night sky model. They turn about the star axis once per
`fStarsRotateDays`, so a star on the east horizon climbs. Their colour is the weather's stars
colour (`NAM0` index 6), which is black by day in the vanilla weathers.

Each weather of the blend that has an aurora model draws it, faded by its blend weight and by the
hour: in from 19:00 to 20:00, out from 05:00 to 06:00. "Always Visible" (`DATA` flag `0x10`)
keeps it at full strength by day. Two weathers with the same model add their weights. For
"Follows Sun Position" (`0x20`), OpenSky turns the model about the up axis by the sun's bearing
from east; that reading of the flag is a guess. `DLC1Eclipse` is the vanilla weather with it.

## Drawing

The sky gradient goes by the height of the view ray above the horizon, not by the place on
the screen. The weather's horizon colour is at the horizon and below it, the sky-lower colour
at 17.5 degrees, and the sky-upper colour from 35 degrees up. So the horizon colour meets the
fogged far land at the true horizon, also when the camera looks down. The angles are OpenSky's:
a level view used to show this span from the bottom to the top of the screen.

The sky objects draw after the sky gradient and before the cloud layers, so clouds cover them.
They follow the camera and use no depth test. The order is stars, aurora, sun glare, sun, moons.
Stars, aurora, sun, and glare add light; a moon covers what is behind it. A star or aurora
shape shades as any effect mesh does: base colour, greyscale palette, view-angle falloff, and
vertex colour and alpha ([NIF materials](/formats/nif-materials.md)). It skips the soft fade and
the scene light, since nothing lies behind the sky. Before each moon,
`textures\sky\moonshadow.dds` paints the sky colour back where the moon will be, so stars do
not show through its dark side. The colour is the weather's sky-lower to sky-upper colour by the
moon's height, an approximation of the gradient behind it.

The models and textures load off the main actor. Until they land, that object does not draw.
`openskycli game state time` shows the sun, the light, the moons, the auroras, and the drawn object
count under `sky`. `openskycli render --weather <WTHR> --time-of-day <hour>` prints the same in its
`[INFO] sky` line.

A sky mesh's shader controllers play on the renderer's animation time, so the aurora streaks
scroll ([shader property controllers](/formats/nif-controllers.md#shader-property-controllers)).

The moon texture is added in the weather's moon glare colour (`NAM0` index 16) times the
moon's alpha, over its shadow card. In `SkyrimClear` that colour is (255, 165, 125) at night
and (68, 48, 38) by day. So a night moon is bright, and a day moon is a faint mark lighter than
the sky. The game reports exactly this colour on the moon's shape, and the reference captures
show no halo around either moon by day or by night (observed 2026-11-05). A weather without
index 16 adds the moon in white. `openskycli game state time` shows the colour as
`sky.moonGlare`.
