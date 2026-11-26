shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D flag_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float wave_speed : hint_range(0.0, 4.0) = 1.35;
uniform float wave_strength : hint_range(0.0, 0.25) = 0.055;
uniform float ripple_strength : hint_range(0.0, 0.25) = 0.018;
uniform float fly_droop : hint_range(0.0, 0.4) = 0.06;
uniform float backlight_amount : hint_range(0.0, 1.0) = 0.3;

// The hoist (u = 0) stays pinned to the staff; the wave grows toward the fly end.
float wave_slope(float u, float phase) {
	float broad = cos(u * 6.0 - phase) * 6.0;
	float fine = cos(u * 15.0 - phase * 1.9 + 1.3) * 15.0 * 0.32;
	return broad + fine;
}

void vertex() {
	float u = UV.x;
	float grip = smoothstep(0.0, 1.0, u);
	float phase = TIME * wave_speed + MODEL_MATRIX[3].x * 0.35;
	float broad = sin(u * 6.0 - phase) * wave_strength;
	float fine = sin(u * 15.0 - phase * 1.9 + 1.3) * ripple_strength;
	VERTEX.z += (broad + fine) * grip * grip;
	VERTEX.y -= fly_droop * grip * grip;
	float slope = wave_slope(u, phase) * (wave_strength * 0.55 + ripple_strength * 0.45) * grip;
	NORMAL = normalize(vec3(-slope, 0.0, 1.0));
}

void fragment() {
	vec4 cloth = texture(flag_texture, UV);
	ALBEDO = cloth.rgb;
	ALPHA = cloth.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ROUGHNESS = 0.94;
	SPECULAR = 0.1;
	BACKLIGHT = cloth.rgb * backlight_amount;
}
