# Flatten

See also [Terrain Generator](terrain_generator.md).
## For more details, see [Terrain Generator](terrain_generator.md)
## Flatten
Levels ground toward Height for landing pads / base sites. Purple outline: outer = soft blend, inner =
fully flat. Always lerps toward Height (Blend Mode hidden). Soft edge uses smootherstep and
auto-widens near tall cliffs/banks (less stretched textures).
- Height: absolute elevation. **Pick Height** then click the terrain (Esc cancels), or **Set Height
  from Centre**. Requires the **Terrain Generator** editor plugin (Project Settings → Plugins).
- Radius: centre to outer edge. Edge Width: soft blend fraction of Radius (0.45 typical; 0.55–0.65
  if the pad meets a cliff). Natural Warp: keep low (0–0.2) for a clean pad.
- Keep the purple ring inside the pale yellow line.

## Example: pads by Area size (tested)
Generate hills (or leave existing ground), then Generate on the Flatten. Ideal smallest: **256 x 256**.

| Area        | Edge Falloff | Height | Radius | Edge Width | Warp | Scale (X,Y,Z) | What you get           |
|-------------|--------------|--------|--------|------------|------|---------------|------------------------|
| 256 x 256   | 30           | (pick) | 55     | 0.45       | 0.10 | 1.1, 1, 0.95  | Small pad / LZ         |
| 512 x 512   | 70           | (pick) | 90     | 0.45       | 0.12 | 1.2, 1, 0.9   | Base pad (recommended) |
| 1024 x 1024 | 140          | (pick) | 160    | 0.50       | 0.12 | 1.3, 1, 0.85  | Large base site        |

1. Area 512 x 512, Edge Falloff 70. Other shapes Enabled = false.
2. Move Flatten to the pad centre. **Pick Height** (or Set Height from Centre).
3. Use the 512 row. Press Generate on the Flatten.

- Stretched rim textures: raise Edge Width (0.55+) and Generate again.
- Harder edge: lower Edge Width toward 0.25. Wrong elevation: Pick Height again, then Generate.