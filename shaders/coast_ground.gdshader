shader_type spatial;
render_mode cull_disabled;
uniform vec4 grass_color : source_color = vec4(0.43, 0.56, 0.39, 1.0);
uniform vec4 sand_color : source_color = vec4(0.76, 0.71, 0.56, 1.0);
uniform vec4 wet_color : source_color = vec4(0.43, 0.49, 0.42, 1.0);
varying vec3 world_point;
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float soft_noise(vec2 p) {
	vec2 a = floor(p); vec2 b = fract(p); b = b * b * (3.0 - 2.0 * b);
	return mix(mix(hash21(a), hash21(a + vec2(1.0, 0.0)), b.x), mix(hash21(a + vec2(0.0, 1.0)), hash21(a + 1.0), b.x), b.y);
}
void vertex() { world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float width = 1.65 + 0.55 * sin(world_point.z * 0.18) + 0.25 * sin(world_point.z * 0.43 + 0.8);
	float sand = smoothstep(-width - 0.24, -width + 0.10, world_point.x);
	float wet = smoothstep(-width * 0.25, 0.0, world_point.x);
	float mottling = 0.94 + soft_noise(world_point.xz * 0.32) * 0.10 + soft_noise(world_point.xz * 1.2) * 0.025;
	ALBEDO = mix(mix(grass_color.rgb, sand_color.rgb, sand), wet_color.rgb, wet * 0.65) * mottling;
	ROUGHNESS = mix(0.96, 0.52, wet);
}
