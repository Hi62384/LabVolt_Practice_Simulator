extends RefCounted

const MOTION := """
shader_type spatial;
render_mode unshaded;
uniform float resolution = 1.0;
uniform float fps = 60.0;
uniform float grain = 0.0;
uniform bool portrait = false;

float noise(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
	float t = floor(TIME * fps) / fps;
	vec2 pixels = (portrait ? vec2(144.0, 226.0) : vec2(256.0, 144.0)) * resolution;
	vec2 uv = (floor(UV * pixels) + 0.5) / pixels;
	uv.x += grain * .031 * sin(uv.y * 90.0 + t * 3.0);
	vec2 position = vec2(uv.x, uv.y * (portrait ? 1.38 : .65));
	vec2 center = vec2(.50 + sin(t * 2.0) * .32, (portrait ? .70 : .33) + cos(t * 2.7) * .15);
	vec3 ink = mix(vec3(.028,.10,.19), vec3(.055,.31,.38), uv.y);
	vec2 grid = abs(fract(uv * vec2(10.0, 8.0)) - .5);
	ink += .09 * step(.47, max(grid.x, grid.y));
	float band = max(0.0, 1.0 - abs(uv.y - .66 - sin(uv.x * 9.0 + t * 4.0) * .09) * 66.0);
	ink += band * vec3(.19, .86, .77);
	float distance_to_ball = distance(position, center);
	ink = mix(ink, vec3(1., .74, .22), (1.0 - smoothstep(.068, .084, distance_to_ball)));
	ink *= 1.0 - grain * .58 * step(.5, fract(UV.y * pixels.y));
	ink += grain * (noise(uv * pixels + vec2(t * 17.0)) - .47);
	ALBEDO = ink;
}
"""

const FILTER := """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float grain = 0.0;
uniform float fps = 60.0;
void fragment() {
	float t = floor(TIME * fps) / fps;
	vec2 uv = SCREEN_UV;
	uv.x += grain * .013 * sin(uv.y * 115.0 + t * 3.0);
	vec3 color = texture(screen_texture, uv).rgb;
	float grain_sample = fract(sin(dot(FRAGCOORD.xy + t * 27.0, vec2(12.9898,78.233))) * 43758.5453);
	color = color * (1.0 - grain * .45 * step(.50, fract(FRAGCOORD.y * .5))) + (grain_sample - .48) * grain * .66;
	COLOR = vec4(color, 1.);
}
"""

static func demo(screen: MeshInstance3D, portrait: bool) -> ShaderMaterial:
	var material:=ShaderMaterial.new()
	var shader:=Shader.new()
	shader.code=MOTION
	material.shader=shader
	material.set_shader_parameter("portrait",portrait)
	screen.material_override=material
	return material

static func effect() -> ShaderMaterial:
	var material:=ShaderMaterial.new()
	var shader:=Shader.new()
	shader.code=FILTER
	material.shader=shader
	return material
