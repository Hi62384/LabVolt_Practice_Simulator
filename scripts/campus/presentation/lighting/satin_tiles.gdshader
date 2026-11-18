shader_type spatial;
render_mode cull_back;

uniform vec4 tile_color : source_color = vec4(1.0);
uniform bool use_tile_vertex_color = false;
uniform bool satin_reflections = true;
uniform bool area_reflections = false;
uniform int lighting_profile = 0;
uniform float fixture_intensity = 1.0;
uniform vec4 reflection_tint : source_color = vec4(1.0, 0.72, 0.45, 1.0);
varying vec3 world_point;
uniform float diffuse_response : hint_range(0.0, 1.0) = 0.63;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 mirror_on_ceiling(float height, vec3 camera_world) {
	vec2 sight = world_point.xz - camera_world.xz;
	return world_point.xz + sight * (height - world_point.y) /
		max(camera_world.y - world_point.y, 0.28);
}

float area_pool(vec2 projected, vec2 fixture, vec2 spread) {
	vec2 offset = (projected - fixture) / spread;
	return exp2(-2.8 * dot(offset, offset));
}

float fixture_mirrors(vec3 camera_world) {
	if (lighting_profile == 1) {
		float floor_base = world_point.y > 4.0 ? 5.0 : 0.0;
		float first = floor_base > 0.0 ? -2.0 : -10.0;
		float last = floor_base > 0.0 ? 63.0 : 45.0;
		vec2 reflected = mirror_on_ceiling(floor_base + 3.89, camera_world);
		float z = clamp(round((reflected.y - first) / 5.0) * 5.0 + first, first, last);
		return area_pool(reflected, vec2(13.0, z), vec2(0.71, 2.12));
	}
	if (lighting_profile == 2) {
		vec2 reflected = mirror_on_ceiling(3.04, camera_world);
		float z = reflected.y < 19.0 ? 15.7 : 22.3;
		float x = reflected.x < 22.8 ? 20.8 : reflected.x < 26.9 ? 24.8 :
			reflected.x < 31.0 ? 29.0 : 33.0;
		float pendants = area_pool(reflected, vec2(x, z), vec2(1.32, 1.02));
		vec2 panel = mirror_on_ceiling(3.89, camera_world);
		float panel_x = clamp(round((panel.x - 26.0) / 5.0), -1.0, 1.0) * 5.0 + 26.0;
		return pendants * 0.80 + area_pool(panel, vec2(panel_x, panel.y < 19.0 ? 16.0 : 22.0), vec2(1.55, 1.23)) * 0.40;
	}
	if (lighting_profile == 3) {
		vec2 panel = mirror_on_ceiling(3.88, camera_world);
		float x = clamp(round((panel.x - 26.0) / 6.0), -1.0, 1.0) * 6.0 + 26.0;
		return area_pool(panel, vec2(x, panel.y < 33.0 ? 30.0 : 36.0), vec2(1.46, 1.05));
	}
	return 0.0;
}

void fragment() {
	ALBEDO = tile_color.rgb * 0.84 * (use_tile_vertex_color ? COLOR.rgb : vec3(1.0));
	ROUGHNESS = area_reflections && satin_reflections ? 0.26 : 0.76;
	SPECULAR = satin_reflections ? 0.5 : 0.0;
	if (area_reflections && lighting_profile != 0) {
		// Low-frequency porcelain grain stays stable as the camera moves.
		vec2 p = world_point.xz;
		float grain = sin(dot(p, vec2(113.0, 89.0))) * sin(dot(p, vec2(49.0, -133.0)));
		grain *= 1.0 - smoothstep(0.004, 0.019, max(length(dFdx(p)), length(dFdy(p))));
		vec2 tile = fract(p);
		float seam = min(min(tile.x, 1.0 - tile.x), min(tile.y, 1.0 - tile.y));
		float edge = smoothstep(0.008, 0.058, seam);
		float boundary = 1.0;
		if (lighting_profile == 1) boundary = smoothstep(0.05, 0.62, min(p.x - 10.0, 16.0 - p.x));
		if (lighting_profile == 2) boundary = smoothstep(0.04, 0.8, min(min(p.x - 16.0, 36.0 - p.x), min(p.y - 13.0, 25.0 - p.y)));
		ALBEDO *= (0.91 + edge * 0.09 + grain * 0.025) * mix(0.73, 1.0, boundary);
		if (satin_reflections) {
			float reach = 1.0 - smoothstep(17.0, 31.0, distance(CAMERA_POSITION_WORLD, world_point));
			float pool = fixture_mirrors(CAMERA_POSITION_WORLD);
			EMISSION = reflection_tint.rgb * (pool * reach * edge * (1.0 + grain * 0.12) * fixture_intensity * 0.48);
		}
	}
}

void light() {
	float facing = max(0.0, dot(NORMAL, LIGHT));
	DIFFUSE_LIGHT += LIGHT_COLOR * (ATTENUATION * facing * diffuse_response / PI);
	if (satin_reflections && !LIGHT_IS_DIRECTIONAL) {
		vec3 half_vector = normalize(LIGHT + VIEW);
		float sheen = pow(max(0.0, dot(NORMAL, half_vector)), 30.0);
		SPECULAR_LIGHT += LIGHT_COLOR * (ATTENUATION * facing * sheen * SPECULAR_AMOUNT * 0.48);
	}
}
