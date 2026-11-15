@tool
class_name TerrainLayerEvaluator
extends RefCounted
## CPU version of terrain_layer_masks.gdshaderinc: gives the same base / overlay / blend the
## shader would for a point. Used by TerrainLayerBaker (and anything that needs "which texture is
## here?"). Keep the math in step with the shader include. Read-only after creation, so it can be
## used from worker threads.

const CURVE_WIDTH := 256

var layer_count := 0
var layers: PackedVector4Array
var mask_a: PackedVector4Array
var mask_b: PackedVector4Array
var mask_c: PackedVector4Array
var curves := PackedFloat32Array()
var noise: Array[PackedByteArray] = []
var noise_size := 1


## params: TerrainLayerMasks.build_params() result. curve_image: FORMAT_RF, one curve per row.
## noise_images: FORMAT_L8 square tiles in the same order as the shader's noise texture array.
func _init(params: Dictionary, curve_image: Image, noise_images: Array[Image]) -> void:
	layer_count = int(params.get("_tlm_layer_count", 0))
	layers = params.get("_tlm_layers", PackedVector4Array())
	mask_a = params.get("_tlm_mask_a", PackedVector4Array())
	mask_b = params.get("_tlm_mask_b", PackedVector4Array())
	mask_c = params.get("_tlm_mask_c", PackedVector4Array())
	if curve_image:
		var img := curve_image.duplicate() as Image
		if img.get_format() != Image.FORMAT_RF:
			img.convert(Image.FORMAT_RF)
		curves = img.get_data().to_float32_array()
	for n in noise_images:
		var img := n.duplicate() as Image
		img.clear_mipmaps()
		if img.get_format() != Image.FORMAT_L8:
			img.convert(Image.FORMAT_L8)
		noise.append(img.get_data())
		noise_size = img.get_width()


func _curve(row: float, x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	if row < 0.0:
		return x
	var t := x * (CURVE_WIDTH - 1)
	var i := int(t)
	var base := int(row) * CURVE_WIDTH
	var a := curves[base + i]
	var b := curves[base + mini(i + 1, CURVE_WIDTH - 1)]
	return lerpf(a, b, t - i)


func _range(v: float, b: Vector4, row: float) -> float:
	var t := (v - b.x) / maxf(b.y - b.x, 0.0001)
	if b.z < 0.5 and (t < 0.0 or t > 1.0):
		return 0.0
	return _curve(row, t)


func _blend(a: float, b: float, mode: int) -> float:
	match mode:
		0: return a * b
		1: return maxf(a, b)
		2: return minf(a, b)
		3: return clampf(a + b, 0.0, 1.0)
	return clampf(a - b, 0.0, 1.0)


## Bilinear, wrapping sample of a noise tile (uv in tiles).
func _noise(layer: int, uv: Vector2) -> float:
	if layer < 0 or layer >= noise.size():
		return 0.0
	var data := noise[layer]
	var s := noise_size
	var px := uv.x * s - 0.5
	var py := uv.y * s - 0.5
	var x0 := floori(px)
	var y0 := floori(py)
	var fx := px - x0
	var fy := py - y0
	x0 = posmod(x0, s)
	y0 = posmod(y0, s)
	var x1 := (x0 + 1) % s
	var y1 := (y0 + 1) % s
	var top := lerpf(data[y0 * s + x0], data[y0 * s + x1], fx)
	var bottom := lerpf(data[y1 * s + x0], data[y1 * s + x1], fx)
	return lerpf(top, bottom, fy) / 255.0


## Control bits (base / overlay / blend, auto off) for a world position and surface normal.
func evaluate(pos: Vector3, normal: Vector3) -> int:
	if mini(layer_count, 32) <= 0:
		return -1
	var r := _texture_weights(pos, normal)
	return _pick(r[0], r[1])


## How visible each texture id (0..31) is at a point before the two-texture limit (sums to 1).
func texture_weights(pos: Vector3, normal: Vector3) -> PackedFloat32Array:
	if mini(layer_count, 32) <= 0:
		return PackedFloat32Array()
	return _texture_weights(pos, normal)[0]


## [texture weights (32), paint position of each texture's top layer (32, -1 = none)]
func _texture_weights(pos: Vector3, normal: Vector3) -> Array:
	var count := mini(layer_count, 32)
	var slope := rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))
	var m := PackedFloat32Array()
	m.resize(count)
	# The lowest layer fills whatever the others leave, so its masks and opacity don't apply.
	m[0] = 1.0
	for i in range(1, count):
		var layer := layers[i]
		var first := int(layer.z)
		var n := int(layer.w)
		var value := 1.0
		for k in n:
			var mi := first + k
			var a := mask_a[mi]
			var b := mask_b[mi]
			var type := int(a.x)
			var x := 0.0
			if type == 0:
				x = _range(pos.y, b, a.z)
			elif type == 1:
				x = _range(slope, b, a.z)
			elif type == 2:
				var c := mask_c[mi]
				var cs := Vector2(cos(c.y), sin(c.y))
				var p := Vector2(pos.x - c.z, pos.z - c.w)
				var uv := Vector2(cs.x * p.x - cs.y * p.y, cs.y * p.x + cs.x * p.y) * c.x
				x = _noise(int(b.x), uv)
				if b.y > 0.5:
					x = absf(x * 2.0 - 1.0)
				x = _curve(a.z, x)
			elif type == 4:
				x = clampf(b.x * 2.0 * (normal.y - 1.0) + 1.0 - b.y * 0.01 * pos.y, 0.0, 1.0)
				x = _curve(a.z, x)
			else:
				var tex := int(b.x)
				var acc := 0.0
				for j in i:
					if int(layers[j].x) == tex:
						var vis := m[j]
						for q in range(j + 1, i):
							vis *= 1.0 - m[q]
						acc += vis
				acc = clampf((acc - b.y) / maxf(1.0 - b.y, 0.0001), 0.0, 1.0)
				x = _curve(a.z, acc)
			if b.w > 0.5:
				x = 1.0 - x
			x = _curve(a.w, x)
			value = x if k == 0 else _blend(value, x, int(a.y))
		m[i] = clampf(value, 0.0, 1.0) * layer.y

	var tw := PackedFloat32Array()
	tw.resize(32)
	var ord := PackedInt32Array()
	ord.resize(32)
	ord.fill(-1)
	var remaining := 1.0
	for i in range(count - 1, -1, -1):
		var vis := m[i] * remaining
		remaining -= vis
		var id := int(layers[i].x) & 31
		tw[id] += vis
		if ord[id] < 0:
			ord[id] = i
	var bottom := int(layers[0].x) & 31
	tw[bottom] += remaining
	ord[bottom] = maxi(ord[bottom], 0)
	return [tw, ord]


## The two strongest textures as Terrain3D control bits (same choice as the shader).
func _pick(tw: PackedFloat32Array, ord: PackedInt32Array) -> int:
	var id0 := 0
	var id1 := 0
	var w0 := -1.0
	var w1 := -1.0
	var w2 := 0.0
	for t in 32:
		var w := tw[t]
		if w > w0:
			w2 = w1
			w1 = w0
			id1 = id0
			w0 = w
			id0 = t
		elif w > w1:
			w2 = w1
			w1 = w
			id1 = t
		elif w > w2:
			w2 = w
	w2 = maxf(w2, 0.0)
	var b0 := w0 - w2
	var b1 := maxf(w1 - w2, 0.0)
	var base_id := id0
	var over_id := id0
	var blend := 0.0
	if b1 > 0.0:
		if ord[id0] < ord[id1]:
			over_id = id1
			blend = b1 / maxf(b0 + b1, 0.0001)
		else:
			base_id = id1
			blend = b0 / maxf(b0 + b1, 0.0001)
	return Terrain3DBridge.encode_textures(base_id, over_id, blend)
