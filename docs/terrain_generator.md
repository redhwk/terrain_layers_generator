# Terrain Generator

Procedural heights for [Terrain3D](https://github.com/TokisanGames/Terrain3D). Shape how-tos: [Mountain](mountain.md), [Valley](valley.md), [Mesa](mesa.md), [Island](island.md), [Lake](lake.md), [Flatten](flatten.md), [Erosion](erosion.md). Layers: [Terrain Layers](terrain_layers.md).
## Terrain Generator for Terrain3D 
## Generates Terrain3D heights from noise; your hand sculpting stays on top when you generate again
## Hover over any property in the Inspector for its full description (every export has a tooltip)
## Setup
- Terrain3D (with a Data Directory, so the result can be saved)
	- TerrainGenerator - Add Child Node > TerrainGenerator.
- Select TerrainGenerator: outlines show where it will work (editor only, while it's selected):
  yellow = the Area, pale yellow = where Edge Falloff reaches full strength, orange = the regions
  it touches. Move the node to move the Area.
- Press Generate on the TerrainGenerator to rebuild the Area from base noise + every enabled shape.
  Press Generate on a shape (Mountain, Valley, ...) to apply only that shape onto the terrain you
  already see (it will not rebuild noise or re-apply other shapes). A pop-up says when it starts and
  finishes; pressing again while it works does nothing. Ctrl+Z undoes it. Save the scene (Ctrl+S):
  Terrain3D writes the region files, and terrain_generator.res remembers what was generated.
- Works with Terrain Layers: TerrainLayerMasks textures the new ground automatically.

## Example: build a world piece by piece (tested)
Leave Edge Falloff at 200. Move the node, change the settings, Generate; repeat. Each piece blends
into what's around it. Overlap neighbouring Areas by at least the Edge Falloff: put the new Area's
yellow edge on (or past) the previous Area's pale yellow line. Areas that only touch each fade out
at the shared edge, so you get a valley between them (with Edge Falloff 0: a cliff / crevasse).
1. Rolling Hills, Area 1024 x 1024, Transform (0, 0, 0). Generate.
2. Ridged Mountains, Area 1024 x 1024, Height 250, Transform (-824, 0, 0) so it overlaps the hills
   by 200 m. Generate: the mountains rise out of the hills over the Edge Falloff distance.
   (Transform (-1024, 0, 0) only touches the hills, so you get a valley or cliff between them.)
3. Billowy, Area 512 x 512, Height 40, Combine = Add, Transform (-512, 0, 0) over the seam. Generate:
   bumps on top of both.
4. Optional: Generate step 3 again with Base Height 10. With Combine = Add, that lifts the Billowy
   patch a little and softens how it sits on the seam.
Edge Falloff = 0 gives hard edges (cliffs) on purpose; 100 - 300 m blends.

## Scope (where it generates)
- Area (default): a rectangle of Area Size meters centred on the node. Only ground inside it
  changes; regions it overlaps are added where missing (Terrain3D regions are 256 m by default,
  so a 256 m Area that isn't lined up with the region grid touches up to 4 regions). Use Area when
  you want one clear rectangle — it is the simplest choice for most work.
- All Regions: every region the terrain already has.
- Listed Regions: only the cells in the **Regions** list. Those entries are Terrain3D **region grid
  indices** `(rx, rz)`, not world meters. One step = one region (often 256 m). Orange outline =
  which cells Generate will touch. Prefer the buttons over typing numbers:
  1. **Add Regions From Area** (easiest): place/size the yellow Area over the patch you want, press
     the button — it copies every overlapped cell into Regions and switches Scope to Listed. Trim
     the list if you need a non-rectangular set.
  2. **Add Selected Node's Region**: select a Node3D standing in a region (Marker3D, Player, …),
     select the TerrainGenerator, press the button — appends that one cell and switches to Listed.
  Example (256 m regions): world near X=-512, Z=1024 maps to cell `(-2, 4)`. Missing regions are
  added on Generate. Use Listed when you need a sparse or non-rectangular set of cells, or to lock
  a set after framing it with Area.

## Your sculpting is kept
- The generator remembers what it has made. Everything else (your hand sculpting, and terrain that
  was there before the first Generate) stays on top when you Generate again. So you can sculpt a
  ramp, change the seed, Generate, and the ramp is still there (on the new hills).
- Keep Hand Sculpting off: that "everything else" is replaced too, for fresh generated ground.
- Combine: Replace (default) = the new heights replace what earlier Generates made here (Ridged
  Mountains where the hills were). Add = added on top (Billowy bumps over the mountains).
- Remove Generated Heights: takes everything the generator made back out (all Generates in the
  scope, blended with Edge Falloff), leaving your sculpting and the terrain from before.

## Height settings
- World Seed: changes the whole pattern; the same seed and settings always give the same terrain.
  Randomize Seed picks a new one.
- Base Height: meters added everywhere (e.g. -20 to start below sea level). With Combine = Add it
  lifts the whole Area before the noise is added (e.g. 10 on a Billowy overlay raises that patch).
- Edge Falloff: blends the new terrain into what's around it over this many meters, from the edge
  of the Area inwards: into neighbouring terrain, or down to height 0 (the flat World Background at
  Terrain3D's default Ground Level) where there's none. 0 = a hard edge.

## Base Noise
- Style: Rolling Hills (smooth), Ridged Mountains (sharp crests and ridge lines), Billowy (round
  bumps with creases between).
- Type: the Godot FastNoiseLite pattern; Simplex Smooth (default) and Perlin suit terrain best.
- Height: about how far it is from the lowest valley to the highest top, in meters.
- Size: about how wide one hill is, in meters. Bigger = broader, gentler land.
- Detail: layers of smaller bumps on top of the big shapes (1 = smooth blobs, 5 = natural, 8+ = gritty).
- Roughness: how strong each smaller layer is. 0.3 = soft, 0.5 = natural, 0.7 = rugged.
- Warp: bends the pattern sideways, in meters. 50 - 150 = less regular, more natural shapes; a lot
  more swirls it.
- Offset: slides the pattern (meters) to try a different spot without changing the seed.
- Curve: remaps the noise (left = lowest, right = highest) before Height. Right-click in the curve
  editor > Load Preset: Ease In = wide flat lowlands with steeper hills; Ease Out = wide high plateaus.

## Starting points
- Gentle countryside: Rolling Hills, Height 60, Size 600, Detail 5, Roughness 0.45.
- Mountains: Ridged Mountains, Height 300, Size 1000, Detail 6, Roughness 0.5, Warp 80.
- Dunes / moors: Billowy, Height 40, Size 300, Detail 3, Roughness 0.4.
- Flat building ground with a few hills: Rolling Hills, Height 50, Size 700, Curve Ease In.

## Speed
- About 5 s for a 1 km x 1 km Area (16 regions) on an 8-core CPU, all cores in use; a 256 m Area is
  almost instant. Bigger areas take longer; the Output panel shows progress.

## Shapes (child nodes of TerrainGenerator)
Add Child Node under TerrainGenerator. Move and scale them in the viewport; the outline shows each
shape's footprint when the generator or a shape is selected.

| Shape   | Outline | What it does                                      |
|---------|---------|---------------------------------------------------|
| Mountain| Orange  | Peak / ridge stacked on (or maxed into) the ground|
| Valley  | Cyan    | Carves a canyon / draw                            |
| Mesa    | Gold    | Flat-top plateau (absolute Height)                |
| Island  | Teal    | Landmass with shore forced down to Shore Height   |
| Lake    | Blue    | Carves a round / oval basin                       |
| Flatten | Purple  | Levels a pad toward Height (soft edge)            |
| Erosion | Green   | Final polish: softens slopes; optional light flow |

- Generate on a shape = apply only that shape onto the terrain you already see (uses the
  TerrainGenerator's **Scope**). The shape must sit over the regions in that Scope — otherwise
  nothing changes. **Recommended:** Scope = Area, keep the shape inside the yellow rectangle, then
  Generate on the shape. Listed Regions works too if the shape footprint overlaps those cells.
- Generate on the TerrainGenerator = rebuild base noise + every **Enabled** shape
  (**Erosion is skipped** — run it last on the Erosion node).
- Typical order: noise + shapes (Mountain … Flatten) until the land looks right, then **Erosion**
  once as the final polish (thermal only; Flow optional).
- Workflow: leave shapes you are not working on with **Enabled = false**. Turn **Enabled = true**
  only on the shape you are testing (or on several you want stacked). The TerrainGenerator itself
  has no Enabled switch — use each shape's Enabled. (Noise Enabled on the generator only turns the
  base noise on/off.)
- With Scope = Area, the yellow Area must cover the shape (warning if it sits outside). With Listed,
  place the shape over the listed cells (or switch back to Area to place it).
- **Falloff Curve** (on a shape) is optional and usually left empty. It is not the same as
  **Edge Falloff** (on the TerrainGenerator), which blends the whole Area into neighbouring ground.
- Transform Scale X/Z stretches the footprint; Scale Y multiplies Height / Depth.
- Blend Mode: Mountain can Add / Max / Min / Subtract. Valley and Lake always carve (hidden). Mesa
  always Max (hidden). Island always sets absolute heights (hidden). Flatten always lerps toward
  Height with a soft edge (hidden). Erosion has no Blend Mode (post-pass over existing heights).

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

## See also
- Shape examples: [Mountain](mountain.md), [Valley](valley.md), [Mesa](mesa.md), [Island](island.md), [Lake](lake.md), [Flatten](flatten.md), [Erosion](erosion.md)
- [Terrain Layers](terrain_layers.md) · [Docs index](index.md)
