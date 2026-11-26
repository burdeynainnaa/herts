shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 deep_water : source_color = vec4(0.12, 0.24, 0.27, 1.0);
uniform vec4 surface_water : source_color = vec4(0.22, 0.38, 0.4, 1.0);
uniform float flow_speed : hint_range(0.0, 2.0) = 0.45;
uniform float ripple_strength : hint_range(0.0, 2.0) = 1.0;

varying vec3 world_position;

float random_value(vec2 point) {
	vec3 value = fract(vec3(point.xyx) * 0.1031);
	value += dot(value, value.yzx + 33.33);
	return fract((value.x + value.y) * value.z);
}

vec3 smooth_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	vec2 blend = fraction * fraction * (3.0 - 2.0 * fraction);
	vec2 blend_gradient = 6.0 * fraction * (1.0 - fraction);
	float lower_left = random_value(cell);
	float lower_right = random_value(cell + vec2(1.0, 0.0));
	float upper_left = random_value(cell + vec2(0.0, 1.0));
	float upper_right = random_value(cell + vec2(1.0, 1.0));
	float lower = mix(lower_left, lower_right, blend.x);
	float upper = mix(upper_left, upper_right, blend.x);
	return vec3(
		mix(lower, upper, blend.y),
		mix(lower_right - lower_left, upper_right - upper_left, blend.y) * blend_gradient.x,
		(upper - lower) * blend_gradient.y
	);
}

vec3 water_field(vec2 position, float time) {
	vec2 flow = vec2(position.x * 0.42, position.y * 1.1 - time);
	vec3 distortion = smooth_noise(flow * 0.35 + vec2(4.0, 9.0));
	vec2 distortion_direction = vec2(1.1, 1.4);
	vec2 warped = flow + (distortion.x - 0.5) * distortion_direction;
	vec3 broad = smooth_noise(warped);
	vec3 detail = smooth_noise(warped * 2.2 + vec2(8.0, 3.0));
	vec2 warped_gradient = 0.12 * broad.yz + 0.055 * detail.yz;
	vec2 gradient = warped_gradient + 0.35 * distortion.yz * dot(warped_gradient, distortion_direction);
	return vec3(0.12 * broad.x + 0.025 * detail.x, gradient * vec2(0.42, 1.1));
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float z = world_position.z;
	float bend = clamp((z + 100.0) / 115.0, 0.0, 1.0);
	float center = -51.0 + 40.0 * (1.0 - smoothstep(-100.0, 15.0, z)) + 8.0 * sin(z * 0.055);
	float center_slope = -40.0 * 6.0 * bend * (1.0 - bend) / 115.0 + 0.44 * cos(z * 0.055);
	vec2 river_position = vec2(world_position.x - center, z);
	float time = TIME * flow_speed;
	vec3 field = water_field(river_position, time);
	float height = field.x;
	vec2 gradient = field.yz;
	vec3 world_normal = normalize(vec3(-gradient.x * ripple_strength, 1.0, (-gradient.y + gradient.x * center_slope) * ripple_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	float variation = clamp((height - 0.025) * 6.0, 0.0, 1.0);
	ALBEDO = mix(deep_water.rgb, surface_water.rgb, variation);
	EMISSION = ALBEDO * 0.12;
	ROUGHNESS = 0.3;
	SPECULAR = 0.25;
}
