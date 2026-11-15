# Island

See also [Terrain Generator](terrain_generator.md).
## For more details, see [Terrain Generator](terrain_generator.md)
## Island
Landmass with a shore forced down to Shore Height (sea / beach). Teal outline: outer = shore, inner =
start of the coastal drop. Always sets absolute heights inside the footprint (Blend Mode hidden) —
not stacked on hills.
- Height: interior elevation. Radius: centre to shore. Shore Width: coastal fraction of Radius
  (0.4 typical). Shore Height: usually 0.
- Scale X/Z stretches the footprint. Natural Warp = irregular coastline. Falloff Curve: leave empty.
- Tip: Base Height 0 (or negative) + Shore Height 0 so the beach meets the World Background. Enable
  Terrain3D ocean if you want water at sea level. Keep the teal ring inside the pale yellow line.

## Example: islands by Area size (tested)
Press Generate on the Island. Ideal smallest: **512 x 512**. Shore Height 0. Falloff Curve empty.

| Area        | Edge Falloff | Height | Radius | Shore Width | Warp | Roughness | Scale (X,Y,Z) | What you get        |
|-------------|--------------|--------|--------|-------------|------|-----------|---------------|---------------------|
| 256 x 256   | 30           | 18     | 90     | 0.45        | 0.30 | 0.16      | 1.15, 1, 0.9  | Islet               |
| 512 x 512   | 70           | 35     | 180    | 0.40        | 0.28 | 0.18      | 1.3, 1, 0.8   | Island (recommended)|
| 1024 x 1024 | 140          | 55     | 360    | 0.38        | 0.26 | 0.16      | 1.4, 1, 0.75  | Large island        |

1. Area 512 x 512, Edge Falloff 70, Base Height 0. Other shapes Enabled = false. Noise off for a
   clean island in flat sea; leave Noise on for hills outside the shore.
2. Use the 512 row. Press Generate on the Island.

- Wider beach: raise Shore Width. Steeper coast: lower it. More circular: Warp 0, Scale (1, 1, 1).