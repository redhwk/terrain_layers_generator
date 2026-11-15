@tool
class_name TerrainLayersGeneratorDocs
extends RefCounted
## Opens markdown guides in the Script workspace (same as double-clicking in FileSystem).
## Godot does not expose ScriptEditor.open_file() to GDScript, so we simulate a FileSystem
## drag onto the script list (force_drag + accessibility_drop).


const DOCS_DIR := "res://addons/terrain_layers_generator/docs/"


static func open(doc_file: String) -> void:
	var path := DOCS_DIR.path_join(doc_file)
	if not FileAccess.file_exists(path):
		push_warning("TerrainLayersGeneratorDocs: missing %s" % path)
		return
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		push_warning("TerrainLayersGeneratorDocs: could not read %s" % path)
		return
	if not Engine.is_editor_hint() or not Engine.has_singleton(&"EditorInterface"):
		push_warning("TerrainLayersGeneratorDocs: editor only.")
		return
	var editor = Engine.get_singleton(&"EditorInterface")
	if not _try_open_in_script_editor(editor, path, text):
		push_warning("TerrainLayersGeneratorDocs: could not open %s in Script editor." % path)


static func _try_open_in_script_editor(editor, path: String, text: String) -> bool:
	editor.set_main_screen_editor("Script")
	var dock = editor.get_file_system_dock()
	if dock != null and dock.has_method(&"navigate_to_path"):
		dock.navigate_to_path(path)

	var se = editor.get_script_editor()
	if se == null:
		return false

	# Bound in a future Godot release; harmless to try.
	if se.has_method(&"open_file"):
		se.call(&"open_file", path)
		return _focus_editor_showing_text(se, text)

	return _open_via_script_list_drop(editor, se, path, text)


static func _open_via_script_list_drop(editor, se, path: String, text: String) -> bool:
	# ScriptEditor::drop_data_fw is not bound; the script ItemList forwards drops to it.
	# force_drag + accessibility_drop goes through that forwarding.
	# Drop may leave an older tab selected (insert index), so we search all open editors
	# and focus the one that matches this guide.
	var data := {
		"type": "files",
		"files": PackedStringArray([path]),
	}
	var base: Control = editor.get_base_control()
	var proxy := Control.new()
	proxy.name = &"TerrainLayersDocsDragProxy"
	base.add_child(proxy)

	var opened := false
	for list in _find_item_lists(se):
		proxy.force_drag(data, null)
		list.accessibility_drop()
		if _focus_editor_showing_text(se, text):
			opened = true
			break

	var vp: Viewport = base.get_viewport()
	if vp != null and vp.gui_is_dragging():
		vp.gui_cancel_drag()
	proxy.queue_free()
	return opened


static func _find_item_lists(node: Node) -> Array[ItemList]:
	var out: Array[ItemList] = []
	_collect_item_lists(node, out)
	return out


static func _collect_item_lists(node: Node, out: Array[ItemList]) -> void:
	if node is ItemList:
		out.append(node as ItemList)
	for child in node.get_children():
		_collect_item_lists(child, out)


static func _focus_editor_showing_text(se, text: String) -> bool:
	var first_line := _first_line(text)
	for ed in se.get_open_script_editors():
		var ed_base = ed.get_base_editor()
		if ed_base == null or not (ed_base is TextEdit):
			continue
		if not _editor_text_matches((ed_base as TextEdit).text, first_line, text):
			continue
		var parent: Node = ed.get_parent()
		if parent is TabContainer:
			(parent as TabContainer).current_tab = ed.get_index()
		return true
	return false


static func _editor_text_matches(shown: String, first_line: String, full_text: String) -> bool:
	if first_line.is_empty():
		return not shown.is_empty()
	if _first_line(shown) == first_line:
		return true
	# Same file already open with identical contents.
	var needle := full_text.substr(0, mini(80, full_text.length()))
	return shown.begins_with(needle)


static func _first_line(text: String) -> String:
	return text.get_slice("\n", 0).strip_edges()
