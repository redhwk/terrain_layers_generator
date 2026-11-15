@tool
class_name TerrainLayerShaderBuilder
extends RefCounted
## Builds terrain_layer_shader.gdshader from Terrain3D's own generated shader: all three World
## Backgrounds in one shader, plus the TERRAIN LAYERS HOOK lines for the layer include.
## Everything that depends on Terrain3D's shader text lives here, so a Terrain3D update that moves
## code around only needs this file adjusted (the error names the spot that wasn't found).

const SHADER_PATH := "res://addons/terrain_layers_generator/shaders/terrain_layer_shader.gdshader"
const INCLUDE_PATH := "res://addons/terrain_layers_generator/shaders/terrain_layer_masks.gdshaderinc"
const FEATURE_TAG := "// TERRAIN LAYER SHADER FEATURES: "
## Bump when the hook code changes so existing shaders rebuild themselves.
const HOOK_VERSION := 4


## Terrain3D material options that change the generated shader code (+ the hook version).
static func material_features(mat) -> String:
	var parts := PackedStringArray(["hooks=%d" % HOOK_VERSION])
	for p in ["texture_filtering", "auto_shader_enabled", "dual_scaling_enabled", "macro_variation_enabled",
			"projection_enabled", "max_regions", "output_albedo", "output_roughness", "output_specular",
			"output_normal_map", "output_ambient_occlusion"]:
		parts.append("%s=%s" % [p, str(mat.get(p))])
	return " ".join(parts)


## True when the material uses (or should use) the layer shader and it doesn't match the material.
static func is_out_of_date(mat) -> bool:
	if mat == null:
		return false
	var sh: Shader = mat.shader_override
	if sh == null:
		return true
	if sh.resource_path != SHADER_PATH:
		return false
	return not sh.code.contains(FEATURE_TAG + material_features(mat))


## Terrain3D's generated shader code for mat's options, with World Background = Noise
## (the only mode whose code includes Flat too). host: any node in the tree (a temporary
## Terrain3D is added under it for two frames, because Terrain3D only generates code for an
## attached material).
static func generate_terrain3d_code(host: Node, mat) -> String:
	var gen = mat.duplicate()
	gen.shader_override_enabled = false
	gen.shader_override = null
	gen.world_background = 2
	var tmp = ClassDB.instantiate("Terrain3D")
	tmp.material = gen
	host.add_child(tmp)
	await host.get_tree().process_frame
	gen.shader_override_enabled = true
	await host.get_tree().process_frame
	var code: String = gen.shader_override.code if gen.shader_override else ""
	tmp.queue_free()
	return code


## Terrain3D's shader + None background + the layer hooks. "" if a spot wasn't found.
static func merge(code: String, features: String) -> String:
	if code.is_empty():
		push_error("TerrainLayerShaderBuilder: Terrain3D did not generate a shader.")
		return ""
	var src := code.replace("\r\n", "\n")
	var none_bg := "// Takes in world space XZ (UV) and returns if the coordinate should be part of the NONE background.\nbool is_none_bg(const vec2 uv) {\n\tivec4 regions = ivec4(\n\t\tget_index_coord(uv - vec2(0.5, 0.0)).z,\n\t\tget_index_coord(uv - vec2(0.0, 0.5)).z,\n\t\tget_index_coord(uv + vec2(1.0, 0.0)).z,\n\t\tget_index_coord(uv + vec2(0.0, 1.0)).z);\n\treturn any(equal(regions, ivec4(-1)));\n}\n\n"
	var ground := "\t\th = mix(h, ground_level, smoothstep(0.0, 1.0, get_region_blend(UV * _region_texel_size)));"
	var steps := [
		["layer uniforms (hook 1)", "uniform float depth_blur : hint_range(0.0, 35.0, 0.1) = 0.0;\ngroup_uniforms;\n",
			"uniform float depth_blur : hint_range(0.0, 35.0, 0.1) = 0.0;\ngroup_uniforms;\n\n// TERRAIN LAYERS HOOK 1/3: Terrain Layer Masks.\n#include \"%s\"\n" % INCLUDE_PATH],
		["None background check", "// Takes in UV2 region space coordinates, returns 1.0 or 0.0 if a region is present or not.",
			none_bg + "// Takes in UV2 region space coordinates, returns 1.0 or 0.0 if a region is present or not."],
		["None background discard", "&& (hole\n\t\t)){", "&& (hole\n\t\t|| (_background_mode == 0u && is_none_bg(UV))\n\t\t)){"],
		["ground level", ground, "\t\tif (_background_mode != 0u) {\n\t" + ground + "\n\t\t}"],
		["auto shader (hook 2)", "\t\tcontrol = control * (1u - is_auto) + u_auto * is_auto;",
			"\t\t// TERRAIN LAYERS HOOK 2/3: a TerrainLayerMasks layer stack replaces the 2-texture auto shader\n\t\t// (only where a corner is auto, so baked / painted areas cost nothing extra).\n\t\tif (_tlm_layer_count > 0 && any(notEqual(is_auto, uvec4(0u)))) {\n\t\t\tu_auto = tlm_control(v_vertex, w_normal, base_ddx.xz, base_ddy.xz);\n\t\t}\n\t\tcontrol = control * (1u - is_auto) + u_auto * is_auto;"],
	]
	steps.append(["blend sharpness (hook 3)", "\tfloat sharpness = fma(60., blend_sharpness, 4.);",
		"\t// TERRAIN LAYERS HOOK 3/3: per-texture Blend Sharpness from the layer stack.\n\tfloat sharpness = fma(60., tlm_sharpness(texture_id, blend_sharpness), 4.);"])
	for s in steps:
		if not src.contains(s[1]):
			push_error("TerrainLayerShaderBuilder: couldn't find the %s spot in Terrain3D's shader (did Terrain3D change?). Shader not rebuilt." % s[0])
			return ""
		src = src.replace(s[1], s[2])
	var blank := RegEx.create_from_string("(\\n[ \\t]*){4,}\\n")
	src = blank.sub(src, "\n\n", true)
	var header := "/* Terrain Layer Shader: Terrain3D's own shader, generated by TerrainLayerMasks > Rebuild Shader.\n * Rebuilt automatically in the editor when the Terrain3D material's shader options change; hand edits are lost.\n * Additions to Terrain3D's code: None, Flat and Noise World Backgrounds in one shader, and the\n * TERRAIN LAYERS HOOK lines for Terrain Layer Masks (%s).\n */\n" % INCLUDE_PATH + FEATURE_TAG + features + "\n\n"
	return header + src


## Writes the shader to SHADER_PATH and makes it mat's Shader Override.
static func save_and_assign(mat, code: String) -> Error:
	var shader: Shader = mat.shader_override if mat.shader_override and mat.shader_override.resource_path == SHADER_PATH else null
	if shader == null:
		shader = load(SHADER_PATH) if ResourceLoader.exists(SHADER_PATH) else Shader.new()
	shader.code = code
	if shader.resource_path.is_empty():
		shader.resource_path = SHADER_PATH
	var err := ResourceSaver.save(shader, SHADER_PATH)
	mat.shader_override = shader
	mat.shader_override_enabled = true
	return err
