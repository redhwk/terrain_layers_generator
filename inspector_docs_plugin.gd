@tool
extends EditorInspectorPlugin
## Adds a Doc control at the top of the Inspector for this addon's nodes.
## Godot's header DOC button opens the engine base class (Node / Node3D) for GDScript — not
## class_name help — so this is how users open the addon guides in one click.

const DocsHelper := preload("res://addons/terrain_layers_generator/docs_helper.gd")


func _can_handle(object: Object) -> bool:
	return _doc_file(object) != ""


func _parse_begin(object: Object) -> void:
	var doc_file := _doc_file(object)
	if doc_file.is_empty():
		return
	var btn := Button.new()
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.icon = EditorInterface.get_base_control().get_theme_icon(&"Help", &"EditorIcons")
	btn.text = "Doc"
	btn.tooltip_text = "Open this node's addon guide. (Godot's header Doc opens the engine base class for GDScript nodes.)"
	btn.pressed.connect(func (): DocsHelper.open(doc_file))
	add_custom_control(btn)


func _doc_file(object: Object) -> String:
	if object.has_method(&"documentation_file"):
		return str(object.call(&"documentation_file"))
	if object is TerrainGenerator:
		return "terrain_generator.md"
	if object is TerrainLayerMasks:
		return "terrain_layers.md"
	if object is TerrainLayerBaker:
		return "terrain_layer_baking_tests.md"
	return ""
