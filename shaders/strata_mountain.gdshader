shader_type spatial;
render_mode cull_disabled;

uniform sampler2D rock_paint : source_color, filter_linear_mipmap, repeat_enable;
varying float cut_face;
varying vec2 cut_uv;

void vertex() {
	float ceiling = INSTANCE_CUSTOM.r;
	cut_face = step(ceiling + 0.00001, VERTEX.y);
	cut_uv = VERTEX.xz * 0.38 + 0.5;
	VERTEX.y = min(VERTEX.y, ceiling);
	// Collapsed nested rings form a closed, upward-facing quarry bench.
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), cut_face));
}

void fragment() {
	vec3 stone = texture(rock_paint, UV).rgb;
	vec3 bench = texture(rock_paint, cut_uv).rgb * 0.55 + vec3(0.40, 0.38, 0.29);
	ALBEDO = mix(stone, bench, cut_face) * COLOR.rgb;
	ROUGHNESS = 0.95;
}
