shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 shallow_color : source_color = vec4(0.20, 0.46, 0.43, 1.0);
uniform vec4 far_color : source_color = vec4(0.12, 0.32, 0.38, 1.0);
uniform vec4 deep_color : source_color = vec4(0.07, 0.18, 0.26, 1.0);
uniform float shallow_end = 12.0;
uniform float far_end = 24.0;
uniform float sea_end = 28.0;
uniform float wave_time = 0.0;
uniform sampler2D shore_atlas : filter_linear, repeat_disable;
uniform vec2 atlas_origin;
uniform vec2 atlas_size = vec2(49.0);
uniform float map_side = 48.0;
uniform vec4 distant_fog : source_color = vec4(0.663, 0.745, 0.718, 1.0);
uniform vec4 ripple_events[8];
// Values are supplied by ocean_parameters.gd for both rendering and CPU aiming.
uniform vec4 wave_components[3];
uniform vec3 wave_speeds;
uniform float horizontal_scale;
uniform float shore_range;
uniform vec2 shore_fade;
uniform vec2 outer_fade;
uniform vec4 ripple_shape;
uniform vec2 ripple_limits;
varying vec3 world_point;
varying vec2 rest_point;
varying vec3 wave_normal;

float shore_distance(vec2 p) {
    vec2 pixel = p - atlas_origin;
    if (any(lessThan(pixel, vec2(0.0))) || any(greaterThan(pixel, atlas_size - vec2(1.0)))) {
        return clamp(p.x, -shore_range, shore_range);
    }
    return texture(shore_atlas, (pixel + vec2(0.5)) / atlas_size).r;
}
vec3 one_wave(vec2 p, vec2 direction, float amplitude, float k, float speed) {
    float phase = k * dot(direction, p) - speed * wave_time;
    return vec3(direction.x * horizontal_scale * amplitude * cos(phase), amplitude * sin(phase), direction.y * horizontal_scale * amplitude * cos(phase));
}
float impact_wave(vec2 p) {
    float value = 0.0;
    for (int i = 0; i < 8; i++) {
        float age = wave_time - ripple_events[i].z;
        if (age >= 0.0 && age <= ripple_limits.x) {
            float front = distance(p, ripple_events[i].xy) - age * ripple_shape.x;
            value += ripple_events[i].w * sin(front * ripple_shape.y) * exp(-front * front * ripple_shape.z) * exp(-age * ripple_shape.w);
        }
    }
    return clamp(value, -ripple_limits.y, ripple_limits.y);
}
vec3 displacement(vec2 p) {
    vec3 offset = vec3(0.0);
    for (int i = 0; i < 3; i++) {
        offset += one_wave(p, wave_components[i].xy, wave_components[i].z, wave_components[i].w, wave_speeds[i]);
    }
    offset.y += impact_wave(p);
    float outer = max(abs(p.x - atlas_origin.x - map_side * 0.5), abs(p.y - atlas_origin.y - map_side * 0.5)) - map_side * 0.5;
    return offset * smoothstep(shore_fade.x, shore_fade.y, shore_distance(p)) * (1.0 - smoothstep(outer_fade.x, outer_fade.y, outer));
}
void vertex() {
    rest_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
    vec3 offset = displacement(rest_point);
    vec3 dx = vec3(0.06, 0.0, 0.0) + displacement(rest_point + vec2(0.06, 0.0)) - offset;
    vec3 dz = vec3(0.0, 0.0, 0.06) + displacement(rest_point + vec2(0.0, 0.06)) - offset;
    wave_normal = normalize(cross(dz, dx));
    VERTEX += offset;
    world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    float variation = sin(rest_point.y * 0.10) * 0.45;
    float first = smoothstep(shallow_end * 0.65, shallow_end * 1.3, rest_point.x + variation);
    float second = smoothstep(far_end * 0.85, mix(far_end, sea_end, 0.55), rest_point.x + variation);
    vec3 water = mix(mix(shallow_color.rgb, far_color.rgb, first), deep_color.rgb, second);
    float detail = 1.0 - smoothstep(0.4, 1.3, length(fwidth(rest_point)));
    float d = shore_distance(rest_point);
    float phase = d * 2.24 + wave_time * 1.75;
    float breakup = 0.45 + 0.30 * sin(rest_point.x * 3.1 + rest_point.y * 4.3) * sin(rest_point.y * 2.3 - wave_time * 0.7);
    float band = smoothstep(0.78, 0.99, cos(phase + sin(rest_point.y * 1.4) * 0.10));
    float near_shore = smoothstep(0.02, 0.20, d) * (1.0 - smoothstep(3.0, 6.0, d));
    float foam = band * near_shore * breakup * 0.48 * detail;
    float ripples = abs(impact_wave(rest_point)) * 3.2 * smoothstep(shore_fade.x, shore_fade.y, d) * detail;
    vec3 normal = normalize(wave_normal);
    float light = 0.76 + 0.24 * normal.y + (-normal.x * 0.7 + normal.z * 0.35) * detail;
    float fine = sin(rest_point.y * 2.1 - rest_point.x * 0.6 + wave_time * 0.7);
    ALBEDO = mix(water * (light + fine * 0.008 * detail), vec3(0.78, 0.88, 0.81), clamp(foam + ripples, 0.0, 0.65));
    float outer = max(abs(rest_point.x - atlas_origin.x - map_side * 0.5), abs(rest_point.y - atlas_origin.y - map_side * 0.5)) - map_side * 0.5;
    ALBEDO = mix(ALBEDO, distant_fog.rgb, smoothstep(0.0, 24.0, outer));
}
