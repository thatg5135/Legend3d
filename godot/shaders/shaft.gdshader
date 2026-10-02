// A beam of light falling through a window or doorway: additive, brightest
// at the opening, fading along its length and toward its edges, with drifting motes.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.9, 0.7, 1.0);
uniform float strength = 0.25;

varying vec3 lp;

void vertex() {
	lp = VERTEX;  // box mesh: x,y across the beam in -0.5..0.5 (scaled), z along -0.5..0.5
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	float along = clamp(lp.z + 0.5, 0.0, 1.0);          // 0 at the opening
	float fade = (1.0 - along) * (1.0 - along);
	vec2 e = abs(lp.xy) * 2.0;
	float edge = (1.0 - smoothstep(0.55, 1.0, e.x)) * (1.0 - smoothstep(0.55, 1.0, e.y));
	vec2 cell = floor(FRAGCOORD.xy / 3.0);
	float mote = step(0.996, hash(cell + floor(TIME * 2.0))) * 0.6;
	ALBEDO = color.rgb * strength * fade * edge * (1.0 + mote);
}
