# Mesa

See also [Terrain Generator](terrain_generator.md).
## For more details, see [Terrain Generator](terrain_generator.md)
## Mesa
Flat-topped plateau: steep drop from the rim, softer talus at the foot. Gold outline: outer = foot,
inner = top rim. Always Max blend (Blend Mode hidden): Height is the plateau elevation.
- Real mesas are irregular, not perfect circles. Natural Warp wobbles the outline.
  **Scale** = Transform → Scale (X / Y / Z) — e.g. (1.4, 1, 0.75) for an elongated plateau.
- Radius: centre to foot. Top Width: flat fraction of Radius (0.72 typical, 0.65 butte, 0.82 wide table).
- Falloff Curve: leave empty (steep face + soft talus). Not the same as Edge Falloff.
- Natural Roughness: light top rolling + mid-cliff bumps (fades before the rim). 0 = table-flat.
- Keep the gold outer ring inside the pale yellow (Edge Falloff) line. Other shapes Enabled = false;
  optional: Generate base noise first for clean ground under the foot.

## Example: butte / mesa / plateau by Area size (tested)
Press Generate on the Mesa. Ideal smallest: **512 x 512**. Leave Falloff Curve empty.

| Area        | Edge Falloff | Height | Radius | Top Width | Warp | Roughness | Scale (X,Y,Z) | Base H / Size | What you get       |
|-------------|--------------|--------|--------|-----------|------|-----------|---------------|---------------|--------------------|
| 256 x 256   | 30           | 45     | 70     | 0.65      | 0.22 | 0.09      | 1.2, 1, 0.85  | 12 / 120      | Butte              |
| 512 x 512   | 70           | 70     | 170    | 0.72      | 0.22 | 0.09      | 1.4, 1, 0.75  | 25 / 260      | Mesa (recommended) |
| 1024 x 1024 | 140          | 110    | 320    | 0.78      | 0.20 | 0.08      | 1.5, 1, 0.7   | 35 / 400      | Large plateau      |

## Example: recommended 512 mesa
1. TerrainGenerator, Area 512 x 512, Edge Falloff 70. Other shapes Enabled = false.
2. Optional: Generate on the TerrainGenerator once for clean base hills.
3. Mesa: Height 70, Radius 170, Top Width 0.72, Warp 0.22, Roughness 0.09,
   Transform Scale (1.4, 1, 0.75), Falloff Curve empty.
4. Press Generate on the Mesa.

- More circular: Warp 0 and Scale (1, 1, 1). More elongated: raise Scale X, lower Scale Z.
- Cliffs too soft: raise Top Width or Height. Table-flat top: Roughness 0.