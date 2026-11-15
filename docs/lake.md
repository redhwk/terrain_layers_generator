# Lake

See also [Terrain Generator](terrain_generator.md).
## For more details, see [Terrain Generator](terrain_generator.md)
## Lake
Bowl carve with a flat bed and banks. Blue outline: outer = rim, inner = bed. Always Subtract
(Blend Mode hidden). Needs ground to carve into — Generate base hills first, then Generate on the Lake.
- Depth: carve depth. Radius: centre to shore. Floor Width: flat bed fraction (0.5 typical).
- Scale X/Z stretches the footprint. Natural Warp = irregular shoreline. Falloff Curve: leave empty.
- Valley = long canyons; Lake = round / oval basins. Keep the blue ring inside the pale yellow line.

## Example: lakes by Area size (tested)
Ideal smallest: **512 x 512**. Falloff Curve empty.

| Area        | Edge Falloff | Depth | Radius | Floor | Warp | Roughness | Scale (X,Y,Z) | Base H / Size | What you get       |
|-------------|--------------|-------|--------|-------|------|-----------|---------------|---------------|--------------------|
| 256 x 256   | 30           | 8     | 70     | 0.45  | 0.28 | 0.12      | 1.1, 1, 0.95  | 18 / 140      | Pond               |
| 512 x 512   | 70           | 14    | 120    | 0.50  | 0.26 | 0.12      | 1.25, 1, 0.85 | 25 / 260      | Lake (recommended) |
| 1024 x 1024 | 140          | 22    | 240    | 0.55  | 0.24 | 0.10      | 1.35, 1, 0.8  | 35 / 400      | Large lake         |

1. Area 512 x 512, Edge Falloff 70, Rolling Hills ~25 / 260. Generate base hills once.
2. Use the 512 row. Press Generate on the Lake.

## Rocky 256 pond (cliff autoshade)
Same as the 256 row, but Depth **20**, Warp **0.59**, Roughness **0.65**, Roughness Size **131**.
Deeper + rougher banks read as cliffs in Terrain Layers. Hand-paint the bed/shore if needed. Ocean
only fills basins near sea level — add a water plane for highland lakes.

- Wider bed: raise Floor Width. Steeper banks: lower Floor Width or raise Depth.