# Erosion

See also [Terrain Generator](terrain_generator.md).
## For more details, see [Terrain Generator](terrain_generator.md)
## Erosion
Final polish after the rest of the terrain is done. Softens slopes steeper than Talus (thermal).
Optional light flow when Flow Strength > 0 (not a full river sim). Green outline = the Area when
Scope = Area. Never runs from TerrainGenerator Generate — only from Generate on this node.
- What you should see: slightly softer hills / rounded lips — not a new landscape. Toast reports
  time and **max height change**. If that number is near 0, lower Talus or raise Thermal.
- Defaults (CPU-friendly): Iterations 16, Thermal 0.45, Talus 0.4, Flow 0.
- Prefer **Scope = Area** 256–512 per piece (weaker PCs). Avoid All Regions unless you accept a long wait.

## Example: final polish (tested starting points)
Finish noise + shapes first. Disable every other shape. Flow Strength 0. Scope = Area.

| Area        | Edge Falloff | Iterations | Thermal | Talus | Flow | What you get           |
|-------------|--------------|------------|---------|-------|------|------------------------|
| 256 x 256   | 30           | 16         | 0.45    | 0.4   | 0    | Soften (fast / weak PC)|
| 512 x 512   | 70           | 16         | 0.45    | 0.4   | 0    | Soften (recommended)   |
| 512 x 512   | 70           | 12         | 0.40    | 0.4   | 0.15 | Light gullies (slower) |

1. Scope = Area 256 (or 512). Ground already generated. Enable Erosion only.
2. Press Generate on the Erosion node. Check the toast (seconds + max change in meters).
3. Optional gullies: Flow Strength ~0.15, Iterations ~12, Generate again.

- Too little change: Talus 0.3, or raise Thermal / Iterations.
- Too smooth: raise Talus (0.6–0.7) or lower Thermal / Iterations.
- Too slow: smaller Area, Flow 0, fewer Iterations. Ctrl+Z undoes one erosion Generate.