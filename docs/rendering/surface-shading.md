---
type: Subsystem
title: Surface shading
description: How the lit static and skinned mesh shader applies normal maps, specular, glow,
  soft, rim and back light, face tints, reflections, parallax, and tint colours, and where the
  model comes from.
tags: [rendering, metal, shading, material, engine]
---

# Surface shading

The lit mesh fragment (`staticMeshFragment`) shades every static, skinned, and FaceGen mesh.
Which terms a material has comes from its NIF shader flags and texture slots
([NIF materials](/formats/nif-materials.md), "Lit-surface terms").

Reference: NifSkope's open GLSL shaders `sk_default.frag`, `sk_msn.frag`, and
`sk_multilayer.frag` (<https://github.com/niftools/nifskope>, `res/shaders`), with the flag
rules in `src/gl/glproperty.cpp`. OpenSky follows their formulas. They are an approximation
of the game, not the game's own shaders.

## Normals

The vertex layout has no tangents. The fragment builds the tangent frame from screen-space
derivatives of the world position and the texture coordinate (a cotangent frame). The
tangent follows +u and the bitangent +v, so mirrored UVs work without a sign bit.

A probe of the real install checked the NIF tangents against the UV directions. On
`malebody_1.nif` and `farmhouse01.nif` the stored "tangent" follows +v (dot product 0.93 to
1.00) and the "bitangent" follows +u (0.95 to 0.99). NifSkope maps normal-map red to the
bitangent and green to the tangent, so red follows +u and green +v, as in OpenSky.

A model-space normal map (`_msn`, SLSF1 bit 12) stores the normal in model space, not
tangent space. Its channels are x in red, z in green, and y in blue. The probe compared the
head map `malehead_msn.dds` with the head mesh normals for all 48 axis orders and signs: this
order with all signs positive scored 0.878, the next best 0.545. The vertex shader passes the
model-to-world rotation, including the blended bone rotation of a skinned mesh, so the
fragment can turn the normal into world space.

A model-space shape stores no vertex normals. Ralof's head mesh `MaleHeadNord` has 898
vertices and none. With the default up normal on every vertex, the head would light flat.
OpenSky builds smooth vertex normals from the triangles, so the shadow offset and the
lighting without the normal map have a real normal.

## Lights

Each light, the sun and the eight nearest point lights, adds:

| Term | Per light | Scaled by |
| --- | --- | --- |
| Diffuse | `colour * max(N.L, 0)` | Albedo |
| Specular | `colour * pow(max(N.H, 0), glossiness)` | Specular colour times strength, times the normal alpha or the slot 7 specular map |
| Back light | `colour * max(-N.L, 0)` | Albedo times the slot 7 back light map |
| Rim light | `colour * pow(1 - N.V, LE2) * smoothstep(-0.2, 1, -L.V)` | Albedo times the slot 2 light mask |
| Soft light | `colour * wrap * smoothstep(1, 0, N.L) * sqrt(LE1)` with `wrap = max((N.L + LE1) / (1 + LE1), 0)` | Albedo times the slot 2 light mask |

LE1 and LE2 are the two lighting effect floats of the shader property. Ambient is the
six-axis directional ambient (`DALC`), plus the single ambient colour while "Base ambient
light" is on. The emissive colour times its multiple adds to the light, scaled by the slot 2
glow map on a glow shape. The sun terms use the sun shadow.

## Albedo

The albedo starts as diffuse times vertex colour. Then, in this order:

1. Multi-layer parallax mixes in the slot 6 inner layer, seen through a refracted view ray.
   The outer layer wins where the view is grazing or the diffuse alpha is high.
2. FaceGen: the slot 3 detail map, then the slot 6 face tint, overlay-blend over the albedo,
   and the result doubles where a detail map is used. These steps run in gamma space.
3. The environment cube map adds its reflection, times the environment scale and the slot 5
   mask (or the normal alpha without a mask).
4. A hair tint colour multiplies the albedo. A skin tint colour (shader type 5) overlays
   it in gamma space instead, the same blend as the face tint.

The skin tint is the actor's `QNAM` colour, or the NIF's own tint colour without one.
NifSkope multiplies it, but a multiply darkens the body far below the head: Ralof's
`QNAM` is (0.78, 0.69, 0.66), which multiplies the body by about 0.5 in linear space,
while the overlaid face tint brightens the head. The game shows no seam at the neck, so
OpenSky blends the body like the face. This is a match to observed output, not a
confirmed game formula.

Parallax (type 3) shifts the texture coordinate before any sampling:
`uv += V.xy * (height * 0.08 - 0.04)`, with V the view direction in the tangent frame.

Skyrim cube maps are DirectX cubes, Y up and left-handed. The world is Z up and
right-handed, so the lookup swaps Y and Z.

## Gamma

The game shades in gamma space. OpenSky samples sRGB textures into linear values, so a
colour that the game multiplies in gamma space must be made linear first. Vertex colours,
which hold baked ambient occlusion and the hair colour, and the hair tint colour are
raised to the power 2.2 while "Vertex colours in gamma space" is on. The terrain's `LAND`
vertex colours and the grass tint follow the same switch, and so does the base ambient
switch for terrain, grass, and decals. Without that, a vertex
colour of 0.5 darkens a surface to 0.5 of its linear value instead of about 0.22, and baked
shading looks washed out and grey.

## Controls

`World > Environment > Surface Shading` has one switch per term group and counts the scene
draws that use each. The launcher's Graphics page has the same switches under "Surface
shading". Both write the `rendering.shading.*` player settings. A frame applies the switches
as a mask over each material's terms, so turning a term off costs no rebuild.

## Not modelled

- Anisotropic hair specular (SLSF2 bit 21). NifSkope has no model for it, so hair uses the
  plain specular.
- Parallax occlusion (type 7) and sparkle snow (type 14). Their tails are skipped.
- Refraction shapes are still skipped ([NIF materials](/formats/nif-materials.md)).
