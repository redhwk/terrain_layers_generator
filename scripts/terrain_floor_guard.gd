class_name TerrainFloorGuard
extends Node

## Keeps physics bodies from falling through Terrain3D in regions that have no collider.
##
## Terrain3D builds collision only around its collision target (usually the camera), so an object
## left behind — a dropped item, a crate, a wreck, a parked vehicle — loses the ground under it as
## soon as the player walks away, and gravity takes it. Small or fast objects can also shoot
## straight through the height map collider. This node reads the height map instead (see
## [TerrainGround]) and puts the body back on the surface, so it stays where you left it. Anything
## that already fell below the terrain is lifted back on top.
##
## Two ways to use it, no configuration needed either way:
## [br]- [b]One body:[/b] add it as a child of the RigidBody3D (e.g. inside a pickup scene).
## [br]- [b]Whole level:[/b] add it anywhere else and it looks after every RigidBody3D in the
## scene, including objects spawned while playing. Set [member guard_group] to narrow that down.
##
## Distant objects can also be parked so large item counts stay affordable. See
## [member park_distance] and [member park_mode]:
## [br]- [b]Freeze[/b] keeps the node, turns off simulation, and wakes it when a player returns.
## [br]- [b]Despawn[/b] frees the node and stores enough data to recreate it when a player returns —
## the pattern used by persistent multiplayer worlds with thousands of loose items.
##
## Holes and regionless areas read as "no ground", so bodies inside a cave or hangar carved with
## Terrain3D holes are left alone. Bodies that clamp themselves to the terrain (anything exposing a
## [code]terrain_floor_clamp[/code] property, e.g. a hover vehicle) are skipped.

## How a distant resting body is parked.
enum ParkMode {
	## Keep the node, freeze simulation. Cheap, and the object stays visible / pickable if you walk
	## up to its frozen collider. Best for hundreds of items.
	FREEZE,
	## Free the node and store transform + scene path so it can be recreated later. Cheapest at
	## thousands of items and the right fit for a dedicated server; the object is gone until a
	## player comes near. Bodies without a [member Node.scene_file_path] fall back to freeze.
	DESPAWN,
}

signal body_parked(body: RigidBody3D)
signal body_woken(body: RigidBody3D)
signal body_despawned(scene_path: String, transform: Transform3D)
signal body_respawned(body: RigidBody3D)

# --- Exports ---

## Single body to look after. Empty = the parent node if it is a physics body, otherwise every
## RigidBody3D in the scene.
@export var body: PhysicsBody3D
## Clearance kept between a body's lowest collision point and the terrain surface (meters).
@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:m") var floor_margin: float = 0.02
## How often terrain height is sampled (seconds). 0 = every physics frame, which is what keeps a
## resting body perfectly still. Raising it saves a little CPU in scenes with hundreds of loose
## objects, at the cost of them bobbing by the distance gravity pulls them between checks.
@export_range(0.0, 1.0, 0.01, "suffix:s") var check_interval: float = 0.0
## How far a body must move sideways before its terrain height is read again (meters). Bodies that
## are just sitting there reuse the cached height, which is what makes large counts cheap.
@export_range(0.01, 5.0, 0.01, "suffix:m") var resample_distance: float = 0.1

@export_group("Whole level")
## Only look after bodies in this group. Empty = every RigidBody3D in the scene.
@export var guard_group: StringName = &""
## How often the scene is re-scanned for new bodies, e.g. loot just spawned (seconds).
@export_range(0.1, 10.0, 0.1, "suffix:s") var rescan_interval: float = 2.0

@export_group("Park when far away")
## Beyond this distance from the nearest player, a resting body is parked (see [member park_mode]).
## 0 = never park (every guarded body stays live).
@export_range(0.0, 2000.0, 1.0, "or_greater", "suffix:m") var park_distance: float = 0.0
## Freeze keeps the node; Despawn frees it and recreates it when someone returns.
@export var park_mode: ParkMode = ParkMode.FREEZE
## Extra distance inside [member park_distance] at which a parked body wakes / respawns, so a
## player standing on the boundary doesn't flip it every pass (meters).
@export_range(0.0, 200.0, 1.0, "or_greater", "suffix:m") var wake_margin: float = 10.0
## Group of nodes that count as "someone is here". With no members, the active camera is used, so
## this works in single player without any setup. In multiplayer, put every player avatar in this
## group (or set it to whatever group your netcode already uses).
@export var player_group: StringName = &"player"
## How often distances to the players are checked (seconds).
@export_range(0.1, 5.0, 0.1, "suffix:s") var park_interval: float = 0.5
## Parent for respawned bodies in Despawn mode. Empty = this node's parent (usually the level root).
@export var despawn_parent: NodePath = NodePath()

# --- Private variables ---

## Live bodies, checked every [member check_interval]. One entry in single-body mode.
var _bodies: Array[PhysicsBody3D] = []
## Instance id -> lowest point of that body's collision shapes, in body space.
var _bottoms: Dictionary = {}
## Instance id -> Vector3(x, terrain height, z) where that body last sampled the height map.
var _floors: Dictionary = {}
## Bodies this node froze (instance id -> RigidBody3D). Iterated separately from [_bodies] so a
## rescan can't make them un-wakeable.
var _frozen: Dictionary = {}
## Despawned objects waiting to come back. Each entry is a Dictionary with scene_path, transform,
## groups, custom_state.
var _despawned: Array[Dictionary] = []
## Instance ids warned once for missing scene_file_path when Despawn was requested.
var _despawn_warned: Dictionary = {}
var _level_mode: bool = false
var _time: float = 0.0
var _rescan_time: float = INF
var _park_time: float = 0.0


# --- Virtual methods (Godot callbacks) ---

func _ready() -> void:
	var single: PhysicsBody3D = body if body else get_parent() as PhysicsBody3D
	if single:
		_bodies = [single]
		return
	_level_mode = true


func _physics_process(delta: float) -> void:
	if _level_mode:
		_rescan_time += delta
		if _rescan_time >= rescan_interval:
			_rescan_time = 0.0
			_collect_bodies()
	if park_distance > 0.0:
		_park_time += delta
		if _park_time >= park_interval:
			_park_time = 0.0
			_update_parking()
	_time += delta
	if _time < check_interval:
		return
	_time = 0.0
	for guarded in _bodies:
		if is_instance_valid(guarded):
			_guard(guarded)


# --- Public methods ---

## Addon guide opened by the Inspector Doc control.
func documentation_file() -> String:
	return "terrain_floor_guard.md"


## How many bodies are currently frozen by this guard.
func get_frozen_count() -> int:
	return _frozen.size()


## How many objects are currently stored as despawn data (not in the tree).
func get_despawned_count() -> int:
	return _despawned.size()


## Snapshot of every despawned record (scene_path, transform, groups, custom_state). Useful for a
## dedicated server that wants to persist world loot without keeping the nodes alive.
func get_despawned_records() -> Array[Dictionary]:
	return _despawned.duplicate(true)


## Restore despawned records previously saved with [method get_despawned_records]. Does not
## instantiate them — they respawn naturally when a player comes within [member park_distance].
func restore_despawned_records(records: Array) -> void:
	for record in records:
		if record is Dictionary and record.has("scene_path") and record.has("transform"):
			_despawned.append((record as Dictionary).duplicate(true))


# --- Private methods ---

func _collect_bodies() -> void:
	var found: Array[Node] = []
	if guard_group != &"":
		found = get_tree().get_nodes_in_group(guard_group)
	else:
		var scene: Node = get_tree().current_scene
		if scene == null:
			return
		found = scene.find_children("", "RigidBody3D", true, false)
	_bodies.clear()
	for node in found:
		var rigid := node as RigidBody3D
		if rigid == null:
			continue
		var id := rigid.get_instance_id()
		# Already parked by us, or clamps itself, or already has its own guard child.
		if _frozen.has(id) or rigid.get(&"terrain_floor_clamp") != null or _has_own_guard(rigid):
			continue
		_bodies.append(rigid)
	_prune_caches()


func _prune_caches() -> void:
	var bottoms := {}
	var floors := {}
	for guarded in _bodies:
		var id := guarded.get_instance_id()
		if _bottoms.has(id):
			bottoms[id] = _bottoms[id]
		if _floors.has(id):
			floors[id] = _floors[id]
	_bottoms = bottoms
	_floors = floors
	# Drop frozen entries whose nodes were freed elsewhere (picked up, destroyed).
	var kept_frozen := {}
	for id in _frozen:
		var rigid: RigidBody3D = _frozen[id]
		if is_instance_valid(rigid):
			kept_frozen[id] = rigid
	_frozen = kept_frozen


func _has_own_guard(target: Node) -> bool:
	for child in target.get_children():
		if child != self and child is TerrainFloorGuard:
			return true
	return false


func _guard(guarded: PhysicsBody3D) -> void:
	var rigid := guarded as RigidBody3D
	if rigid and rigid.freeze:
		return
	var height := _floor_under(guarded)
	if is_nan(height):
		return
	var bottom: float = (guarded.global_transform * _bottom_of(guarded)).y
	var floor_y := height + floor_margin
	if bottom >= floor_y - 0.01:
		return

	guarded.global_position.y += floor_y - bottom
	# Jolt wakes a body that nothing is holding it up, so there is no "settle and sleep" here: the
	# body is simply put back every frame and its fall speed cleared, which reads as resting.
	if rigid and rigid.linear_velocity.y < 0.0:
		rigid.linear_velocity.y = 0.0


## Park resting bodies nobody is near, and wake / respawn the ones a player has come back to.
func _update_parking() -> void:
	var targets := _player_positions()
	if targets.is_empty():
		return
	var wake_at := maxf(park_distance - wake_margin, 0.0)

	# Wake frozen bodies (tracked separately so a rescan can't lose them).
	var to_wake: Array[int] = []
	for id in _frozen:
		var rigid: RigidBody3D = _frozen[id]
		if not is_instance_valid(rigid):
			to_wake.append(id)
			continue
		if _nearest_distance(rigid.global_position, targets) <= wake_at:
			rigid.freeze = false
			to_wake.append(id)
			# Back into the floor-clamp loop immediately — don't wait for the next rescan.
			if not _bodies.has(rigid):
				_bodies.append(rigid)
			body_woken.emit(rigid)
	for id in to_wake:
		_frozen.erase(id)

	# Respawn despawned records that a player is near.
	var still_despawned: Array[Dictionary] = []
	for record in _despawned:
		var xf: Transform3D = record["transform"]
		if _nearest_distance(xf.origin, targets) <= wake_at:
			var spawned := _respawn(record)
			if spawned:
				if not _bodies.has(spawned):
					_bodies.append(spawned)
				body_respawned.emit(spawned)
			else:
				still_despawned.append(record)
		else:
			still_despawned.append(record)
	_despawned = still_despawned

	# Park newly distant resting bodies.
	var to_remove: Array[PhysicsBody3D] = []
	for guarded in _bodies:
		if not is_instance_valid(guarded):
			continue
		var rigid := guarded as RigidBody3D
		if rigid == null or rigid.freeze or not _is_resting(rigid):
			continue
		if _nearest_distance(rigid.global_position, targets) <= park_distance:
			continue
		match park_mode:
			ParkMode.FREEZE:
				_freeze(rigid)
				to_remove.append(rigid)
			ParkMode.DESPAWN:
				if _try_despawn(rigid):
					to_remove.append(rigid)
				else:
					_freeze(rigid)
					to_remove.append(rigid)
	for rigid in to_remove:
		_bodies.erase(rigid)
		_bottoms.erase(rigid.get_instance_id())
		_floors.erase(rigid.get_instance_id())


func _freeze(rigid: RigidBody3D) -> void:
	rigid.freeze = true
	_frozen[rigid.get_instance_id()] = rigid
	body_parked.emit(rigid)


func _try_despawn(rigid: RigidBody3D) -> bool:
	var path := rigid.scene_file_path
	if path.is_empty():
		var id := rigid.get_instance_id()
		if not _despawn_warned.has(id):
			_despawn_warned[id] = true
			push_warning(
				"TerrainFloorGuard: %s has no scene_file_path — Despawn needs a packed-scene instance. Freezing instead."
				% rigid.name
			)
		return false
	var record := {
		"scene_path": path,
		"transform": rigid.global_transform,
		"groups": PackedStringArray(rigid.get_groups()),
		"custom_state": {},
	}
	if rigid.has_method(&"get_terrain_guard_state"):
		var state: Variant = rigid.call(&"get_terrain_guard_state")
		if state is Dictionary:
			record["custom_state"] = (state as Dictionary).duplicate(true)
	_despawned.append(record)
	body_despawned.emit(path, rigid.global_transform)
	rigid.queue_free()
	return true


func _respawn(record: Dictionary) -> RigidBody3D:
	var path: String = record.get("scene_path", "")
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("TerrainFloorGuard: cannot respawn — missing scene %s" % path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("TerrainFloorGuard: cannot respawn — %s is not a PackedScene" % path)
		return null
	var instance := packed.instantiate()
	var rigid := instance as RigidBody3D
	if rigid == null:
		instance.queue_free()
		push_warning("TerrainFloorGuard: cannot respawn — root of %s is not a RigidBody3D" % path)
		return null
	var parent := _despawn_parent_node()
	parent.add_child(rigid)
	rigid.global_transform = record["transform"]
	for group_name in record.get("groups", PackedStringArray()):
		if not rigid.is_in_group(group_name):
			rigid.add_to_group(group_name)
	var custom: Dictionary = record.get("custom_state", {})
	if not custom.is_empty() and rigid.has_method(&"apply_terrain_guard_state"):
		rigid.call(&"apply_terrain_guard_state", custom)
	return rigid


func _despawn_parent_node() -> Node:
	if not despawn_parent.is_empty():
		var node := get_node_or_null(despawn_parent)
		if node:
			return node
	if get_parent():
		return get_parent()
	return self


## Positions that count as "someone is here": the player group, or the active camera when empty.
func _player_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if player_group != &"":
		for node in get_tree().get_nodes_in_group(player_group):
			var spatial := node as Node3D
			if spatial and spatial.is_inside_tree():
				positions.append(spatial.global_position)
	if positions.is_empty():
		var camera := get_viewport().get_camera_3d()
		if camera:
			positions.append(camera.global_position)
	return positions


func _nearest_distance(from: Vector3, targets: Array[Vector3]) -> float:
	var best := INF
	for target in targets:
		best = minf(best, from.distance_to(target))
	return best


## A body only parks once it has stopped moving, so nothing freezes mid-fall or mid-throw.
func _is_resting(rigid: RigidBody3D) -> bool:
	return rigid.linear_velocity.length_squared() < 0.25 \
			and rigid.angular_velocity.length_squared() < 0.25


## Terrain height under a body, re-read from the height map only once the body has moved sideways.
## A body resting on the fallback floor never moves, so this is what keeps hundreds of dropped
## items cheap: they cost a cached float per frame instead of a terrain lookup.
func _floor_under(guarded: PhysicsBody3D) -> float:
	var id := guarded.get_instance_id()
	var pos := guarded.global_position
	if _floors.has(id):
		var cached: Vector3 = _floors[id]
		if absf(cached.x - pos.x) < resample_distance and absf(cached.z - pos.z) < resample_distance:
			return cached.y
	var height := TerrainGround.height_at(self, pos)
	_floors[id] = Vector3(pos.x, height, pos.z)
	return height


## Lowest point of a body's collision shapes, in body space. Measured once per body.
func _bottom_of(guarded: PhysicsBody3D) -> Vector3:
	var id := guarded.get_instance_id()
	if _bottoms.has(id):
		return _bottoms[id]
	var to_body := guarded.global_transform.affine_inverse()
	var bounds := AABB()
	var first := true
	for node in guarded.find_children("", "CollisionShape3D", true, false):
		var cs := node as CollisionShape3D
		if cs.shape == null or cs.disabled:
			continue
		var b: AABB = (to_body * cs.global_transform) * cs.shape.get_debug_mesh().get_aabb()
		bounds = b if first else bounds.merge(b)
		first = false
	var bottom := Vector3.ZERO
	if not first:
		bottom = Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	_bottoms[id] = bottom
	return bottom
