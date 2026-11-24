# TerrainGround

Static helper that reads Terrain3D's height map without needing a physics collider.

Terrain3D only builds collision around its collision target. The height map, though, stays loaded for every region — so anything that needs a floor out there (enemies, vehicles, dropped items) can ask the height map instead of raycasting into empty space.

Used by [TerrainFloorGuard](terrain_floor_guard.md). Safe to call from your own scripts; nothing here writes to Terrain3D.

## API

```gdscript
# Surface height under a world position, or NAN where there is no region / a hole.
var h := TerrainGround.height_at(self, global_position)
if not is_nan(h):
    global_position.y = maxf(global_position.y, h)

# Surface normal (falls back to Vector3.UP when unavailable).
var n := TerrainGround.normal_at(self, global_position)

# The scene's Terrain3D, or null.
var terrain := TerrainGround.get_terrain(self)
```

Treat `NAN` as "no ground here" so caves and hangars carved with Terrain3D holes stay passable.
