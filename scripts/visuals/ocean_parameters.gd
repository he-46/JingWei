extends RefCounted
## One source for CPU height queries and GPU uniforms. Array capacities are fixed.
const WAVES := [Vector4(-.9805807, .1961161, .16, .70), Vector4(-.7071068, -.7071068, .07, 1.15), Vector4(-.8574929, .5144958, .035, 1.90)]
const SPEEDS := Vector3(1.05, 1.38, 1.85)
const HORIZONTAL_SCALE := .55
const SHORE_RANGE := 8.0
const SHORE_FADE := Vector2(.35, 3.0)
const OUTER_FADE := Vector2(12, 32)
const RIPPLE_COUNT := 8
const RIPPLE_AMPLITUDE := .07
const RIPPLE_SHAPE := Vector4(2.8, 5.0, 1.5, .7) # Speed, frequency, width falloff, age falloff.
const RIPPLE_LIMITS := Vector2(4.5, .10) # Lifetime, maximum combined displacement.

static func displacement_bound() -> float:
	var height := RIPPLE_LIMITS.y
	for wave: Vector4 in WAVES:
		height += absf(wave.z)
	return height

static func apply_to(material: ShaderMaterial) -> void:
	assert(WAVES.size() == 3 and RIPPLE_COUNT == 8, "Changing wave/event capacity also requires updating the shader array declarations.")
	material.set_shader_parameter("wave_components", PackedVector4Array(WAVES))
	material.set_shader_parameter("wave_speeds", SPEEDS)
	material.set_shader_parameter("horizontal_scale", HORIZONTAL_SCALE)
	material.set_shader_parameter("shore_range", SHORE_RANGE)
	material.set_shader_parameter("shore_fade", SHORE_FADE)
	material.set_shader_parameter("outer_fade", OUTER_FADE)
	material.set_shader_parameter("ripple_shape", RIPPLE_SHAPE)
	material.set_shader_parameter("ripple_limits", RIPPLE_LIMITS)
