shader_type sky;

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

float smooth_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	vec2 blend = fraction * fraction * (3.0 - 2.0 * fraction);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

float cloud_facet(vec2 point) {
	point.x += 0.20 * sin(point.y * 1.7);
	point.y += 0.17 * sin(point.x * 1.3);
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	float upper = step(1.0, fraction.x + fraction.y);
	vec2 face_center = cell + mix(vec2(0.333), vec2(0.667), upper);
	return 0.65 * smooth_noise(face_center * 0.75 + vec2(4.1, 8.3)) + 0.35 * hash21(face_center + vec2(9.7, 2.3));
}

float cloud_puff(vec2 point) {
	vec2 cell = floor(point);
	float nearest = 2.0;
	for (int row = -1; row <= 1; row++) {
		for (int column = -1; column <= 1; column++) {
			vec2 neighbor = cell + vec2(float(column), float(row));
			vec2 offset = vec2(hash21(neighbor), hash21(neighbor + vec2(21.7, 6.2)));
			vec2 center = neighbor + 0.20 + 0.60 * offset;
			nearest = min(nearest, length(point - center));
		}
	}
	return 1.0 - smoothstep(0.12, 0.82, nearest);
}

float cloud_lobe(vec2 point, vec2 center, vec2 radius) {
	vec2 local = abs((point - center) / radius);
	return 1.0 - smoothstep(0.96, 1.04, max(local.y, local.x * 0.87 + local.y * 0.50));
}

float small_cloud(vec2 point, vec2 center, vec2 size) {
	float middle = cloud_lobe(point, center, size);
	float left = cloud_lobe(point, center + vec2(-size.x * 0.62, -size.y * 0.13), size * vec2(0.65, 0.66));
	float right = cloud_lobe(point, center + vec2(size.x * 0.60, -size.y * 0.18), size * vec2(0.70, 0.62));
	return max(middle, max(left, right));
}

void sky() {
	float altitude = max(EYEDIR.y, 0.0);
	float azimuth = atan(EYEDIR.x, -EYEDIR.z);
	vec2 point = vec2(azimuth, altitude);
	float sun_x = azimuth - 0.18;
	float glow = exp(-sun_x * sun_x * 6.5 - (altitude - 0.085) * (altitude - 0.085) * 24.0);
	float warm = exp(-sun_x * sun_x * 5.0 - (altitude - 0.12) * (altitude - 0.12) * 10.0);
	vec3 horizon = vec3(0.24, 0.075, 0.052);
	vec3 upper = vec3(0.035, 0.006, 0.020);
	vec3 color = mix(horizon, upper, smoothstep(0.0, 0.52, altitude));
	color += vec3(0.64, 0.28, 0.075) * glow;
	float sun_distance = length(vec2(sun_x, altitude - 0.035));
	float sun_halo = exp(-sun_distance * sun_distance * 85.0);
	float sun_disc = 1.0 - smoothstep(0.009, 0.015, sun_distance);
	color += vec3(0.45, 0.27, 0.09) * sun_halo;
	color += vec3(1.5, 1.0, 0.48) * sun_disc;

	float billows = smooth_noise(vec2(azimuth * 5.0 + 3.4, altitude * 9.0 + 1.8));
	float fine_billows = smooth_noise(vec2(azimuth * 11.0 - 2.0, altitude * 19.0 + 4.6));
	float cloud_edge = 0.16 + 0.035 * sin(azimuth * 5.5 + 0.6) + 0.09 * (billows - 0.5);
	cloud_edge += 0.025 * (fine_billows - 0.5);
	float canopy = smoothstep(-0.008, 0.018, altitude - cloud_edge);
	float bank_left = small_cloud(point, vec2(-0.77, 0.13), vec2(0.15, 0.05));
	float bank_right = small_cloud(point, vec2(0.82, 0.15), vec2(0.16, 0.045));
	canopy = max(canopy, max(bank_left, bank_right));
	float facet = cloud_facet(vec2(azimuth * 13.0 + altitude * 3.0, altitude * 22.0));
	float second_facet = cloud_facet(vec2(azimuth * 22.0 - altitude * 4.0 + 2.0, altitude * 32.0 + 4.0));
	vec2 puff_space = vec2(azimuth * 7.0 + altitude * 2.0, altitude * 13.0);
	float puff = cloud_puff(puff_space);
	float face_light = (0.48 + 0.85 * facet + 0.27 * second_facet) * (0.72 + 0.46 * puff);
	vec3 dark_cloud = vec3(0.085, 0.010, 0.025);
	vec3 lit_cloud = vec3(0.43, 0.105, 0.045);
	vec3 cloud_color = mix(dark_cloud, lit_cloud, warm * (0.65 + 0.35 * billows)) * face_light;
	float lower_rim = exp(-max(altitude - cloud_edge, 0.0) * 22.0) * canopy * warm;
	cloud_color += vec3(0.20, 0.075, 0.025) * lower_rim;
	color = mix(color, cloud_color, canopy * 0.96);

	float left_ribbon_height = 0.15 - 0.27 * (azimuth + 0.08);
	float right_ribbon_height = 0.14 + 0.27 * (azimuth - 0.22);
	float left_ribbon = exp(-pow((altitude - left_ribbon_height) * 24.0, 2.0)) * (1.0 - smoothstep(-0.12, 0.07, azimuth));
	float right_ribbon = exp(-pow((altitude - right_ribbon_height) * 25.0, 2.0)) * smoothstep(0.22, 0.43, azimuth);
	float ribbons = max(left_ribbon, right_ribbon) * canopy;
	vec3 ribbon_color = mix(vec3(0.30, 0.045, 0.060), vec3(0.52, 0.15, 0.075), warm) * face_light;
	color = mix(color, ribbon_color, ribbons * 0.72);

	float fragments = smoothstep(0.57, 0.72, billows * 0.72 + fine_billows * 0.28);
	fragments *= smoothstep(0.045, 0.075, altitude) * (1.0 - smoothstep(0.16, 0.23, altitude));
	vec3 fragment_color = mix(vec3(0.16, 0.025, 0.035), vec3(0.68, 0.30, 0.085), warm) * face_light;
	color = mix(color, fragment_color, fragments * 0.85);

	float inner_clouds = small_cloud(point, vec2(-0.05, 0.17), vec2(0.067, 0.025));
	inner_clouds = max(inner_clouds, small_cloud(point, vec2(0.08, 0.125), vec2(0.065, 0.018)));
	inner_clouds = max(inner_clouds, small_cloud(point, vec2(0.19, 0.19), vec2(0.075, 0.023)));
	inner_clouds = max(inner_clouds, small_cloud(point, vec2(0.30, 0.125), vec2(0.072, 0.018)));
	inner_clouds = max(inner_clouds, small_cloud(point, vec2(0.38, 0.205), vec2(0.075, 0.025)));
	inner_clouds = max(inner_clouds, small_cloud(point, vec2(0.49, 0.15), vec2(0.055, 0.018)));
	float inner_facet = cloud_facet(vec2(azimuth * 31.0 - 1.0, altitude * 51.0 + 8.0));
	vec3 inner_color = mix(vec3(0.35, 0.07, 0.045), vec3(0.73, 0.33, 0.11), warm);
	inner_color *= 0.70 + 0.60 * inner_facet;
	color = mix(color, inner_color, inner_clouds * 0.80);

	float left_cloud = small_cloud(point, vec2(-0.38, 0.105), vec2(0.105, 0.037));
	float high_cloud = small_cloud(point, vec2(0.26, 0.30), vec2(0.085, 0.027));
	float right_cloud = small_cloud(point, vec2(0.71, 0.105), vec2(0.055, 0.022));
	float little_clouds = max(left_cloud, max(high_cloud, right_cloud));
	float small_facet = cloud_facet(vec2(azimuth * 32.0 + 4.0, altitude * 55.0 + 1.0));
	vec3 small_color = mix(vec3(0.31, 0.135, 0.075), vec3(0.71, 0.36, 0.15), warm);
	color = mix(color, small_color * (0.8 + 0.4 * small_facet), little_clouds * 0.95);
	COLOR = color;
}
