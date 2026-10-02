// Grass tufts: cut-out, gently swaying in the wind, lit softly from both sides.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;
uniform sampler2D tex : source_color, filter_nearest_mipmap, repeat_disable;
uniform float wind = 1.0;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.7 + w.x * 0.6 + w.z * 0.4) * 0.06 * wind * UV.y;
	VERTEX.x += sway * (1.0 - UV.y) * 2.0;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * vec3(0.78, 0.8, 0.72);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}

void light() {
	DIFFUSE_LIGHT += (0.35 + 0.4 * max(dot(NORMAL, LIGHT), 0.0)) * ATTENUATION * LIGHT_COLOR / PI;
}
