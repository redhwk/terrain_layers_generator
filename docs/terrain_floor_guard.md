# TerrainFloorGuard

Keeps physics bodies from falling through Terrain3D where it has no collider, and optionally parks distant objects so large item counts stay affordable.

Terrain3D only builds collision around its collision target (usually the camera). Walk far enough from a dropped item and the ground under it stops existing — gravity takes it. This node reads the height map instead (via [TerrainGround](terrain_ground.md)) and puts the body back on the surface. It never changes Terrain3D settings.

## Setup

No configuration needed for basic use.

### Whole level (recommended)

1. Add a **TerrainFloorGuard** node anywhere in the level (scene root is fine).
2. Leave **Body** empty.
3. It looks after every `RigidBody3D` in the scene and re-scans every **Rescan Interval** seconds, so loot spawned or dropped while playing is covered automatically.

### One body

1. Add **TerrainFloorGuard** as a child of a `RigidBody3D` (e.g. inside a pickup scene).
2. Leave **Body** empty — it uses its parent.
3. A level-wide guard skips bodies that already have their own, so the two never fight.

### Guard Group

Optional. When set, only bodies in that group are covered. Leave empty unless you have hundreds of bodies and need to limit the scan. Group membership must live on the packed scene (not a level instance) if you also drop those items from inventory.

## Park when far away

Beyond **Park Distance** from the nearest player, a resting body is parked so it costs almost nothing until someone comes back. `0` = never park.

| Park Mode | What happens | Best for |
|-----------|--------------|----------|
| **Freeze** | Keeps the node, freezes simulation. Visible / collidable if you walk up to it. | Hundreds of items, single player, simple multiplayer |
| **Despawn** | Frees the node and stores `scene_path` + transform (+ optional custom state). Recreates it when a player returns. | Thousands of items, dedicated servers, persistent worlds |

**Wake Margin** is the hysteresis inside Park Distance so a player on the boundary doesn't flip the body every frame.

**Player Group** defaults to `player`. With no members, the active camera is used (works for single player with zero setup). In multiplayer, put every player avatar in this group.

### Despawn requirements

- The body must be an instance of a packed scene (`scene_file_path` set). Editor-unique nodes without a scene path fall back to Freeze with a one-time warning.
- Optional hooks on the body for game-specific state (inventory contents, durability, etc.):

```gdscript
func get_terrain_guard_state() -> Dictionary:
    return { "charges": charges }

func apply_terrain_guard_state(state: Dictionary) -> void:
    charges = state.get("charges", charges)
```

### Saving despawned loot (dedicated server)

```gdscript
# Persist
var records := $TerrainFloorGuard.get_despawned_records()

# Restore after load (they respawn when a player comes near)
$TerrainFloorGuard.restore_despawned_records(records)
```

Signals for netcode hooks: `body_parked`, `body_woken`, `body_despawned`, `body_respawned`.

## What is skipped

- Bodies exposing a `terrain_floor_clamp` property (e.g. hover vehicles that already snap to the height map).
- Bodies that already have their own TerrainFloorGuard child.
- Terrain3D holes and regionless areas (read as "no ground").

## Related

- [TerrainGround](terrain_ground.md) — the height / normal helper this node uses; call it directly from your own scripts if you need a one-off snap.
