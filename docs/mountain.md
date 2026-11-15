# Mountain

See also [Terrain Generator](terrain_generator.md).
## For more details, see [Terrain Generator](terrain_generator.md)
## Mountain
Orange outline = footprint. Height = peak above the base noise (with Blend Mode Add). Radius = centre
to foot. Keep the outline inside the yellow Area (leave a margin for Edge Falloff).
- Natural Warp (default ~0.35): breaks the perfect circle (stops the pyramid look).
- Natural Roughness: bumpy slopes. Falloff Curve: leave empty.
- Blend Mode Add + Rolling Hills: the mountain sits on hills. Max: Height is absolute elevation.

## Example: mountains by Area size (tested)
Rule of thumb: Height ≈ 0.45 × Radius. Radius ≈ 35–40% of Area width. Leave Falloff Curve empty.
Press Generate on the Mountain. Ideal smallest: **512 x 512** (256 = knoll, not a full peak).

| Area        | Edge Falloff | Height | Radius | Warp | Roughness | Base noise H / Size | What you get     |
|-------------|--------------|--------|--------|------|-----------|---------------------|------------------|
| 256 x 256   | 30           | 45     | 95     | 0.40 | 0.25      | 18 / 140            | Rocky knoll      |
| 512 x 512   | 80           | 110    | 200    | 0.38 | 0.22      | 30 / 260            | Small mountain   |
| 1024 x 1024 | 150          | 180    | 380    | 0.35 | 0.20      | 45 / 420            | Natural mountain |

- Ridge: Scale (1.4, 1, 0.7), or two Mountains a few hundred meters apart; Generate on each.
- Too pyramid-like: raise Warp, lower Height, or enlarge Area.