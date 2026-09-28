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
