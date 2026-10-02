@tool
extends Control
## A map preview with wheel zoom in whole pixels per cell, drag panning and double-click to fit.
## Owners draw on it, asking current() where the cells go.

## Cells across and down of the map drawn, to fit it.
var grid := Vector2i.ONE
## {cell, origin} in pixels while zoomed or panned; {} fits the map.
var view := {}
## Off when a left drag picks something instead: then the middle or right button pans.
var pan_with_left := true
var _panning := false


func _init() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tooltip_text = "Wheel to zoom, drag to move, double-click to fit"
	gui_input.connect(_on_input)
	resized.connect(queue_redraw)


func fit() -> void:
	view = {}
	queue_redraw()


## The fitted view, or the one zooming and panning left.
func current() -> Dictionary:
	if not view.is_empty():
		return view
	var cell := floorf(minf(size.x / grid.x, size.y / grid.y))
	return {cell = cell, origin = ((size - Vector2(grid) * cell) * 0.5).floor()}


func _on_input(event: InputEvent) -> void:
	var pan_buttons := [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE] if pan_with_left else [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var now := current()
			var step := maxf(1.0, roundf(now.cell * 0.25))
			var cell: float = clampf(now.cell + (step if event.button_index == MOUSE_BUTTON_WHEEL_UP else -step), 2.0, 256.0)
			# The point under the mouse stays put.
			var origin: Vector2 = (event.position - (event.position - now.origin) * (cell / now.cell)).round()
			view = {cell = cell, origin = origin}
			queue_redraw()
			accept_event()
		elif event.double_click and event.button_index in pan_buttons:
			fit()
	if event is InputEventMouseButton and event.button_index in pan_buttons:
		_panning = event.pressed
		mouse_default_cursor_shape = Control.CURSOR_DRAG if _panning else Control.CURSOR_ARROW
	elif event is InputEventMouseMotion and _panning:
		var now := current()
		view = {cell = now.cell, origin = (now.origin + event.relative).round()}
		queue_redraw()
