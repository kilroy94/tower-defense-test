extends Label

@export var update_interval := 0.2

var _update_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	text = "FPS: --"


func _process(delta: float) -> void:
	_update_timer -= delta
	if _update_timer > 0.0:
		return

	_update_timer = update_interval
	text = "FPS: %d" % Engine.get_frames_per_second()
