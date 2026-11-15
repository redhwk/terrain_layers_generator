# Terrain Layer Baking Tests

Measured live vs baked cost. Setup: [Terrain Layers](terrain_layers.md).
## Terrain Layers: live vs baked vs Terrain3D's own shader (measured)
## What each way of running the layers costs, so you can pick one for your game
## Setup and baking steps: [Terrain Layers](terrain_layers.md)
## The short version
- Live layers (the layer shader works out every pixel's textures each frame): easiest while you
  build. Costs the most.
- Baked, layer shader still on: 15 - 23% less GPU time per frame than live in this test, same look.
  Ground outside your regions (World Background) stays live, and you can return to live any time.
- Baked, Terrain3D's own shader, no TerrainLayerMasks: another 5 - 29% less than baked (26 - 39% less
  than live). The baked ground looks the same, but the World Background goes back to Terrain3D's
  2-texture auto look, and the layers no longer texture new sculpting until you add them back.
- Return Baked To Auto gives exactly the live result back (same look, same cost).

## Test setup
- Terrain: 4 Terrain3D regions (256 m each, 512 x 512 m), beach to a ~375 m peak, ocean mesh on.
  World Background Flat (the default), so the ground outside the regions is drawn too.
- Layers: the 5-texture Example in [Terrain Layers](terrain_layers.md) (Cliff base, Grass, Sand, Scree,
  Peak; 5 layers, 9 masks including one Noise mask and one Height curve).
- Godot 4.7.2, Forward+, Vulkan, Terrain3D 1.1.0. NVIDIA GeForce RTX 4060 Ti, AMD Ryzen 7 9800X3D.
- Window 1179 x 648, vsync off, no FPS cap. Simple sun + flat sky (no clouds, fog or post effects),
  so the numbers are mostly terrain.
- Each test was measured from 3 camera views, 150 frames each after a 1 s settle:
  Overhead  - 520 m up looking straight down: the regions plus a lot of World Background around them.
  Slope     - standing on a hillside looking across grass, sand, scree and rock.
  Low       - low over one corner looking across the whole terrain towards the horizon.
- GPU ms = GPU time to render one frame (RenderingServer measured render time). Frame ms = time
  between frames. FPS = 1000 / frame ms. Lower ms is better.
- The bake ran in the running game, not saved, so every test started from the same terrain.

## The tests
1. Baseline: everything live, as set up (TerrainLayerMasks on, layer shader on, nothing baked).
2. Bake: TerrainLayerBaker, Scope All Regions, Bake. Layer shader still on.
3. Return to auto: Return Baked To Auto after test 2 (back to live layers).
4. Terrain3D's own shader: Bake again, turn off the material's Shader Override Enabled and remove the
   TerrainLayerMasks node (what the "final build" steps in the instructions do).

## Results: GPU ms per frame (lower is better)
| Test                                   | Overhead | Slope | Low  |
|----------------------------------------|----------|-------|------|
| 1. Live layers (baseline)              | 6.13     | 3.14  | 2.52 |
| 2. Baked, layer shader on              | 5.21     | 2.42  | 2.13 |
| 3. Returned to auto                    | 6.15     | 3.14  | 2.52 |
| 4. Baked, Terrain3D shader, no layers  | 3.72     | 2.31  | 1.85 |

## Results: FPS (higher is better)
| Test                                   | Overhead | Slope | Low  |
|----------------------------------------|----------|-------|------|
| 1. Live layers (baseline)              | 154      | 285   | 351  |
| 2. Baked, layer shader on              | 180      | 364   | 405  |
| 3. Returned to auto                    | 154      | 284   | 351  |
| 4. Baked, Terrain3D shader, no layers  | 247      | 379   | 457  |

## Change in GPU time compared with the baseline
| Test                                   | Overhead | Slope | Low  |
|----------------------------------------|----------|-------|------|
| 2. Baked, layer shader on              | -15%     | -23%  | -15% |
| 3. Returned to auto                    | 0%       | 0%    | 0%   |
| 4. Baked, Terrain3D shader, no layers  | -39%     | -26%  | -26% |

- Bake time: 1.0 s for 262,144 vertices (4 regions), using all CPU cores.
- Return Baked To Auto: instant.

## What the screenshots showed
- Baked vs live: the same picture. The pixel difference (1 - 2.4%) is the same size as between
  test 1 and test 3, which are identical terrain: it's the animated ocean, not the terrain.
- Test 4 vs live: the baked regions look the same. The visible change is the World Background
  around them: with the layers it's textured by the layers (sand at sea level, so the ocean floor
  looks grey); with Terrain3D's shader it gets Terrain3D's auto textures (darker under the water).
  With World Background None there is no ground outside the regions, so test 4 would look the same.

## Why the numbers look like this
- Live layers: every terrain pixel runs every layer's masks (height, slope, noise lookups, curves)
  to choose its two textures.
- Baked: the textures come from the control map, like hand painting. The layer shader skips the
  layer maths wherever a spot is baked or painted, so only the World Background still pays for it.
  That's why the Overhead view (mostly World Background) saves the least in test 2 and the most in
  test 4.
- Terrain3D's own shader: no layer code at all, also not for the World Background, and a slightly
  smaller shader everywhere. Inside the regions this adds only a little over test 2 (Slope view
  2.42 -> 2.31 ms).

## Choosing
| You want                                         | Use                                       |
|--------------------------------------------------|-------------------------------------------|
| To keep sculpting and tuning layers              | Live layers                               |
| Finished areas cheaper, still able to tweak      | Bake, keep the layer shader               |
| Layers on the endless ground outside regions     | Live or baked with the layer shader       |
| The fastest final build                          | Bake + Terrain3D's own shader             |
| Hand painting on top of the layer result         | Bake (either shader)                      |
| Footsteps / foliage that read Terrain3D textures | Bake (only baked or painted ground counts)|

## Reading these numbers for your own game
- This is a small, simple test scene; the times are fractions of a millisecond to a few ms on a
  fast GPU. The percentages are the useful part: on a slower GPU (laptops, Steam Deck) or at higher
  resolutions the same percentages are more milliseconds.
- More layers and masks (especially Noise and Texture masks) make live layers cost more, so baking
  saves more. Baked cost doesn't grow with the number of layers.
- The more of the screen is terrain, the bigger the difference. Close-ups of other objects hide it.

## Measuring your own terrain
1. Project Settings > Display > Window > V-Sync Mode = Disabled (just for the test), run the scene.
2. Debugger > Visual Profiler > Start: GPU time per frame. Or Debugger > Monitors > Time > FPS.
3. Stand still at the same spot for each test (a Camera3D or the Player at a fixed position), note
   the GPU time live, after Bake, and with the material's Shader Override Enabled off.
4. Turn V-Sync back on afterwards.
