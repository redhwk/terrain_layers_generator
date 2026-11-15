// Terrain Layer Masks: texture layers (Height / Slope / Noise / Texture masks)
// for Terrain3D's auto shader. Every value here is set by the TerrainLayerMasks node
// (TerrainLayerMasks script); don't set them on the material.
//
// Layers are composited bottom to top: each layer covers the layers below it by its mask.
// Terrain3D renders two textures per vertex, so the two strongest layers become the
// base / overlay / blend that the rest of the shader uses.

#define TLM_MAX_LAYERS 32
#define TLM_MAX_MASKS 64

uniform int _tlm_layer_count = 0;
// x texture id, y opacity, z first mask index, w mask count
uniform vec4 _tlm_layers[TLM_MAX_LAYERS];
// x type (0 height, 1 slope, 2 noise, 3 texture, 4 Terrain3D auto slope), y blend mode, z mask curve row, w strength curve row (-1 = none)
uniform vec4 _tlm_mask_a[TLM_MAX_MASKS];
// height / slope: x min, y max, z outside range (0 zero, 1 extend edges), w invert
// noise: x noise layer, y billow, w invert. texture: x texture id, y start at, w invert
// Terrain3D auto slope: x auto slope, y height reduction, w invert
uniform vec4 _tlm_mask_b[TLM_MAX_MASKS];
// noise: x 1 / tile size, y rotation (radians), zw offset (meters)
uniform vec4 _tlm_mask_c[TLM_MAX_MASKS];
// Per-texture blend sharpness + 1 (0 = use the material's Blend Sharpness).
uniform float _tlm_texture_sharpness[32];
uniform float _tlm_curve_rows = 1.0;
uniform highp sampler2D _tlm_curves : filter_linear, repeat_disable;
uniform highp sampler2DArray _tlm_noise : filter_linear_mipmap, repeat_enable;

// Blend sharpness where two textures meet: the softer of the two textures' settings wins.
float tlm_sharpness(ivec2 ids, float material_sharpness) {
	float a = _tlm_texture_sharpness[ids.x & 31];
	float b = _tlm_texture_sharpness[ids.y & 31];
	return min(a > 0.5 ? a - 1.0 : material_sharpness, b > 0.5 ? b - 1.0 : material_sharpness);
}

float tlm_curve(float row, float x) {
	x = clamp(x, 0.0, 1.0);
	if (row < 0.0) {
		return x;
	}
	vec2 uv = vec2(x * (255.0 / 256.0) + (0.5 / 256.0), (row + 0.5) / _tlm_curve_rows);
	return textureLod(_tlm_curves, uv, 0.0).r;
}

float tlm_range(float v, vec4 b, float curve_row) {
	float t = (v - b.x) / max(b.y - b.x, 0.0001);
	if (b.z < 0.5 && (t < 0.0 || t > 1.0)) {
		return 0.0;
	}
	return tlm_curve(curve_row, t);
}

float tlm_blend(float a, float b, int mode) {
	if (mode == 0) {
		return a * b;
	} else if (mode == 1) {
		return max(a, b);
	} else if (mode == 2) {
		return min(a, b);
	} else if (mode == 3) {
		return clamp(a + b, 0.0, 1.0);
	}
	return clamp(a - b, 0.0, 1.0);
}

// Returns a Terrain3D control value (base id, overlay id, blend) for this pixel.
// dpdx / dpdy: screen derivatives of the world XZ position, for noise mipmapping.
uint tlm_control(vec3 wpos, vec3 wnormal, vec2 dpdx, vec2 dpdy) {
	float slope = degrees(acos(clamp(wnormal.y, -1.0, 1.0)));
	int count = min(_tlm_layer_count, TLM_MAX_LAYERS);
	float m[TLM_MAX_LAYERS];

	// The lowest layer fills whatever the others leave, so its masks and opacity don't apply.
	m[0] = 1.0;
	for (int i = 1; i < count; i++) {
		vec4 layer = _tlm_layers[i];
		int first = int(layer.z);
		int n = int(layer.w);
		float value = 1.0;
		for (int k = 0; k < n; k++) {
			int mi = first + k;
			vec4 a = _tlm_mask_a[mi];
			vec4 b = _tlm_mask_b[mi];
			int type = int(a.x);
			float x = 0.0;
			if (type == 0) {
				x = tlm_range(wpos.y, b, a.z);
			} else if (type == 1) {
				x = tlm_range(slope, b, a.z);
			} else if (type == 2) {
				vec4 c = _tlm_mask_c[mi];
				vec2 cs = vec2(cos(c.y), sin(c.y));
				mat2 rot = mat2(vec2(cs.x, cs.y), vec2(-cs.y, cs.x));
				vec2 uv = rot * (wpos.xz - c.zw) * c.x;
				x = textureGrad(_tlm_noise, vec3(uv, b.x), rot * dpdx * c.x, rot * dpdy * c.x).r;
				if (b.y > 0.5) {
					x = abs(x * 2.0 - 1.0);
				}
				x = tlm_curve(a.z, x);
			} else if (type == 4) {
				// Terrain3D auto shader slope formula (b.x auto slope, b.y height reduction).
				x = clamp(fma(b.x * 2.0, wnormal.y - 1.0, 1.0) - b.y * 0.01 * wpos.y, 0.0, 1.0);
				x = tlm_curve(a.z, x);
			} else {
				// Texture mask: how visible the chosen texture is from the layers below this one.
				int tex = int(b.x);
				float acc = 0.0;
				for (int j = 0; j < i; j++) {
					if (int(_tlm_layers[j].x) == tex) {
						float vis = m[j];
						for (int q = j + 1; q < i; q++) {
							vis *= 1.0 - m[q];
						}
						acc += vis;
					}
				}
				// Start At (b.y): only count the texture where it is at least that visible.
				acc = clamp((acc - b.y) / max(1.0 - b.y, 0.0001), 0.0, 1.0);
				x = tlm_curve(a.z, acc);
			}
			if (b.w > 0.5) {
				x = 1.0 - x;
			}
			x = tlm_curve(a.w, x);
			if (k == 0) {
				value = x;
			} else {
				value = tlm_blend(value, x, int(a.y));
			}
		}
		m[i] = clamp(value, 0.0, 1.0) * layer.y;
	}

	// Visible weight per texture id, top layer first. ord = paint position of the texture's top layer.
	float tw[32];
	int ord[32];
	for (int t = 0; t < 32; t++) {
		tw[t] = 0.0;
		ord[t] = -1;
	}
	float remaining = 1.0;
	for (int i = count - 1; i >= 0; i--) {
		float vis = m[i] * remaining;
		remaining -= vis;
		int id = int(_tlm_layers[i].x) & 31;
		tw[id] += vis;
		if (ord[id] < 0) {
			ord[id] = i;
		}
	}
	if (count > 0) {
		// Nothing covers this spot: the bottom layer shows.
		int id = int(_tlm_layers[0].x) & 31;
		tw[id] += remaining;
		ord[id] = max(ord[id], 0);
	}

	int id0 = 0;
	int id1 = 0;
	float w0 = -1.0;
	float w1 = -1.0;
	float w2 = 0.0;
	for (int t = 0; t < 32; t++) {
		float w = tw[t];
		if (w > w0) {
			w2 = w1;
			w1 = w0;
			id1 = id0;
			w0 = w;
			id0 = t;
		} else if (w > w1) {
			w2 = w1;
			w1 = w;
			id1 = t;
		} else if (w > w2) {
			w2 = w;
		}
	}
	// Only two textures can show. Measuring both against the third strongest fades the second
	// out before a third takes its place, so switching textures never makes a hard edge.
	w2 = max(w2, 0.0);
	float b0 = w0 - w2;
	float b1 = max(w1 - w2, 0.0);
	int base_id = id0;
	int over_id = id0;
	float blend = 0.0;
	if (b1 > 0.0) {
		// The lower layer is always the base and the higher the overlay, like Terrain3D's auto shader:
		// the overlay settles into the base's crevices, so swapping them by strength would leave a seam.
		if (ord[id0] < ord[id1]) {
			over_id = id1;
			blend = b1 / max(b0 + b1, 0.0001);
		} else {
			base_id = id1;
			blend = b0 / max(b0 + b1, 0.0001);
		}
	}
	return ((uint(base_id) & 0x1Fu) << 27u) | ((uint(over_id) & 0x1Fu) << 22u) | ((uint(blend * 255.0 + 0.5) & 0xFFu) << 14u);
}
