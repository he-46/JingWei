shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 shallow_color : source_color = vec4(0.20, 0.46, 0.43, 1.0);
uniform vec4 far_color : source_color = vec4(0.12, 0.32, 0.38, 1.0);
uniform vec4 deep_color : source_color = vec4(0.07, 0.18, 0.26, 1.0);
uniform float shallow_end = 12.0;
uniform float far_end = 24.0;
uniform float sea_end = 28.0;
uniform float wave_time = 0.0;
varying vec3 world_point;
void vertex() { world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float variation = sin(world_point.z * 0.10) * 0.45;
	float first = smoothstep(shallow_end * 0.65, shallow_end * 1.3, world_point.x + variation);
	float second = smoothstep(far_end * 0.85, mix(far_end, sea_end, 0.55), world_point.x + variation);
	vec3 water = mix(mix(shallow_color.rgb, far_color.rgb, first), deep_color.rgb, second);
	float swell = sin(world_point.x * 0.70 + world_point.z * 0.35 + wave_time * 0.65);
	float fine = sin(world_point.z * 1.5 - world_point.x * 0.48 + wave_time * 0.43 + sin(world_point.x * 0.13) * 0.4);
	float glint = smoothstep(0.88, 1.0, swell) * smoothstep(0.55, 0.92, fine);
	float detail = 1.0 - smoothstep(0.4, 1.3, length(fwidth(world_point.xz)));
	ALBEDO = water * (0.99 + 0.015 * swell * detail) + vec3(0.010, 0.014, 0.013) * glint * detail;
}
