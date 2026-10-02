// The sky: gradient by sun height, sun and its glow, a moon drawn in its real
// phase, stars at night, and two layers of drifting painted clouds whose
// cover and darkness follow Legend's weather.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.30, 0.52, 0.82);
uniform vec3 horizon : source_color = vec3(0.72, 0.82, 0.90);
uniform vec3 ground_col : source_color = vec3(0.22, 0.24, 0.22);
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.8);
uniform vec3 sun_col : source_color = vec3(1.0, 0.92, 0.8);
uniform float sun_vis = 1.0;
uniform vec3 moon_dir = vec3(0.0, 0.5, 0.8);
uniform float moon_phase = 0.5;     // 0 new, .25 first quarter, .5 full, .75 last quarter
uniform float moon_vis = 0.0;
uniform float night = 0.0;          // 0 day .. 1 full night (stars)
uniform float day = 1.0;            // how lit the clouds are
uniform float cover = 0.35;         // cloud cover 0..1
uniform float cloud_dark = 0.0;     // 0 white puffs .. 1 storm clouds
uniform vec2 wind = vec2(0.008, 0.003);
uniform float flash = 0.0;          // lightning

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h > 0.0) {
		col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.5));
	} else {
		col = mix(horizon * 0.85, ground_col, clamp(-h * 5.0, 0.0, 1.0));
	}
	// sun and its glow
	float sd = max(dot(d, normalize(sun_dir)), 0.0);
	col += sun_col * (pow(sd, 6.0) * 0.22 + pow(sd, 48.0) * 0.45) * sun_vis;
	col = mix(col, sun_col * 2.6, smoothstep(0.99935, 0.9997, sd) * sun_vis);
	if (AT_CUBEMAP_PASS) {
		COLOR = col;
	} else {
		// stars
		if (night > 0.01 && h > 0.0) {
			vec3 cell = floor(d * 260.0);
			float s = hash3(cell);
			if (s > 0.9972) {
				float tw = 0.6 + 0.4 * sin(TIME * (2.0 + s * 9.0) + s * 40.0);
				col += vec3(0.9, 0.92, 1.0) * tw * night * smoothstep(0.0, 0.25, h) * (1.0 - cover * 0.85);
			}
		}
		// the moon, in phase
		vec3 md = normalize(moon_dir);
		float mdot = dot(d, md);
		if (moon_vis > 0.0 && mdot > 0.9985) {
			vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), md));
			vec3 up = cross(md, right);
			float rad = sqrt(1.0 - 0.9988 * 0.9988);
			vec2 uv = vec2(dot(d, right), dot(d, up)) / rad;
			float r = length(uv);
			if (r < 1.0) {
				float w = sqrt(max(1.0 - uv.y * uv.y, 0.0));
				float k = cos(6.2831853 * moon_phase);
				bool lit = moon_phase < 0.5 ? (uv.x > w * k) : (uv.x < -w * k);
				float maria = vnoise(uv * 3.0 + 4.0) * 0.18;
				vec3 face = lit ? vec3(0.93, 0.92, 0.86) * (1.0 - maria) : col * 0.6 + vec3(0.02, 0.025, 0.04);
				col = mix(col, face, smoothstep(1.0, 0.92, r) * moon_vis);
			}
		}
		col += vec3(0.75, 0.8, 0.9) * pow(max(mdot, 0.0), 220.0) * 0.12 * moon_vis * night;
		// clouds, two layers
		if (h > -0.02) {
			vec2 cp = d.xz / (max(h, 0.0) + 0.14);
			float n1 = fbm(cp * 0.55 + wind * TIME);
			float n2 = fbm(cp * 1.3 - wind.yx * TIME * 1.6 + 7.0);
			float n = n1 * 0.72 + n2 * 0.28;
			float thresh = mix(0.78, 0.3, cover);
			float c = smoothstep(thresh, thresh + 0.18, n);
			float body = smoothstep(thresh, thresh + 0.4, n);
			vec3 lit_col = mix(vec3(1.0), sun_col, 0.25) * mix(0.18, 1.05, day);
			vec3 shade_col = lit_col * mix(0.72, 0.38, cloud_dark);
			vec3 ccol = mix(lit_col, shade_col, body);
			ccol = mix(ccol, vec3(0.32, 0.34, 0.38) * mix(0.25, 1.0, day), cloud_dark * 0.7);
			ccol += sun_col * pow(sd, 10.0) * 0.35 * day * (1.0 - body);  // bright rims toward the sun
			c *= smoothstep(-0.02, 0.18, h);
			col = mix(col, ccol, c * 0.96);
		}
		col += vec3(0.75, 0.8, 1.0) * flash;
		COLOR = col;
	}
}
