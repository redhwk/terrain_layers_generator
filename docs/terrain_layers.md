# Terrain Layers

Multi-texture layers for Terrain3D. Baking benchmarks: [Baking tests](terrain_layer_baking_tests.md). Generator: [Terrain Generator](terrain_generator.md).
## Terrain Layers for Terrain3D 
## Layer system: auto-place every Terrain3D texture with masks, not limited to Terrain3D's 2-texture auto shader
## Hover over any property in the Inspector for its full description (every export has a tooltip)
## Setup
- Terrain3D Material: Auto Shader on.
- Terrain3D
	- TerrainLayerMasks - Node, attach terrain_layer_masks.gd (or Add Child Node > TerrainLayerMasks).
	  Assign a Stack (a saved preset .tres), or create a New TerrainLayerStack: it fills with one
	  layer per Terrain3D texture.
	  Press Rebuild Shader once: it writes addons/terrain_layers_generator/shaders/terrain_layer_shader.gdshader from Terrain3D's
	  own shader and sets it as the material's Shader Override.
		- TerrainLayerBaker - Node (optional), see Baking below.
- Changes show live in the editor and in game. Enabled off = Terrain3D's own 2-texture auto shader.
- Layers apply where Terrain3D's auto shader applies: outside regions and anywhere painted with the
  Autoshader brush. Hand-painted (and baked) areas keep their painting.

## The layer shader (terrain_layer_shader.gdshader)
- Built by Rebuild Shader; rebuilt automatically in the editor (Auto Rebuild Shader) whenever a Terrain3D
  material option that changes shader code changes: Texture Filtering, Auto Shader, Dual Scaling,
  Macro Variation, Projection, Max Regions, PBR Output. Don't edit it by hand (rebuilds overwrite it).
- World Background None, Flat and Noise all work (Terrain3D normally writes only the selected one).
- After updating Terrain3D: press Rebuild Shader. If Terrain3D's shader changed too much, the Output
  panel says which spot couldn't be found; the three additions are marked TERRAIN LAYERS HOOK.

## Sea level
- "Relative To Sea Level" height masks measure from Sea Level Source: Manual = the Sea Level number.
  Terrain3D Ocean = Sea Level inside Terrain3D > Ocean Material (works with the ocean mesh off).
  Node = the height of any Node3D you pick (water plane, Marker3D at the waterline).
- World Background Noise: Terrain3D's noise is always positive, so its ground sits well above 0
  (about World Noise Height x 3.6 m; ~115 m at the default 32). World Noise Offset Y (x 100 m) moves it down.

## Layers (Stack > Layers)
- Layer N = Terrain3D texture N (kept in sync automatically; Sync Textures forces it).
- Paint Order: higher numbers paint over lower ones wherever their masks are strong
  (equal numbers: higher texture number on top).
- No masks = covers everything below it. Opacity caps the layer's strength.
- The lowest Paint Order layer is the base: it fills whatever the other layers leave, so its masks
  and Opacity have no effect.
- Blend Sharpness (per layer): how crisp this texture's edges are where it meets another
  (-1 = the material's Blend Sharpness). The softer of the two textures that meet wins, so soften
  "soft ground" textures (sand, scree, dirt: 0.15 - 0.25) and leave grass and rock at -1: grass-to-sand
  becomes soft, grass-to-rock keeps the crisp crevice look. Works on painted and baked areas too.
- Terrain3D draws two textures per spot: where 3+ layers overlap the two strongest show, so keep
  overlaps to two (e.g. one cliff texture, not five; one grass at a time over the rock).

## Masks (how the numbers work)
- Height and Slope masks are RAMPS (Outside Range = Extend Edges, the default):
  0 below Min, rising to 1 at Max, 1 above Max. Invert turns that around: 1 below Min, 0 above Max.
  So "Min 150, Max 250, Invert" = full strength below 150 m, fading out by 250 m.
  Outside Range = Zero instead makes a band: only between Min and Max.
- A layer's masks run top to bottom. The first one sets the value (it has no Blend Mode); each next
  one combines with Blend Mode: Multiply = both must be true; Smaller Than = like Multiply but softer;
  Greater Than = either one; Add = stacks up; Subtract = cuts out.
- Height - Meters (default); Relative To Sea Level or World Space.
- Slope - degrees (0 flat, 90 vertical).
- Noise - patches (Godot FastNoiseLite: Perlin / Cellular / Simplex / Value, octaves, warp ...);
  Tile Size = how big the pattern is. With Multiply it breaks a layer into patches.
- Texture - follows how visible another texture is from lower Paint Orders (e.g. scree only on rock).
- Terrain3D Auto Slope - Terrain3D's own auto shader look: strong on flat ground, fading on slopes
  (follows the material's Auto Slope / Height Reduction). Use it for grass.
- Curves are optional fine-tuning; leave them empty to start (empty = a straight ramp). A Height or
  Slope curve reshapes the fade between Min (left of the curve) and Max (right): Ease Out = rises early,
  Ease In = rises late, Smoothstep = gentle at both ends. Strength Transform does the same to the
  mask's final value.
- Soft blends come from wide ranges: a fade is only as wide as the ground between Min and Max.
- A harsh line between two textures: Terrain3D's height blending looks best between a texture and
  rock, and can look hard between two "soft" ground textures (grass / scree / sand). First lower the
  soft texture's layer Blend Sharpness (0.15 - 0.25). Also: keep rock between them (Texture mask
  Start At, e.g. 0.6), widen the Min..Max fade, or add a Noise mask (Multiply) so the edge breaks up.
- A hard line where BOTH drawn textures change at once (e.g. rock + scree right next to grass + sand):
  make sure one texture carries across the edge. Here rock should: Scree Start At 0.6 and Sand on a
  Slope mask give rock + scree -> rock + grass -> grass + sand.
- Lines that jump around: more than two textures overlap there at similar strength, so the two that
  get drawn keep changing. Give each texture its own job (sand: flat + low; grass: Auto Slope;
  scree: on rock only) so mostly two meet at any spot.
- Grass to rock on a sharp ledge looks crisp even with Terrain3D's own auto shader: the slope changes
  within about a meter there. Lower Auto Slope in the Terrain3D material for a wider fade, or lower
  Blend Sharpness for softer blends everywhere.
- Curves are resources: a curve copied between masks is SHARED. Right-click > Make Unique first.

## Example: 5 textures from the beach to the peaks (tested on a terrain with ~350 m peaks)
Start from a New TerrainLayerStack (all layers off). Only change what's listed; leave everything else
at its default. Heights are meters above your sea level. Replace the texture numbers with yours.
1. Cliff  (layer 7)  - Enabled, Paint Order 0. No masks.
					   = the base: rock wherever nothing else covers it. The lowest Paint Order layer
					   always fills what the others leave, so masks on it have no effect (the node warns).
					   Soft grass-to-rock edges come from the Auto Slope mask on the Grass layer.
2. Grass  (layer 12) - Enabled, Paint Order 10. Masks:
					   a. New TerrainAutoSlopeMask.
					   b. New TerrainHeightMask: Min 150, Max 250, Invert, Blend Mode Smaller Than.
					   = grass on flatter ground (rock shows on slopes), thinning out from 150 to 250 m.
3. Sand   (layer 1)  - Enabled, Paint Order 20. Masks:
					   a. New TerrainHeightMask: Min 2, Max 12, Invert.
					   b. New TerrainSlopeMask: Min 10, Max 20, Invert (Multiply).
					   = sand on flat ground at the water line, gone by 12 m above sea level.
					   The Slope mask keeps sand off the slopes the grass uses (an Auto Slope mask here
					   would put sand everywhere grass is, so 3-4 textures overlap and fight).
4. Scree  (layer 11) - Enabled, Paint Order 30. Masks:
					   a. New TerrainTextureMask: Texture = your cliff (7), Start At 0.6.
					   b. New TerrainHeightMask: Min 20, Max 60, Invert (Multiply).
					   c. New TerrainNoiseMask (Multiply, defaults).
					   = rubble patches on the lower rock, fading out by 60 m. Start At 0.6 keeps the
					   scree where the rock is mostly visible, so a little rock always sits between
					   grass and scree (grass right against scree makes a harsh line).
5. Peak   (layer 10) - Enabled, Paint Order 40. Masks:
					   a. New TerrainTextureMask: Texture = your cliff (7).
					   b. New TerrainHeightMask: Min 300, Max 340 (Multiply).
						  Height Curve: click it > New Curve, then in the curve editor right-click >
						  Load Preset > Ease Out.
					   = the rock turns into peak rock from 300 to 340 m. The curve shapes the fade:
					   without it the fade is a straight ramp; Ease Out makes the peak rock take over
					   sooner and fade in gently (a bigger cap); Ease In holds off, then switches late
					   and sharply. Try both to see the difference.
Tuning: move Min / Max to slide a fade up or down; a wider Min..Max = a softer fade.
More grasses: copy step 2 for the next grass with its own Height band starting where the previous
grass ends (Outside Range Zero + a curve that rises and falls), so only one grass meets the rock at a time.

## Baking (TerrainLayerBaker)
- Writes the layer result into Terrain3D's control map, the same data the paint brush writes:
  baked areas cost nothing extra per pixel, Terrain3D's own texture lookups (footsteps, foliage)
  see the textures, and you can hand-paint on top with Terrain3D's brushes.
- Add as a child of TerrainLayerMasks. Scope: All Regions, or Listed Regions (select any node in the
  scene, e.g. a Marker3D, and press Add Selected Node's Region). Bake. Ctrl+Z undoes it.
- Keep Hand Painting (on): only vertices that are still auto, or still exactly what the last bake
  wrote, are rewritten; anything you painted since stays. Re-bake after sculpting or changing layers.
- Return Baked To Auto: baked vertices go back to the live layers. Or paint them with Terrain3D's
  Autoshader brush (that's the "back to auto" brush; the eraser isn't).
- Baking is per vertex (every 1 m), like brush painting; the live layers are per pixel.
- World Background (outside regions) can't be baked; it stays live.
- terrain_layer_bake.res (next to the Terrain3D data) remembers what was baked.
- Measured results (live vs baked vs Terrain3D's own shader): Terrain Layer Baking Tests.md.

## Example: bake a finished terrain
1. Get the live layers looking right first (Example above). Baking copies what you see.
2. Select TerrainLayerMasks > Add Child Node > TerrainLayerBaker.
3. In the TerrainLayerBaker Inspector: leave Layer Masks empty (it finds its parent), Scope = All
   Regions, Keep Hand Painting on, Bake Data empty (created on the first bake).
   Only part of the world? Select a node standing in that region (a Marker3D, the Player ...), then
   select TerrainLayerBaker and press Add Selected Node's Region (Scope switches to Listed Regions).
   Repeat for more regions.
4. Press Bake. The Output panel says how many vertices / regions were baked and how long it took
   (about a second for four 256 m regions). The terrain should look the same as before: it now
   comes from the control map instead of the live layers.
5. Check it worked: select Terrain3D > Debug Views > turn on Show Autoshader. Auto ground is
   highlighted; baked ground isn't anymore (turn it off again afterwards). Ctrl+Z undoes the bake.
6. Save the scene (Ctrl+S). Terrain3D writes the baked control map into its region files; the
   first bake also created terrain_layer_bake.res in the Terrain3D data directory. Keep both.
7. Changed something later (sculpted, moved a Min / Max, added a layer)? Press Bake again and save.
   Your hand-painted strokes since the last bake are kept (Keep Hand Painting).
Back to live layers: press Return Baked To Auto, then save. Hand-painted strokes stay painted.

## Optional: final build with Terrain3D's own shader (fastest)
Baked areas no longer need the layer shader, so a finished game can drop it. Trade-off: the ground
outside your regions (World Background) gets Terrain3D's 2-texture auto look again, and newly
sculpted ground isn't textured by the layers until you put them back.
1. Bake (above) and save.
2. Terrain3D > Material: turn off Shader Override Enabled.
3. Delete the TerrainLayerMasks node (its TerrainLayerBaker child goes with it). Your Stack preset
   (.tres), the baked region files and terrain_layer_bake.res all stay on disk.
   Don't just leave TerrainLayerMasks in the scene: its Auto Rebuild Shader turns Shader Override
   back on the next time a Terrain3D material option changes.
4. Save the scene.
To go back: add TerrainLayerMasks again, assign the same Stack, press Rebuild Shader (turns Shader
Override back on), add a TerrainLayerBaker and assign terrain_layer_bake.res to its Bake Data.

## Presets
- The Stack is a resource: Inspector > Save As (.tres) to reuse on other terrains or games.
  Its Description field is a good place to note what each layer does.
- A preset that is exactly Terrain3D's auto look is a good start: texture 7 (rock) base with no masks,
  texture 12 (grass) above it with one Terrain3D Auto Slope mask. Then turn on more layers above it.
- A shared preset changes everywhere it's used; right-click > Make Unique to change one copy.

## Limits
- Max 32 layers and 64 masks in total. Every mask costs a little GPU time per pixel where it's live;
  Noise masks are baked to a tile (a few hundred ms when a noise setting changes).

## Files (addons/terrain_layers_generator/scripts)
terrain_layer_masks.gd          - node: sends the stack to the shader, Rebuild Shader
terrain_layer_baker.gd          - node: Bake / Return Baked To Auto
terrain_layer_bake_data.gd      - what the last bake wrote (keeps hand painting safe)
terrain_layer_evaluator.gd      - the layer math on the CPU (same result as the shader)
terrain_layer_shader_builder.gd - builds terrain_layer_shader.gdshader from Terrain3D's shader
terrain3d_bridge.gd             - every direct use of Terrain3D's data API (fix here after a Terrain3D change)
terrain_layer_stack.gd / terrain_mask_layer.gd - the preset and its layers
terrain_mask.gd + terrain_height / slope / noise / texture / auto_slope _mask.gd - the masks
addons/terrain_layers_generator/shaders/terrain_layer_masks.gdshaderinc - the layer code in the shader
addons/terrain_layers_generator/shaders/terrain_layer_shader.gdshader   - generated Terrain3D shader with the three hooks
[terrain_layer_baking_tests.md](terrain_layer_baking_tests.md) - measured cost of live layers vs baked vs Terrain3D's shader
