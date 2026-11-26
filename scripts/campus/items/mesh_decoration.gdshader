shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D visibility_depth : filter_nearest, repeat_disable;
uniform sampler2D pattern : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(1.);
uniform vec3 glow_color : source_color = vec3(1.);
uniform float roughness = .55;
uniform float metallic = 0.;
uniform float glow = 0.;
uniform bool projected = false;
uniform mat4 projector_from_mesh;
uniform mat3 normal_from_mesh;
uniform vec2 dimensions = vec2(1.);
uniform float thickness = .02;
uniform vec4 crop = vec4(0., 0., 1., 1.);
uniform float separation = .00004;
varying vec3 surface_point;
varying vec3 surface_normal;

void vertex() {
	if (projected) {
		surface_point = (projector_from_mesh * vec4(VERTEX, 1.)).xyz;
		surface_normal = normal_from_mesh * NORMAL;
	}
	// Offset the duplicate surface toward the camera without widening its silhouette.
	vec4 view_vertex = MODELVIEW_MATRIX * vec4(VERTEX, 1.);
	view_vertex.z += separation;
	POSITION = PROJECTION_MATRIX * view_vertex;
}

void fragment() {
	vec2 sample_uv = UV;
	if (projected) {
		sample_uv = surface_point.xy / dimensions * vec2(1., -1.) + .5;
		if (abs(surface_point.z) > thickness || normalize(surface_normal).z < -.03 ||
				any(lessThan(sample_uv, vec2(0.))) || any(greaterThan(sample_uv, vec2(1.)))) discard;
		float visible_z = texture(visibility_depth, sample_uv).r;
		float fragment_z = surface_point.z / (2. * thickness) + .5;
		float tolerance = min(.14, .025 + abs(dFdx(fragment_z)) + abs(dFdy(fragment_z)));
		if (fragment_z + tolerance < visible_z) discard;
		sample_uv = crop.xy + sample_uv * crop.zw;
	}
	vec4 pixel = texture(pattern, sample_uv) * tint;
	if (pixel.a < .008) discard;
	ALBEDO = pixel.rgb;
	ALPHA = pixel.a;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = pixel.rgb * glow_color * glow;
}
