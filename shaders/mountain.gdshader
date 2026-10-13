shader_type spatial;
render_mode cull_disabled;

void vertex() {
	// Cut the top down as excavation advances; zero-stock mountains are hidden by the world.
	VERTEX.y = min(VERTEX.y, INSTANCE_CUSTOM.r);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.95;
}
