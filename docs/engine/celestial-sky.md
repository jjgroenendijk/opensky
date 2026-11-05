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
| `fSunXExtreme` | 400 | East-west reach and midday height of the sun's circle, in sky units |
| `fSunYExtreme` | 40 | The circle's offset to the south |
| `fSunZExtreme` | -150 | How far below the horizon the sun is at midnight |
| `fSunDirXExtreme` | 200 | East-west reach of the light's circle |
| `fSunAlphaTransTime` | 0.5 | Game hours the sun disc fades in after rising and out before setting |
| `fSunMinimumGlareScale` | 0.25 | Lowest glare size; the weather's `DATA` sun glare raises it |
| `iMasserSize`, `iSecundaSize` | 90, 40 | Moon width in sky units, at the sun's distance |
| `fMasserAngleFadeStart`, `...End` | 35, 20 | Degrees from the sun where the moon starts and ends fading |
| `fMasserSpeed`, `fSecundaSpeed` | 0.25, 0.3 (CK default) | Half turns the moon trails the point opposite the sun |
| `fMasserZOffset`, `fSecundaZOffset` | 35, 50 (CK default) | Degrees the moon's path tilts south |
| `fStarsRotateDays` | 1.0027 | Days for one turn of the stars |
| `fStarsRotateXAxis`, `Y`, `Z` | -0.09, 0.35, 1 | The axis the stars turn about |
| `fAuroraFadeInStart`, `fAutoraFadeIn` | 19, 20 | Hours the aurora fades in |
| `fAuroraFadeOutStart`, `fAutoraFadeOut` | 5 (CK default), 6 | Hours the aurora fades out |
| `fWeatherTransAccel` | 16 | See [weather scripts](/engine/weather.md#scripts) |

Two settings are spelled "Autora" in the game. The game has no setting for the sun's size, so the
sun card is 0.12 and the glare card 1.0 across, as tangents at full glare. These are OpenSky values.

## The sun path

The sun is on the east horizon (+X) at the middle of the sunrise window and on the west horizon at
the middle of the sunset window. By day it moves on a half circle of radius `fSunXExtreme`. By night
it moves on, below the horizon, down to `fSunZExtreme` at the middle of the night.

The light uses the same path with `fSunDirXExtreme` as its reach, so the light stays steeper than
the sun disc. By night the light comes from the night path mirrored above the horizon, like
moonlight, so it moves without a jump at sunset and sunrise. The light never comes from lower than
10 degrees, so shadows stay finite. Both rules are OpenSky's.

[WARNING] The settings list gives only values. The circle shapes above are OpenSky's reading of the
setting names, not observed behaviour. `GetSunPositionX/Y/Z` and the sun gaze of `OnPlayerBowShot`
read the same sun direction.

## Moons

Each moon shows when the climate's flag is set. The phase steps every phase-length days, in the
order full, three waning, half waning, one waning, new, one waxing, half waxing, three waxing. The
texture is `textures\sky\<moon>_<phase>.dds`, for example `masser_three_wan.dds`. Day 0 of the
game clock is a full moon; the game's start phase is not known.

A moon sits opposite the sun on a circle, trails that point by its speed setting, and its circle
tilts south by its z offset setting. It fades by its angle to the sun, between the fade start and
end settings, and below the horizon. [WARNING] The position rules are OpenSky's reading of the
setting names.

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

Each moon gets a glare card behind it, drawn with the climate's glare texture and added in
the weather's moon glare colour (`NAM0` index 16) times the moon's alpha. The card is
`Renderer.moonGlareScale` (4) moon widths across. That size is OpenSky's, and so is the use of
the sun glare texture. `openskycli game state time` shows the colour as `sky.moonGlare`.
