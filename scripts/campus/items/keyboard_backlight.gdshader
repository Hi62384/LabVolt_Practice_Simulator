shader_type spatial;

uniform bool enabled = true;
uniform int color_count = 1;
uniform vec4 colors[8] : source_color;

void fragment() {
	float phase = mod(TIME / 2.4, float(color_count));
	int current = int(floor(phase));
	int next = (current + 1) % color_count;
	vec3 glow = mix(colors[current].rgb, colors[next].rgb, smoothstep(0.65, 1.0, fract(phase)));
	ALBEDO = enabled ? mix(vec3(0.25, 0.31, 0.31), glow, 0.30) : vec3(0.39, 0.46, 0.46);
	ROUGHNESS = 0.72;
	EMISSION = enabled ? glow * 0.5 : vec3(0.0);
}
