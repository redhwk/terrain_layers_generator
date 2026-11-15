@tool
class_name TerrainLayerStack
extends Resource
## A terrain layer stack: the preset you assign to TerrainLayerMasks.
## Save it as a .tres (Inspector > Save As) to reuse it on other terrains;
## use "Make Unique" first if you want to change a copy without changing the preset.

## Notes about this preset.
@export_multiline var description := ""

## One layer per Terrain3D texture: Layer N = texture N (kept in sync by TerrainLayerMasks).
## Paint Order on each layer sets what paints over what.
@export var layers: Array[TerrainMaskLayer] = []:
	set(value):
		for l in layers:
			if l and l.changed.is_connected(emit_changed):
				l.changed.disconnect(emit_changed)
		layers = value
		for l in layers:
			if l and not l.changed.is_connected(emit_changed):
				l.changed.connect(emit_changed)
		emit_changed()
