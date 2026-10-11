@tool
extends RefCounted

static func preview(text: String) -> Control:
	var box := PanelContainer.new()
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	box.add_child(label)
	box.modulate = Color(1, 1, 1, 0.85)
	return box

static func highlight(control: Control) -> void:
	var rect := Rect2(Vector2.ZERO, control.size)
	control.draw_rect(rect, Color(0.35, 0.9, 1.0, 0.18), true)
	control.draw_rect(rect, Color(0.35, 0.9, 1.0, 0.95), false, 2.0)


## A bar on one edge of [param control] where a dragged item would go: the right or bottom edge
## when [param after], the left or top one otherwise; vertical when [param across].
static func insertion_bar(control: Control, after: bool, across: bool) -> void:
	var color := Color(0.35, 0.9, 1.0)
	var w := 3.0
	var r: Rect2
	if across:
		r = Rect2(control.size.x - w if after else 0.0, 0.0, w, control.size.y)
	else:
		r = Rect2(0.0, control.size.y - w if after else 0.0, control.size.x, w)
	control.draw_rect(r, color, true)
