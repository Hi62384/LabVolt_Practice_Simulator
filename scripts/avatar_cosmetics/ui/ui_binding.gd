class_name AvatarCosmeticUIBinding
extends RefCounted

# Read-only bridge from the existing profile dictionary into the additive panel.
# It never saves, grants, purchases, or mutates the supplied profile.
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
const EditIntent = preload("res://scripts/avatar_cosmetics/ui/edit_intent_builder.gd")

var panel: AvatarCosmeticCustomizerPanel
var profile_snapshot: Dictionary

func bind(target: AvatarCosmeticCustomizerPanel, catalog: Dictionary, profile: Dictionary, cache: CosmeticThumbnailCache, avatar_renderer: Callable, animation_handler := Callable()) -> void:
	panel = target
	profile_snapshot = profile.duplicate(true)
	var owned: Array = []
	for value in profile_snapshot.get("owned_cosmetics", []):
		if value is String:
			owned.append(value)
	var raw_state: Variant = profile_snapshot.get("avatar_cosmetics", {})
	var resolved := Core.resolve(catalog, raw_state if raw_state is Dictionary else {}, owned)
	panel.configure(catalog, owned, resolved.state, cache, avatar_renderer, Core.resolve)
	if animation_handler.is_valid() and not panel.preview.animation_requested.is_connected(animation_handler):
		panel.preview.animation_requested.connect(animation_handler)

static func commit_payload(state: Dictionary) -> Dictionary:
	# Main owns the actual profile/save transaction. This payload is already shaped
	# as profile.avatar_cosmetics and intentionally contains no currency/inventory.
	return {"avatar_cosmetics": state.duplicate(true)}

func atomic_edit_intent(state: Dictionary) -> Dictionary:
	var before: Variant = profile_snapshot.get("avatar_cosmetics", {})
	return EditIntent.build(before if before is Dictionary else {}, state)
