shader_type spatial;
render_mode cull_disabled;

uniform vec3 bend = vec3(0.0);

void vertex() {
	VERTEX += bend * sin(PI * (VERTEX.y + 0.5));
}

void fragment() {
	ALBEDO = vec3(0.024, 0.038, 0.045);
	ROUGHNESS = 0.65;
}
