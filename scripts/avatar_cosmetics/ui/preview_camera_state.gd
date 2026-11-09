class_name CosmeticPreviewCameraState
extends RefCounted

const FOCUS := {
	"body": {"target": Vector3(0, 0.95, 0), "distance": 3.4},
	"faces": {"target": Vector3(0, 1.55, 0), "distance": 1.15},
	"hair": {"target": Vector3(0, 1.62, 0), "distance": 1.3},
	"facial_hair": {"target": Vector3(0, 1.48, 0), "distance": 1.25},
	"tops": {"target": Vector3(0, 1.15, 0), "distance": 2.0},
	"bottoms": {"target": Vector3(0, 0.7, 0), "distance": 2.1},
	"shoes": {"target": Vector3(0, 0.14, 0), "distance": 1.35},
	"accessories": {"target": Vector3(0, 1.1, 0), "distance": 2.5},
}

var yaw := -0.22
var pitch := -0.03
var distance := 3.4
var target := Vector3(0, 0.95, 0)
var manual_until_msec := 0

func mark_manual(now_msec: int) -> void:
	manual_until_msec = now_msec + 1800

func owns_camera(now_msec: int) -> bool:
	return now_msec < manual_until_msec

func focus_category(category: String, now_msec: int, force := false) -> bool:
	if owns_camera(now_msec) and not force:
		return false
	var preset: Dictionary = FOCUS.get(category, FOCUS.body)
	target = preset.target
	distance = float(preset.distance)
	return true

func reset() -> void:
	yaw = -0.22
	pitch = -0.03
	target = FOCUS.body.target
	distance = FOCUS.body.distance
	manual_until_msec = 0

func orbit(delta: Vector2, now_msec: int) -> void:
	# Orbit the camera opposite to the drag so the model follows the pointer.
	yaw -= delta.x * 0.008
	pitch = clampf(pitch - delta.y * 0.006, -0.65, 0.65)
	mark_manual(now_msec)

func zoom(amount: float, now_msec: int) -> void:
	distance = clampf(distance + amount, 0.7, 5.0)
	mark_manual(now_msec)

func pan(delta: Vector2, now_msec: int) -> void:
	var scale := distance * 0.0015
	var right := Vector3.RIGHT.rotated(Vector3.UP, yaw)
	var up := Vector3.UP.rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
	target += (-right * delta.x + up * delta.y) * scale
	mark_manual(now_msec)

