shader_type spatial;
render_mode cull_disabled;
uniform sampler2D palette : source_color, filter_linear_mipmap, repeat_disable;
uniform float wind_time = 0.0;
uniform vec3 detail_origin = vec3(0.0);
uniform float detail_distance = 0.0;
uniform float overview = 0.0;
varying vec3 world_point;
varying float detail_fade;
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float distance = length(world_point.xz - detail_origin.xz);
	float wind = (1.0 - smoothstep(35.0, 65.0, distance)) * (1.0 - overview);
	detail_fade = detail_distance > 0.0 ? 1.0 - smoothstep(detail_distance - 12.0, detail_distance, distance) : 1.0;
	VERTEX.y *= detail_fade;
	if (wind > .001) {
		VERTEX.x += sin(world_point.x * 0.7 + world_point.z * 0.9 + wind_time * 0.75) * smoothstep(0.15, 2.8, VERTEX.y) * 0.035 * wind;
	}
}
void fragment() { if (detail_fade < .01) { discard; } ALBEDO = texture(palette, UV).rgb * COLOR.rgb; ROUGHNESS = 0.9; }
