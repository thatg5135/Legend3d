// Crepuscular rays: streaks of light from the sun (or moon) across the
// picture, broken up by roofs, trees and clouds in front of it.
// Only bright pixels close to the sun feed the rays, so open sky doesn't
// wash out; the result is screen-blended so nothing clips to white.
shader_type canvas_item;
uniform vec2 light_pos = vec2(0.5, 0.3);
uniform float strength = 0.0;
uniform vec3 ray_col : source_color = vec3(1.0, 0.9, 0.7);
uniform float threshold = 0.75;
uniform float aspect = 1.6;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (strength <= 0.001) {
		COLOR = base;
	} else {
		vec2 delta = (UV - light_pos) / 28.0;
		vec2 uv = UV;
		float illum = 0.0;
		float decay = 1.0;
		for (int i = 0; i < 28; i++) {
			uv -= delta;
			vec3 s = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
			vec2 d = (uv - light_pos) * vec2(aspect, 1.0);
			float near = 1.0 - smoothstep(0.04, 0.32, length(d));
			float l = max(dot(s, vec3(0.3, 0.59, 0.11)) - threshold, 0.0) / (1.0 - threshold);
			illum += l * near * decay;
			decay *= 0.94;
		}
		illum /= 14.0;
		vec3 add = clamp(ray_col * illum * strength * 1.4, 0.0, 1.0);
		COLOR = vec4(1.0 - (1.0 - base.rgb) * (1.0 - add), 1.0);
	}
}
