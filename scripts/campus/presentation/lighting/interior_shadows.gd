extends RefCounted
## Match the cast-shadow setting across the campus's physical fixtures.
static func enabled(light: Light3D, authored: bool, quality: int) -> bool:
	if quality<=0:return false
	if light is DirectionalLight3D:return authored
	return not light.get_meta("fixture_spill",false)

# One instanced pass per furnished room for the soft shadow immediately below
# the props. This also works without screen-space AO.
static func add_contacts(parent: Node3D, placements: Array[Transform3D]) -> void:
	if placements.is_empty():return
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, depth_draw_never, shadows_disabled, fog_disabled;
void fragment() {
	vec2 p = abs(UV * 2.0 - 1.0);
	float spread = pow(p.x, 3.0) + pow(p.y, 3.0);
	ALBEDO = vec3(0.055, 0.066, 0.085);
	ALPHA = 0.62 * (1.0 - smoothstep(0.14, 1.0, spread));
}
"""
	var material := ShaderMaterial.new()
	material.shader=shader
	var batch := MultiMesh.new()
	batch.transform_format=MultiMesh.TRANSFORM_3D
	batch.mesh=PlaneMesh.new()
	batch.mesh.size=Vector2.ONE
	batch.instance_count=placements.size()
	for index in placements.size():batch.set_instance_transform(index,placements[index])
	var contacts := MultiMeshInstance3D.new()
	contacts.name="FurnitureContacts"
	contacts.multimesh=batch
	contacts.material_override=material
	contacts.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	contacts.set_meta("floor_contact_shadows",true)
	parent.add_child(contacts)
