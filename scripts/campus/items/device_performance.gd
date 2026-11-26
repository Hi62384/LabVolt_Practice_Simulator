extends Node

signal freeze_changed(frozen: bool)
signal crashed

const MAX := 4
const QUEUE_LIMIT := 24
const APP_SECONDS := [6.5, 3.1, 1.15, .28, 0.0]
const ACTION_SECONDS := [1.35, .62, .23, .07, 0.0]
const FREEZE_INTERVAL := [Vector2(9, 19), Vector2(20, 42), Vector2(48, 90), Vector2(110, 200)]
const FREEZE_LENGTH := [Vector2(2, 5.5), Vector2(1.4, 3.6), Vector2(.8, 2.2), Vector2(.4, 1.1)]
const CRASH_CHANCE := [.35, .18, .08, .025]

var device := ""
var quality := MAX
var rng := RandomNumberGenerator.new()
var frozen := false
var jobs: Array[Dictionary] = []
var remaining := 0.0
var event_in := 0.0

func _ready() -> void:
	set_process(false)

func configure(identity: String, preset: int) -> void:
	if device==identity and quality==preset:return
	device=identity
	quality=clampi(preset,0,MAX)
	discard_jobs()
	if frozen:
		frozen=false
		freeze_changed.emit(false)
	if not device.is_empty() and quality<MAX:
		_schedule_freeze()
		set_process(true)
	else:set_process(false)

func discard_jobs() -> void:
	jobs.clear()
	remaining=0.0

func submit(action: Callable, app_open := false) -> bool:
	if device.is_empty() or quality==MAX:
		action.call()
		return true
	if frozen or jobs.size()>=QUEUE_LIMIT:return false
	var seconds: float=APP_SECONDS[quality] if app_open else ACTION_SECONDS[quality]
	jobs.append({"action":action,"seconds":seconds})
	if jobs.size()==1:remaining=seconds
	return true

func _schedule_freeze() -> void:
	var interval: Vector2=FREEZE_INTERVAL[quality]
	event_in=rng.randf_range(interval.x,interval.y)

func _process(delta: float) -> void:
	event_in-=delta
	if event_in<=0.0:
		if frozen:
			frozen=false
			if rng.randf()<float(CRASH_CHANCE[quality]):
				configure("",MAX)
				freeze_changed.emit(false)
				crashed.emit()
				return
			_schedule_freeze()
			freeze_changed.emit(false)
		else:
			frozen=true
			var length: Vector2=FREEZE_LENGTH[quality]
			event_in=rng.randf_range(length.x,length.y)
			freeze_changed.emit(true)
	if frozen or jobs.is_empty():return
	remaining-=delta
	if remaining>0.0:return
	var next: Dictionary=jobs.pop_front()
	if not jobs.is_empty():remaining=jobs[0].seconds
	if next.action.is_valid():next.action.call()

static func freeze_overlay(title: String) -> CenterContainer:
	var cover:=CenterContainer.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card:=PanelContainer.new()
	card.add_theme_stylebox_override("panel",preload("res://scripts/ui/design_system/tokens.gd").surface(Color("142d3fee"),Color("588296"),14))
	cover.add_child(card)
	var copy:=VBoxContainer.new()
	card.add_child(copy)
	var heading:=Label.new()
	heading.text=title
	heading.add_theme_font_size_override("font_size",18)
	copy.add_child(heading)
	var caption:=Label.new()
	caption.text="Waiting for the device to respond…"
	copy.add_child(caption)
	return cover
