shader_type spatial;
uniform sampler2D rock_paint : source_color, filter_linear_mipmap, repeat_enable;

void fragment() {
	vec2 point = UV - 0.5;
	float radius = length(point);
	float angle = atan(point.y, point.x);
	// Shallow radial fractures and a few raked tool marks, not harvestable loose stones.
	float fractures = (1.0 - smoothstep(0.010, 0.022, abs(sin(angle * 3.0 + radius * 2.0)))) * smoothstep(0.09, 0.25, radius);
	float rake = (1.0 - smoothstep(0.016, 0.034, abs(sin((point.x + point.y * 0.28) * 37.0)))) * 0.15;
	ALBEDO = (texture(rock_paint, UV).rgb * 0.42 + vec3(0.24, 0.22, 0.14)) * (1.0 - fractures * 0.30 - rake);
	ROUGHNESS = 1.0;
}
