class_name SplatTouchControls
extends Control
## Independent touch IDs prevent the move pad, aim pad and action buttons stealing one another.

var state: Dictionary = {"move": Vector2.ZERO, "look": Vector2.ZERO, "fire": false, "swim": false, "jump": false, "sub": false, "special": false, "map": false}
var _touches: Dictionary = {}
var _origin: Dictionary = {}
var _move_knob := Vector2.ZERO
var _look_knob := Vector2.ZERO
var _safe := Rect2()
var _radius: float = 72.0
var _left := Vector2.ZERO
var _right := Vector2.ZERO
var _buttons: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	_safe = SplatUiTheme.safe_rect(size)
	_radius = clampf(minf(size.x, size.y) * 0.12, 56, 94)
	_left = _safe.position + Vector2(_radius * 1.55, _safe.size.y - _radius * 1.6)
	_right = _safe.end - Vector2(_radius * 1.8, _radius * 1.9)
	var action_radius: float = _radius * 0.42
	_buttons = {
		"swim": Rect2(_safe.end - Vector2(_radius * 4.25, _radius * 1.4), Vector2.ONE * action_radius * 2),
		"jump": Rect2(_safe.end - Vector2(_radius * 1.55, _radius * 3.75), Vector2.ONE * action_radius * 2),
		"sub": Rect2(_safe.end - Vector2(_radius * 3.0, _radius * 3.5), Vector2.ONE * action_radius * 2),
		"special": Rect2(_safe.position + Vector2(_safe.size.x - _radius * 1.55, _radius * 2.0), Vector2.ONE * action_radius * 2),
		"map": Rect2(_safe.position + Vector2(_radius * 0.6, _radius * 2.2), Vector2.ONE * action_radius * 2),
	}
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			var action: String = _at(touch.position)
			if action.is_empty():
				return
			_touches[touch.index] = action
			_origin[touch.index] = touch.position
			if action == "look":
				state.fire = true
			elif action != "move":
				state[action] = true
			_update_pad(action, touch.position)
		else:
			var action: String = str(_touches.get(touch.index, ""))
			_touches.erase(touch.index)
			_origin.erase(touch.index)
			if action == "move":
				state.move = Vector2.ZERO
				_move_knob = Vector2.ZERO
			elif action == "look":
				state.fire = false
				_look_knob = Vector2.ZERO
			elif not action.is_empty():
				state[action] = false
		queue_redraw()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		var action: String = str(_touches.get(drag.index, ""))
		if action == "look":
			state.look = (state.look as Vector2) + drag.relative
		_update_pad(action, drag.position)

func _at(point: Vector2) -> String:
	for key: String in _buttons:
		if (_buttons[key] as Rect2).has_point(point):
			return key
	if point.distance_to(_left) < _radius * 1.35:
		return "move"
	if point.distance_to(_right) < _radius * 1.35:
		return "look"
	return ""

func _update_pad(action: String, point: Vector2) -> void:
	if action == "move":
		_move_knob = ((point - _left) / _radius).limit_length(1)
		state.move = _move_knob
	elif action == "look":
		_look_knob = ((point - _right) / _radius).limit_length(1)
	queue_redraw()

func consume() -> Dictionary:
	var result: Dictionary = state.duplicate()
	state.look = Vector2.ZERO
	return result

func reset() -> void:
	_touches.clear()
	_origin.clear()
	state.move = Vector2.ZERO
	state.look = Vector2.ZERO
	for key: String in ["fire", "swim", "jump", "sub", "special", "map"]:
		state[key] = false
	_move_knob = Vector2.ZERO
	_look_knob = Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	for pair: Array in [[_left, _move_knob, SplatUiTheme.ORANGE], [_right, _look_knob, SplatUiTheme.BLUE]]:
		var center: Vector2 = pair[0]
		var knob: Vector2 = pair[1]
		var color: Color = pair[2]
		draw_circle(center, _radius, Color(SplatUiTheme.INK, 0.35))
		draw_arc(center, _radius, 0, TAU, 64, Color(color, 0.7), 3, true)
		draw_circle(center + knob * _radius * 0.6, _radius * 0.38, Color(color, 0.72))
	var labels: Dictionary = {"swim": "SWIM", "jump": "JUMP", "sub": "BOMB", "special": "SP", "map": "MAP"}
	for key: String in _buttons:
		var rect: Rect2 = _buttons[key]
		var color: Color = SplatUiTheme.GOLD if key == "special" else SplatUiTheme.ORANGE
		draw_circle(rect.get_center(), rect.size.x * 0.5, Color(SplatUiTheme.INK, 0.7))
		draw_arc(rect.get_center(), rect.size.x * 0.5, 0, TAU, 40, Color(color, 0.95 if bool(state[key]) else 0.6), 3, true)
		var label: String = labels[key]
		var width: float = SplatUiTheme.DISPLAY.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(SplatUiTheme.DISPLAY, rect.get_center() + Vector2(-width * 0.5, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
