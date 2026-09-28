@tool
extends PanelContainer

## List mode rows are this wide so each entry takes a line of the flow container.
const LIST_ROW_WIDTH := 2000.0
const DRAG_VISUALS := preload("res://addons/better-tile-editor/editor/DragVisuals.gd")

signal select(index)
signal edit_requested(index)
signal context_requested(index)
signal dropped_on(source_id: int, target_id: int)

@onready var color_panel := %Color
@onready var terrain_icon_slot := %TerrainIcon
@onready var type_icon_slot := %TypeIcon
@onready var type_icon_panel := %TerrainIconPanel
@onready var name_label := %Name
@onready var layout_container := %Layout
@onready var icon_layout_container := %IconLayout

var selected := false

var tileset:TileSet
var terrain:Dictionary

var grid_mode := true
var show_type_icon := true
var color_style_list:StyleBoxFlat
var color_style_grid:StyleBoxFlat
var color_style_decoration:StyleBoxFlat

var _terrain_texture:Texture2D
var _lone_source:Texture2D
var _terrain_texture_rect:Rect2i
var _icon_draw_connected := false
var _drop_hint := false

const CliffData := preload("res://addons/better-tile-editor/CliffData.gd")


func _ready():
	update()

func update():
	if !terrain or !terrain.valid:
		return
	if !tileset:
		return
	
	name_label.text = terrain.name
	tooltip_text = "" if terrain.type == BetterTerrain.TerrainType.SINGLE else "%s (%d)" % [terrain.name, terrain.id]
	if terrain.has("scene"):
		tooltip_text = String(terrain.scene.path)
	
	color_style_list = color_panel.get_theme_stylebox("panel").duplicate()
	color_style_grid = color_panel.get_theme_stylebox("panel").duplicate()
	color_style_decoration = color_panel.get_theme_stylebox("panel").duplicate()
	
	color_style_list.bg_color = terrain.color
	color_style_list.corner_radius_top_left = 8
	color_style_list.corner_radius_bottom_left = 8
	color_style_list.corner_radius_top_right = 0
	color_style_list.corner_radius_bottom_right = 0
	color_style_list.content_margin_left = -1
	color_style_list.content_margin_right = -1
	color_style_list.border_width_left = 0
	color_style_list.border_width_right = 0
	color_style_list.border_width_top = 0
	color_style_list.border_width_bottom = 0
	
	color_style_grid.bg_color = terrain.color
	color_style_grid.corner_radius_top_left = 6
	color_style_grid.corner_radius_bottom_left = 6
	color_style_grid.corner_radius_top_right = 6
	color_style_grid.corner_radius_bottom_right = 6
	color_style_grid.content_margin_left = -1
	color_style_grid.content_margin_right = -1
	color_style_grid.border_width_left = 0
	color_style_grid.border_width_right = 0
	color_style_grid.border_width_top = 0
	color_style_grid.border_width_bottom = 0
	
	color_style_decoration.bg_color = terrain.color
	color_style_decoration.corner_radius_top_left = 8
	color_style_decoration.corner_radius_bottom_left = 8
	color_style_decoration.corner_radius_top_right = 8
	color_style_decoration.corner_radius_bottom_right = 8
	color_style_decoration.content_margin_left = -1
	color_style_decoration.content_margin_right = -1
	color_style_decoration.border_width_left = 4
	color_style_decoration.border_width_right = 4
	color_style_decoration.border_width_top = 4
	color_style_decoration.border_width_bottom = 4
	
	match terrain.type:
		BetterTerrain.TerrainType.MATCH_TILES:
			type_icon_slot.texture = load("res://addons/better-tile-editor/icons/MatchTiles.svg")
		BetterTerrain.TerrainType.MATCH_VERTICES:
			type_icon_slot.texture = load("res://addons/better-tile-editor/icons/MatchVertices.svg")
		BetterTerrain.TerrainType.CATEGORY:
			type_icon_slot.texture = load("res://addons/better-tile-editor/icons/NonModifying.svg")
		BetterTerrain.TerrainType.DECORATION:
			type_icon_slot.texture = load("res://addons/better-tile-editor/icons/Decoration.svg")
		BetterTerrain.TerrainType.OBJECT:
			var mass: bool = bool(terrain.get("object", {}).get("mass", false))
			type_icon_slot.texture = load("res://addons/better-tile-editor/icons/ObjectMass.svg" if mass
					else "res://addons/better-tile-editor/icons/ObjectTerrain.svg")
		BetterTerrain.TerrainType.EXEMPLAR:
			type_icon_slot.texture = load("res://addons/better-tile-editor/icons/Exemplar.svg")
		BetterTerrain.TerrainType.SCATTER:
			type_icon_slot.texture = load("res://addons/better-tile-editor/icons/Scatter.svg")
		BetterTerrain.TerrainType.SINGLE:
			type_icon_slot.texture = load("res://addons/better-tile-editor/icons/SingleTile.svg")
		_:
			type_icon_slot.texture = null
	type_icon_slot.visible = show_type_icon
	
	var has_icon = false
	if terrain.has("scene"):
		var scene_icon := EditorInterface.get_base_control().get_theme_icon("PackedScene", "EditorIcons")
		type_icon_slot.texture = scene_icon
		var thumb: Texture2D = terrain.get("thumbnail")
		if thumb != null:
			_terrain_texture = thumb
			_terrain_texture_rect = Rect2i(Vector2i.ZERO, thumb.get_size())
			terrain_icon_slot.queue_redraw()
		else:
			terrain_icon_slot.texture = scene_icon
			terrain_icon_slot.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		has_icon = true
	if not has_icon and terrain.has("icon"):
		if terrain.icon.has("path") and not terrain.icon.path.is_empty():
			terrain_icon_slot.texture = load(terrain.icon.path)
			_terrain_texture = null
			terrain_icon_slot.queue_redraw()
			has_icon = true
		elif terrain.icon.has("source_id") and tileset.has_source(terrain.icon.source_id):
			var source := tileset.get_source(terrain.icon.source_id) as TileSetAtlasSource
			var coord := terrain.icon.coord as Vector2i
			var rect := source.get_tile_texture_region(coord, 0)
			_terrain_texture = source.texture
			_terrain_texture_rect = rect
			terrain_icon_slot.queue_redraw()
			has_icon = true
	
	if not has_icon and terrain.type == BetterTerrain.TerrainType.OBJECT:
		var block := _lone_block_region()
		if block.size.x > 0:
			_terrain_texture = _lone_source
			_terrain_texture_rect = block
			terrain_icon_slot.queue_redraw()
			has_icon = true

	if not has_icon and terrain.type == BetterTerrain.TerrainType.SINGLE:
		var one: Array = BetterTerrain.single_tile_of(tileset, int(terrain.id))
		if one.size() == 3:
			var src := tileset.get_source(one[0]) as TileSetAtlasSource
			if src != null and src.get_tile_at_coords(one[1]) == one[1]:
				_terrain_texture = src.texture
				_terrain_texture_rect = src.get_tile_texture_region(one[1], one[2])
				terrain_icon_slot.queue_redraw()
				has_icon = true

	if not has_icon and terrain.type == BetterTerrain.TerrainType.SCATTER:
		var ScatterTerrain := load("res://addons/better-tile-editor/ScatterTerrain.gd")
		var bag: Array = ScatterTerrain.config_of(tileset, int(terrain.id)).get("bag", [])
		if not bag.is_empty():
			var first: Dictionary = ScatterTerrain.normalise_entry(bag[0])
			var source := tileset.get_source(first.source) as TileSetAtlasSource
			if source != null and source.get_tile_at_coords(first.origin) == first.origin:
				_terrain_texture = source.texture
				_terrain_texture_rect = Rect2(source.get_tile_texture_region(first.origin, 0).position,
					Vector2(source.texture_region_size) * Vector2(first.size))
				terrain_icon_slot.queue_redraw()
				has_icon = true

	if not has_icon and terrain.type == BetterTerrain.TerrainType.EXEMPLAR:
		var drawing := _exemplar_block_region()
		if drawing.size.x > 0:
			_terrain_texture = _lone_source
			_terrain_texture_rect = drawing
			terrain_icon_slot.queue_redraw()
			has_icon = true

	if not has_icon:
		var tiles = BetterTerrain.get_tile_sources_in_terrain(tileset, terrain.id)
		if tiles.size() > 0:
			var source := tiles[0].source as TileSetAtlasSource
			var coord := tiles[0].coord as Vector2i
			var rect := source.get_tile_texture_region(coord, 0)
			_terrain_texture = source.texture
			_terrain_texture_rect = rect
			terrain_icon_slot.queue_redraw()
	
	if _terrain_texture:
		terrain_icon_slot.texture = null
	
	if not _icon_draw_connected:
		terrain_icon_slot.connect("draw", func():
			if _terrain_texture:
				terrain_icon_slot.draw_texture_rect_region(_terrain_texture, _icon_rect(), _terrain_texture_rect)
		)
		_icon_draw_connected = true
	
	update_style()


## Icons keep their shape, so a 2x4 object is not squashed into the square.
func _icon_rect() -> Rect2:
	var box := Vector2(44, 44)
	if _terrain_texture_rect.size.x <= 0 or _terrain_texture_rect.size.y <= 0:
		return Rect2(Vector2.ZERO, box)
	var size := Vector2(_terrain_texture_rect.size)
	size *= minf(box.x / size.x, box.y / size.y)
	return Rect2((box - size) * 0.5, size)


func _exemplar_block_region() -> Rect2i:
	var ExemplarData = load("res://addons/better-tile-editor/ExemplarData.gd")
	var sheet: Dictionary = ExemplarData.table_of(tileset, terrain.name)
	var block: Array = sheet.get("block", [])
	if block.size() != 4:
		return Rect2i()
	var src := tileset.get_source(int(sheet.source)) as TileSetAtlasSource
	if !src or !src.texture:
		return Rect2i()
	var origin := Vector2i(int(block[0]), int(block[1]))
	if not src.has_tile(origin):
		return Rect2i()
	_lone_source = src.texture
	var one_tile := src.get_tile_texture_region(origin, 0)
	return Rect2i(Vector2i(one_tile.position), Vector2i(one_tile.size) * Vector2i(int(block[2]), int(block[3])))


func _lone_block_region() -> Rect2i:
	var ObjectTerrain = load("res://addons/better-tile-editor/ObjectTerrain.gd")
	var cfg: Dictionary = terrain.get("object", {})
	var lone: Array = cfg.get("lone", [])
	if lone.size() != 2:
		return Rect2i()
	var sz: Array = cfg.get("size", [2, 2])
	var size := Vector2i(sz[0], sz[1])
	var origin := Vector2i(lone[0], lone[1])
	for b in ObjectTerrain.detect_blocks(tileset, terrain.id, size):
		if b["rect"].position != origin:
			continue
		var src := tileset.get_source(b["source_id"]) as TileSetAtlasSource
		if !src or !src.texture:
			return Rect2i()
		_lone_source = src.texture
		var one_tile := src.get_tile_texture_region(origin, 0)
		return Rect2i(Vector2i(one_tile.position), Vector2i(one_tile.size) * size)
	return Rect2i()


func update_style():
	if terrain.type == BetterTerrain.TerrainType.DECORATION:
		type_icon_panel.visible = false
		color_panel.custom_minimum_size = Vector2i(52,52)
	else:
		type_icon_panel.visible = true
		color_panel.custom_minimum_size = Vector2i(24,24)
			
	if grid_mode:
		if terrain.type == BetterTerrain.TerrainType.DECORATION:
			color_panel.add_theme_stylebox_override("panel", color_style_decoration)
			color_panel.size_flags_vertical = Control.SIZE_FILL
			icon_layout_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		else:
			color_panel.add_theme_stylebox_override("panel", color_style_grid)
			color_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			icon_layout_container.size_flags_vertical = Control.SIZE_FILL
		custom_minimum_size = Vector2(0, 60)
		size_flags_horizontal = Control.SIZE_FILL
		layout_container.vertical = true
		name_label.visible = false
		icon_layout_container.add_theme_constant_override("separation", -24)
	else:
		if terrain.type == BetterTerrain.TerrainType.DECORATION:
			color_panel.add_theme_stylebox_override("panel", color_style_decoration)
		else:
			color_panel.add_theme_stylebox_override("panel", color_style_list)
		icon_layout_container.size_flags_vertical = Control.SIZE_FILL
		custom_minimum_size = Vector2(LIST_ROW_WIDTH, 60)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		layout_container.vertical = false
		name_label.visible = true
		color_panel.size_flags_vertical = Control.SIZE_FILL
		icon_layout_container.add_theme_constant_override("separation", 4)


## Scene tiles have no preview until the editor has rendered one.
func set_scene_thumbnail(texture: Texture2D) -> void:
	terrain.thumbnail = texture
	update()


func terrain_id() -> int:
	return terrain.id if terrain and terrain.has("id") else BetterTerrain.TileCategory.EMPTY


func set_selected(value:bool = true):
	selected = value
	if value:
		select.emit(terrain_id())
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		context_requested.emit(terrain_id())
		accept_event()
		return
	if event is InputEventMouseButton and event.double_click \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		edit_requested.emit(terrain_id())
		accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if terrain.has("scene"):
		set_drag_preview(_drag_preview())
		return {"better_terrain_scene": get_meta(&"better_terrain_scene"),
			"from_group": get_meta(&"better_terrain_group")}
	var id := terrain_id()
	if id < 0:
		return null
	set_drag_preview(_drag_preview())
	return {"better_terrain_entry": id}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if data is Dictionary and (data.has("better_terrain_group_drag") or data.has("better_terrain_scene")):
		_set_drop_hint(false)
		return get_parent()._can_drop_data(position + _at, data)
	var ok: bool = data is Dictionary and data.has("better_terrain_entry") \
		and terrain_id() >= 0 \
		and int(data["better_terrain_entry"]) != terrain_id()
	_set_drop_hint(ok)
	return ok


func _drop_data(_at: Vector2, data: Variant) -> void:
	_set_drop_hint(false)
	if data.has("better_terrain_group_drag") or data.has("better_terrain_scene"):
		get_parent()._drop_data(position + _at, data)
		return
	dropped_on.emit(int(data["better_terrain_entry"]), terrain_id())


## _can_drop_data stops firing on exit; clear highlights through notifications.
func _notification(what: int) -> void:
	if what in [NOTIFICATION_DRAG_END, NOTIFICATION_MOUSE_EXIT]:
		_set_drop_hint(false)


func _set_drop_hint(on: bool) -> void:
	if _drop_hint == on:
		return
	_drop_hint = on
	queue_redraw()


func _drag_preview() -> Control:
	return DRAG_VISUALS.preview(String(terrain.name) if terrain and terrain.has("name") else "terrain")


func _draw():
	if selected:
		draw_rect(Rect2(Vector2.ZERO, get_rect().size), Color(0.15, 0.70, 1, 0.3))
	if _drop_hint:
		DRAG_VISUALS.highlight(self)


func _on_focus_entered():
	queue_redraw()
	selected = true
	select.emit(terrain_id())


func _on_focus_exited():
	queue_redraw()


func _make_custom_tooltip(for_text: String) -> Object:
	if !tileset or !terrain or !terrain.get("valid", false):
		return null
	if terrain.type == BetterTerrain.TerrainType.SINGLE:
		return null
	var img := _terrain_preview_image()
	if img == null:
		return null

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_picture(img, 2.0))
	var label := Label.new()
	label.text = for_text
	box.add_child(label)
	return box


func _terrain_preview_image() -> Image:
	var region := Rect2i()
	match terrain.type:
		BetterTerrain.TerrainType.EXEMPLAR:
			region = _exemplar_block_region()
		BetterTerrain.TerrainType.OBJECT:
			region = _lone_block_region()
		BetterTerrain.TerrainType.SCATTER:
			return _scatter_patch_image(10)
		_:
			return _terrain_patch_image(5, 3)
	if region.has_area() and _lone_source != null:
		return _lone_source.get_image().get_region(region)
	return null


func _scatter_patch_image(size: int) -> Image:
	var scatter = load("res://addons/better-tile-editor/ScatterTerrain.gd")
	var scratch := TileMapLayer.new()
	scratch.tile_set = tileset
	var cells := PackedVector2Array()
	for y in size:
		for x in size:
			cells.append(Vector2(x, y))
	scatter.set_zone(scratch, terrain.id, cells)
	scatter.rebuild(scratch)
	var layer: TileMapLayer = scatter.find_layer(scratch)
	var bounds := Rect2i(0, 0, size, size)
	if layer != null:
		bounds = bounds.merge(layer.get_used_rect())
	var cell := tileset.tile_size
	var img := Image.create_empty(bounds.size.x * cell.x, bounds.size.y * cell.y, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var color := Color("282c30") if (x + y) % 2 == 0 else Color("33383d")
			img.fill_rect(Rect2i((Vector2i(x, y) - bounds.position) * cell, cell), color)
	if layer != null:
		var art := Image.create_empty(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		var sources := {}
		for at in layer.get_used_cells():
			_blit(art, sources, layer.get_cell_source_id(at), layer.get_cell_atlas_coords(at), at - bounds.position, cell)
		img.blend_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), Vector2i.ZERO)
	scratch.free()
	return img


func _picture(img: Image, scale: float) -> TextureRect:
	var pic := TextureRect.new()
	pic.texture = ImageTexture.create_from_image(img)
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	var image_size := Vector2(img.get_width(), img.get_height())
	pic.custom_minimum_size = image_size * minf(scale, 320.0 / maxf(image_size.x, image_size.y))
	return pic


func _terrain_patch_image(size: int, face_rows: int) -> Image:
	var cell: Vector2i = tileset.tile_size
	if cell.x <= 0 or cell.y <= 0:
		return null

	var scratch := TileMapLayer.new()
	scratch.tile_set = tileset
	var cells := []
	for y in size:
		for x in size:
			cells.append(Vector2i(x, y))
	BetterTerrain.set_cells(scratch, cells, terrain.id)
	BetterTerrain.update_terrain_area(scratch, Rect2i(0, 0, size, size), false)

	var objects = load("res://addons/better-tile-editor/ObjectTerrain.gd")
	if objects != null and objects.has_objects(tileset):
		objects.fix_cells(scratch, cells)

	var cfg := CliffData.config_of(tileset, terrain.name)
	var faces := {}
	if not cfg.get("slots", {}).is_empty():
		var plateau := {}
		for c in cells:
			plateau[c] = true
		var map := CliffData.face_map(cells, face_rows)
		for f in map.keys():
			var case_name := CliffData.case_at(plateau, map, f)
			var tile := CliffData.resolve_tile(cfg, map[f].row, case_name)
			if not tile.is_empty():
				faces[f] = tile

	var rows := size + (face_rows if not faces.is_empty() else 0)
	var img := Image.create(size * cell.x, rows * cell.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# get_image copies the entire atlas; cache it per sourcj.
	var sources := {}
	var any := false
	for c in cells:
		var sid := scratch.get_cell_source_id(c)
		if _blit(img, sources, sid, scratch.get_cell_atlas_coords(c), c, cell):
			any = true
	for f in faces.keys():
		var tile: Dictionary = faces[f]
		if _blit(img, sources, int(tile.source_id), tile.coord, f, cell):
			any = true
	scratch.free()
	return img if any else null


func _blit(img: Image, sources: Dictionary, sid: int, coord: Vector2i,
		at: Vector2i, cell: Vector2i) -> bool:
	if sid < 0:
		return false
	var src := tileset.get_source(sid)
	if not (src is TileSetAtlasSource) or src.texture == null:
		return false
	if not sources.has(sid):
		sources[sid] = src.texture.get_image()
	var atlas: Image = sources[sid]
	if atlas == null:
		return false
	img.blit_rect(atlas, src.get_tile_texture_region(coord),
		Vector2i(at.x * cell.x, at.y * cell.y))
	return true
