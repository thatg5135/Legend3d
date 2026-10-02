// Flames, lantern glass, embers: always full bright.
// With use_tex, draws a two-frame flame sprite that crackles.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.7, 0.3, 1.0);
uniform float flicker = 0.0;
uniform sampler2D flame_tex : source_color, filter_nearest, repeat_disable;
uniform bool use_tex = false;

void fragment() {
	if (use_tex) {
		float ph = floor(TIME * 9.0 + NODE_POSITION_WORLD.x * 3.0 + NODE_POSITION_WORLD.z * 5.0);
		vec2 uv = vec2(UV.x * 0.5 + 0.5 * mod(ph, 2.0), UV.y);
		vec4 t = texture(flame_tex, uv);
		if (t.a < 0.5) {
			discard;
		}
		ALBEDO = t.rgb;
	} else {
		float f = 1.0 - flicker * 0.25 * (0.5 + 0.5 * sin(TIME * 13.0 + NODE_POSITION_WORLD.x * 7.0) * sin(TIME * 7.3));
		ALBEDO = color.rgb * f;
	}
}
