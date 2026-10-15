shader_type spatial;
render_mode cull_disabled;
uniform sampler2D rock_paint : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 dry_stone : source_color = vec4(0.64, 0.65, 0.55, 1.0);
uniform vec4 wet_stone : source_color = vec4(0.30, 0.40, 0.38, 1.0);
varying vec3 world_point;
vec2 stone_hash(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}
void vertex() { world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = world_point.xz * 1.3;
	vec2 cell = floor(p), local = fract(p);
	float detail = 1.0 - smoothstep(0.12, 0.6, length(fwidth(p)));
	float nearest = 9.0, second = 9.0, tint = 0.5;
	if (detail > 0.01) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 offset = vec2(float(x), float(y));
				vec2 seed = stone_hash(cell + offset);
				vec2 center = offset + 0.18 + seed * 0.64 - local;
				float distance2 = dot(center, center);
				if (distance2 < nearest) { second = nearest; nearest = distance2; tint = seed.x; }
				else { second = min(second, distance2); }
			}
		}
	}
	float bevel = smoothstep(0.01, 0.09, second - nearest);
	float dry = smoothstep(0.16, 0.40, world_point.y);
	vec3 paint = texture(rock_paint, world_point.xz * 0.16).rgb;
	ALBEDO = mix(wet_stone.rgb, dry_stone.rgb, dry) * (0.78 + paint * 0.36) * mix(1.0, mix(0.90, 1.0, bevel) * (0.96 + tint * 0.08), detail);
	ROUGHNESS = mix(0.45, 0.93, dry);
}
