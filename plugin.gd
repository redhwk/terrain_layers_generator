@tool
extends EditorPlugin
## TerrainLayers and TerrainGenerator for Terrain3D — editor helpers (Flatten height picker),
## Inspector Doc guides, and a Terrain3D dependency check on enable.

const InspectorDocsPlugin := preload("res://addons/terrain_layers_generator/inspector_docs_plugin.gd")

var _inspector_docs: EditorInspectorPlugin


func _enter_tree() -> void:
	_warn_if_terrain3d_missing()
	_inspector_docs = InspectorDocsPlugin.new()
	add_inspector_plugin(_inspector_docs)


func _exit_tree() -> void:
	if _inspector_docs:
		remove_inspector_plugin(_inspector_docs)
		_inspector_docs = null


func _handles(object: Object) -> bool:
	return object is TerrainGeneratorFlatten


func _make_visible(_visible: bool) -> void:
	pass


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	var target := TerrainGeneratorFlatten.height_pick_target
	if target == null or not is_instance_valid(target):
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		TerrainGeneratorFlatten.height_pick_target = null
		print("TerrainGeneratorFlatten: height pick cancelled.")
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _terrain_hit(camera, target)
		if is_nan(hit.x):
			print("TerrainGeneratorFlatten: click missed terrain; try again or Esc to cancel.")
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		target.apply_picked_height(hit)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _terrain_hit(camera: Camera3D, flatten: TerrainGeneratorFlatten) -> Vector3:
	var gen := flatten.get_generator()
	if gen == null:
		return Vector3(NAN, NAN, NAN)
	var terrain = gen.get_terrain()
	if terrain == null or not terrain.has_method(&"get_intersection"):
		return Vector3(NAN, NAN, NAN)

	var viewport: SubViewport = camera.get_parent() as SubViewport
	if viewport == null:
		return Vector3(NAN, NAN, NAN)
	var vp_mouse := viewport.get_mouse_position()
	var full_resolution := true
	var container := viewport.get_parent()
	if container is SubViewportContainer and container.stretch_shrink == 2:
		full_resolution = false
	var mouse_pos := vp_mouse if full_resolution else vp_mouse * 0.5
	var origin := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	var hit: Vector3 = terrain.get_intersection(origin, dir, true)
	if hit.z > 3.4e38 or is_nan(hit.y):
		return Vector3(NAN, NAN, NAN)
	return hit


func _warn_if_terrain3d_missing() -> void:
	var has_class := ClassDB.class_exists(&"Terrain3D")
	var cfg_path := "res://addons/terrain_3d/plugin.cfg"
	var has_addon := FileAccess.file_exists(cfg_path)
	if has_class or has_addon:
		return
	var message := "TerrainLayers and TerrainGenerator for Terrain3D requires the Terrain3D addon. Install and enable Terrain3D, then reload this plugin."
	printerr(message)
	var editor = get_editor_interface() if Engine.is_editor_hint() else null
	if editor == null:
		return
	if editor.has_method(&"get_editor_toaster"):
		editor.get_editor_toaster().push_toast(message)
	var dialog := AcceptDialog.new()
	dialog.title = "Terrain3D required"
	dialog.dialog_text = message
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	editor.get_base_control().add_child(dialog)
	dialog.popup_centered()
