shader_type spatial;
render_mode cull_disabled;
uniform sampler2D palette : source_color, filter_linear_mipmap, repeat_disable;
uniform float wind_time = 0.0;
varying vec3 world_point;
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.x += sin(world_point.x * 0.7 + world_point.z * 0.9 + wind_time * 0.75) * smoothstep(0.15, 2.8, VERTEX.y) * 0.035;
}
void fragment() { ALBEDO = texture(palette, UV).rgb * COLOR.rgb; ROUGHNESS = 0.9; }
