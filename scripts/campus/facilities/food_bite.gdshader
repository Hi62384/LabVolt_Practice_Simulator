shader_type spatial;
render_mode cull_disabled;

uniform vec4 tint : source_color;
uniform mat4 part_transform;
uniform float bite_edge;
uniform float half_depth;
varying vec3 food_position;

void vertex() {
	food_position = (part_transform * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float scallop = min(abs(food_position.z) / half_depth, 1.0);
	if (food_position.x > bite_edge + 0.03 * scallop * scallop) {
		discard;
	}
	ALBEDO = tint.rgb * (FRONT_FACING ? 1.0 : 0.82);
	ROUGHNESS = 0.78;
}
