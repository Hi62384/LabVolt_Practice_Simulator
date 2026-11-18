shader_type spatial;

uniform vec4 ceramic : source_color = vec4(0.77, 0.73, 0.65, 1.0);
uniform vec4 grout : source_color = vec4(0.60, 0.58, 0.53, 1.0);

void fragment() {
	vec2 tiles = UV * vec2(20.0, 12.0);
	vec2 tile_id = floor(tiles);
	vec2 edge = min(fract(tiles), 1.0 - fract(tiles));
	float seam = min(edge.x, edge.y);
	float aa = max(fwidth(seam), 0.001);
	float tile = smoothstep(0.006 - aa, 0.006 + aa, seam);
	float variation = fract(sin(dot(tile_id, vec2(37.3, 57.1))) * 4831.7);
	ALBEDO = mix(grout.rgb, ceramic.rgb * mix(0.96, 1.04, variation), tile);
	ROUGHNESS = mix(0.84, 0.45, tile);
	SPECULAR = 0.34;
}
