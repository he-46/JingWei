shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float wave_time = 0.0;
uniform vec4 foam_color : source_color = vec4(0.78, 0.88, 0.81, 1.0);
varying vec2 world_point;
void vertex() { world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz; }
void fragment() {
	float edge = 1.0 - smoothstep(0.12, 0.50, abs(UV.y - 0.5));
	float breaks = 0.50 + 0.28 * sin(world_point.x * 2.7 + world_point.y * 3.1 + wave_time * 0.8);
	ALBEDO = foam_color.rgb;
	ALPHA = edge * breaks * 0.52;
}
