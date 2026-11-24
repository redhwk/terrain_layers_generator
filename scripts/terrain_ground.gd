class_name TerrainGround
extends RefCounted

## Terrain3D surface queries that work without physics colliders.
##
## Terrain3D only builds collision shapes around its collision target (Collision > Mode = Dynamic),
## which is why distant regions have no collider and anything resting on them falls through. The
## height map, on the other hand, stays loaded for every region, so reading it gives parked
## vehicles and dropped objects a floor out there.
##
## Nothing here writes to Terrain3D or changes its settings; it only reads [code]terrain.data[/code].
## Used by [TerrainFloorGuard], and usable directly from your own scripts:
## [codeblock]
## var h := TerrainGround.height_at(self, global_position)
## if not is_nan(h):
##     global_position.y = maxf(global_position.y, h)
## [/codeblock]

## Terrain3D found last time, so every caller doesn't re-scan the scene tree.
static var _terrain_id: int = 0
## Scene the cache belongs to; a new scene (or a scene with no terrain) triggers one fresh scan.
static var _scene_id: int = 0


# --- Static methods ---

## Terrain3D of the running scene, or null when the scene has none.
static func get_terrain(context: Node) -> Terrain3D:
	if context == null or not context.is_inside_tree():
		return null
	var scene: Node = context.get_tree().current_scene
	if scene == null:
		scene = context.get_tree().root
	if scene == null:
		return null
	var scene_id := scene.get_instance_id()
	if scene_id == _scene_id:
		if _terrain_id == 0:
			return null
		var cached := instance_from_id(_terrain_id) as Terrain3D
		if is_instance_valid(cached) and cached.is_inside_tree():
			return cached
	_scene_id = scene_id
	_terrain_id = 0
	var terrain := scene as Terrain3D
	if terrain == null:
		var found: Array[Node] = scene.find_children("", "Terrain3D", true, false)
		if found.is_empty():
			return null
		terrain = found[0] as Terrain3D
	_terrain_id = terrain.get_instance_id()
	return terrain


## Terrain surface height under [param global_position], or NAN where there is no Terrain3D, no
## region, or a hole. Callers must treat NAN as "no ground here" so caves and hangars carved with
## holes stay passable.
static func height_at(context: Node, global_position: Vector3) -> float:
	var terrain := get_terrain(context)
	if terrain == null or terrain.data == null:
		return NAN
	# Same call Terrain3DObjects uses to place objects, so this matches the visible surface.
	return terrain.data.get_surface_height(global_position)


## Terrain surface normal at [param global_position], or [constant Vector3.UP] when unavailable.
static func normal_at(context: Node, global_position: Vector3) -> Vector3:
	var terrain := get_terrain(context)
	if terrain == null or terrain.data == null:
		return Vector3.UP
	var normal: Vector3 = terrain.data.get_normal(global_position)
	if is_nan(normal.x) or is_nan(normal.y) or is_nan(normal.z) or normal.length_squared() < 0.0001:
		return Vector3.UP
	return normal.normalized()
