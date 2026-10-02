// World surfaces: hand-painted textures, soft warm/cool light, a hint of
// banding, fine ordered dither at the light's edges, darker wall bases.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 0.5;      // repeats per meter
uniform bool use_uv = false;       // use the mesh's UVs (meters) instead of world projection
uniform float steps = 6.0;         // light bands
uniform float band = 0.25;         // how strongly light snaps to them
uniform float dither = 0.35;       // fine pattern where light falls off (0 = none)
uniform float wrap = 0.0;          // >0 lets light reach round the back a little
uniform float floor_h = 3.4;       // storey height, for darkening wall bases

varying vec3 wpos;
varying vec3 wnrm;

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return float(m[x + y * 4]) / 16.0 - 0.5;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv;
	if (use_uv) {
		uv = UV;
	} else {
		vec3 n = abs(wnrm);
		if (n.y >= n.x && n.y >= n.z) {
			uv = wpos.xz;
		} else if (n.x >= n.z) {
			uv = vec2(wpos.z, -wpos.y);
		} else {
			uv = vec2(wpos.x, -wpos.y);
		}
	}
	vec3 col = texture(albedo_tex, uv * uv_scale).rgb * tint.rgb;
	// walls darken toward the floor (soot, damp, contact shadow)
	if (abs(wnrm.y) < 0.5) {
		float yl = mod(wpos.y + 0.02, floor_h);
		col *= mix(0.72, 1.0, smoothstep(0.0, 0.7, yl));
	}
	ALBEDO = col;
}

void light() {
	float nl = dot(NORMAL, LIGHT);
	nl = max((nl + wrap) / (1.0 + wrap), 0.0);
	float v = nl * ATTENUATION;
	float d = bayer4(FRAGCOORD.xy) * dither / steps;
	float q = floor((v + d) * steps + 0.5) / steps;
	v = mix(v, max(q, 0.0), band * smoothstep(0.0, 0.08, v));
	DIFFUSE_LIGHT += v * LIGHT_COLOR / PI;
}
