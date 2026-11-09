shader_type spatial;
render_mode cull_back;
uniform vec4 identity_tint : source_color = vec4(1.0);
void vertex() {
	if (abs(UV2.x) > 0.5) {
		float phase = TIME * 5.0 + MODEL_MATRIX[3].x * 0.2;
		float side = sign(UV2.x) * (abs(UV2.x) > 1.5 ? -1.0 : 1.0);
		float angle = sin(phase) * 0.32 * side;
		float c = cos(angle);
		float s = sin(angle);
		mat3 turn = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
		vec3 pivot = vec3(UV.x, UV.y, UV2.y);
		VERTEX = pivot + turn * (VERTEX - pivot);
		NORMAL = turn * NORMAL;
	}
}
void fragment() {
	ALBEDO = COLOR.rgb * identity_tint.rgb;
	ROUGHNESS = 0.85;
}
