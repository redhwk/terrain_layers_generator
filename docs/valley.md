# Valley

See also [Terrain Generator](terrain_generator.md).
## For more details, see [Terrain Generator](terrain_generator.md)
## Valley
Always carves (Blend Mode hidden). Cyan centre line = floor; oval = banks.
- Length = along the cyan line (centre to each end; total ≈ Length × 2). Width = out to each bank
  (total ≈ Width × 2). Long canyon: Length ≫ Width. Width > Length = short wide bowl.
- Depth: carve depth. Floor Width: 0 = V, 0.35 = U, 0.55–0.7 = flat canyon floor.
- Rotation Y aims the cyan line. Keep the oval inside the yellow Area.

## Example: valleys by Area size (tested)
Place the Valley in the middle of the Area. Leave Falloff Curve empty. Press Generate on the Valley.
Ideal smallest: **512 x 512** (256 = short ravine).

| Area        | Edge Falloff | Depth | Length | Width | Floor | Warp | Roughness | Base noise H / Size | What you get        |
|-------------|--------------|-------|--------|-------|-------|------|-----------|---------------------|---------------------|
| 256 x 256   | 30           | 25    | 110    | 45    | 0.30  | 0.40 | 0.18      | 18 / 140            | Short ravine        |
| 512 x 512   | 80           | 45    | 220    | 90    | 0.35  | 0.35 | 0.15      | 30 / 260            | Valley / draw       |
| 1024 x 1024 | 150          | 70    | 420    | 140   | 0.40  | 0.35 | 0.15      | 45 / 420            | Canyon / long valley|

## Example: long canyon (512 x 1024 Area)
1. TerrainGenerator, Area Size 512 x 1024, Edge Falloff 80. Other shapes Enabled = false.
2. Valley at (0, 0, 0), Rotation Y = 90 (cyan line along the long axis).
3. Depth 55, Length 420, Width 90, Floor Width 0.55. Press Generate on the Valley.
   (Length 95 + Width 225 = short wide bowl, not a canyon.)

- Mountain pass: Generate the Mountain first, then Valley across it (Generate on the Valley only).
- Too knife-like: raise Floor Width. Too smooth: raise Roughness / Warp.