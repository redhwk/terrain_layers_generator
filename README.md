# TerrainLayers and TerrainGenerator for Terrain3D

A companion addon for [Terrain3D](https://github.com/TokisanGames/Terrain3D):

- **TerrainLayerMasks** — place every Terrain3D texture with height / slope / noise / texture masks (not limited to Terrain3D’s two-texture auto shader).
- **TerrainGenerator** — procedural base noise plus shapes (Mountain, Valley, Mesa, Island, Lake, Flatten, Erosion).
- **TerrainFloorGuard** — keeps rigid bodies from falling through Terrain3D regions that have no collider; optional Freeze / Despawn of distant items for large worlds and multiplayer.

## Requirements

- Godot 4.x
- **Terrain3D** 1.1.x (required). Enable Terrain3D before or with this plugin. If Terrain3D is missing, the editor shows a warning when this plugin enables.

## Install

1. Copy the `terrain_layers_generator` folder into your project’s `addons/` directory.
   - The folder name must be exactly `terrain_layers_generator`. GitHub’s automatic Source code ZIP
     often extracts as `terrain_layers_generator-0.1.0` (or similar) — rename it. Prefer a Release
     asset ZIP that already uses the correct folder name when one is attached.
2. Project → Project Settings → Plugins → enable **TerrainLayers and TerrainGenerator for Terrain3D**.
3. Ensure **Terrain3D** is also enabled.

## Quick start

### Layers

1. Add a **TerrainLayerMasks** child under your Terrain3D node.
2. Assign or create a **TerrainLayerStack**.
3. Press **Rebuild Shader** once (writes the layer shader override from Terrain3D’s shader).
4. Use the Inspector **Doc** control (Help icon) for the full guide.

### Generator

1. Add a **TerrainGenerator** child under Terrain3D (Data Directory set on Terrain3D).
2. Set Area / noise, add shape children as needed, press **Generate**.
3. **Listed Regions:** fill via **Add Regions From Area** (frame with Area first) or **Add Selected Node's Region** — entries are region grid cells, not world meters.
4. Use the Inspector **Doc** control for examples.

### Floor guard (dropped items / parked props)

1. Add a **TerrainFloorGuard** node anywhere in the level (scene root is fine).
2. Leave **Body** empty — it covers every `RigidBody3D` and re-scans for newly spawned loot.
3. Optional: set **Park Distance** (e.g. 200) and **Park Mode** = Freeze (keep the node) or Despawn (free it and recreate when a player returns).
4. Use the Inspector **Doc** control for the full guide (also covers [TerrainGround](docs/terrain_ground.md) for direct height lookups).

## Documentation

Markdown guides live in [`docs/`](docs/index.md).

**Godot’s header Doc button:** For GDScript nodes it opens the *engine* base class (e.g. Node), not your `class_name`. Terrain3D’s header Doc works because Terrain3D is a native class. For this addon, select the node and use the **Doc** control at the top of the Inspector — it opens the matching guide. You can also press **F1** and search the class name (e.g. `TerrainLayerMasks`).

## Notes

- This addon does not ship example textures or demo art.
- Erosion is a final polish pass; prefer Scope = Area 256–512 on modest PCs.
- After updating Terrain3D, press **Rebuild Shader** on TerrainLayerMasks.
