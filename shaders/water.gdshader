shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 shallow_color : source_color = vec4(0.12, 0.38, 0.36, 1.0);
uniform vec4 deep_color : source_color = vec4(0.05, 0.20, 0.26, 1.0);
uniform float shallow_end = 12.0;
uniform float far_end = 24.0;
uniform float sea_end = 28.0;
varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world_point.x * 0.65 + TIME * 0.8) * cos(world_point.z * 0.7 + TIME * 0.5) * 0.045;
}

void fragment() {
	float depth_mix = smoothstep(shallow_end * 0.6, far_end, world_point.x);
	vec3 color = mix(shallow_color.rgb, deep_color.rgb, depth_mix);
	color = mix(color, vec3(0.025, 0.095, 0.16), smoothstep(far_end, sea_end, world_point.x));
	float waves = sin(world_point.x * 2.3 + world_point.z * 1.1 + TIME * 0.85);
	float breaks = sin(world_point.z * 3.5 - world_point.x * 0.7 + TIME * 0.3);
	float foam = smoothstep(0.96, 1.0, waves) * smoothstep(0.2, 0.85, breaks);
	color += foam * 0.12;
	float shore = 1.0 - smoothstep(0.0, 0.5, abs(world_point.x - 0.18 + sin(world_point.z * 2.0) * 0.08));
	color = mix(color, vec3(0.76, 0.87, 0.77), shore * 0.65);
	ALBEDO = color;
}
