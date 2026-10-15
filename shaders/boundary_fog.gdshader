shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 map_bounds;
uniform float opacity = 1.0;
uniform float edge_width = 2.0;
uniform float drift = 0.0;
uniform float fog_time = 0.0;
uniform vec4 fog_low : source_color = vec4(0.64, 0.74, 0.72, 1.0);
uniform vec4 fog_high : source_color = vec4(0.81, 0.86, 0.81, 1.0);
varying vec2 world_point;

float noise_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float cloud_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(noise_hash(cell), noise_hash(cell + vec2(1.0, 0.0)), f.x),
		mix(noise_hash(cell + vec2(0.0, 1.0)), noise_hash(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// The game uses an orthographic camera. Evaluate the boundary at the low
	// coastal reference plane along its view ray, not at the elevated fog sheet.
	// Otherwise the upper sheets project several reachable units into the map.
	vec3 forward = -INV_VIEW_MATRIX[2].xyz;
	float drop = (0.2 - world_position.y) / min(forward.y, -0.0001);
	world_point = world_position.xz + forward.xz * drop;
}

void fragment() {
	float edge = max(max(map_bounds.x - world_point.x, world_point.x - map_bounds.z),
		max(map_bounds.y - world_point.y, world_point.y - map_bounds.w));
	vec2 p = world_point * 0.14 + vec2(fog_time * 0.025 + drift, fog_time * 0.015);
	float clouds = cloud_noise(p) * 0.65 + cloud_noise(p * 2.7) * 0.35;
	float distortion = smoothstep(0.0, edge_width, edge) * (clouds - 0.5) * edge_width * 0.3;
	float veil = smoothstep(-0.12, edge_width * 0.80, edge + distortion);
	ALBEDO = mix(fog_low.rgb, fog_high.rgb, clouds);
	ALPHA = veil * opacity;
}
