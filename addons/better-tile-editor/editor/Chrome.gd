@tool


static func rule() -> HSeparator:
	var sep := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(1, 1, 1, 0.28)
	line.thickness = 2
	line.grow_begin = 0
	line.grow_end = 0
	sep.add_theme_stylebox_override("separator", line)
	sep.custom_minimum_size.y = 14
	return sep


## Draw the gutter background separately; grabber icons are clipped when they exceed the bar.
static var _bars := {}
static var _grabbers := {}

static func bar_style(vertical := false) -> StyleBox:
	if not _bars.has(vertical):
		var img := Image.create_empty(12, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0.10))
		for y in 4:
			img.set_pixel(5, y, Color(1, 1, 1, 0.42))
			img.set_pixel(6, y, Color(1, 1, 1, 0.42))
		if vertical:
			img.rotate_90(CLOCKWISE)
		var box := StyleBoxTexture.new()
		box.texture = ImageTexture.create_from_image(img)
		_bars[vertical] = box
	return _bars[vertical]


static func grabber_icon(vertical := false) -> Texture2D:
	if not _grabbers.has(vertical):
		var img := Image.create_empty(8, 120, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0.18))
		for y in 120:
			img.set_pixel(3, y, Color(1, 1, 1, 0.85))
			img.set_pixel(4, y, Color(1, 1, 1, 0.85))
		if vertical:
			img.rotate_90(CLOCKWISE)
		_grabbers[vertical] = ImageTexture.create_from_image(img)
	return _grabbers[vertical]


static func dress_split(split: SplitContainer) -> void:
	split.dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	split.add_theme_constant_override("separation", 12)
	# SplitContainer uses h_grabber/v_grabber; its subclasses use grabber.
	var vertical := split is VSplitContainer or split.vertical
	split.add_theme_icon_override("h_grabber", grabber_icon(false))
	split.add_theme_icon_override("v_grabber", grabber_icon(true))
	split.add_theme_icon_override("grabber", grabber_icon(vertical))
	# The editor theme hides the handle unless autohide is overridden.
	split.add_theme_constant_override("autohide", 0)
	split.add_theme_stylebox_override("split_bar_background", bar_style(vertical))


static func open_at(split: SplitContainer, fraction: float) -> void:
	if split.get_child_count() < 2:
		push_warning("open_at: the split needs both panes before the ratio can be set")
		return
	var first := split.get_child(0) as Control
	var second := split.get_child(1) as Control
	var flag := Control.SIZE_EXPAND_FILL
	if split is VSplitContainer:
		first.size_flags_vertical = flag
		second.size_flags_vertical = flag
	else:
		first.size_flags_horizontal = flag
		second.size_flags_horizontal = flag
	first.size_flags_stretch_ratio = clampf(fraction, 0.05, 0.95)
	second.size_flags_stretch_ratio = 1.0 - first.size_flags_stretch_ratio
	split.split_offset = 0
