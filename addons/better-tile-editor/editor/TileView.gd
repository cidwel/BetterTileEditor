@tool
extends Control

const ObjectTerrain := preload("res://addons/better-tile-editor/ObjectTerrain.gd")
const ExemplarData := preload("res://addons/better-tile-editor/ExemplarData.gd")

signal paste_occurred
signal change_zoom_level(value)
signal terrain_updated(index)
signal tile_picked(source_id: int, origin: Vector2i, size: Vector2i)
signal favorite_requested
signal tile_dropped(source_id: int, coord: Vector2i)

@onready var checkerboard := get_theme_icon("Checkerboard", "EditorIcons")

@onready var paint_symmetry_icons := [
	null,
	preload("res://addons/better-tile-editor/icons/paint-symmetry/SymmetryMirror.svg"),
	preload("res://addons/better-tile-editor/icons/paint-symmetry/SymmetryFlip.svg"),
	preload("res://addons/better-tile-editor/icons/paint-symmetry/SymmetryReflect.svg"),
	preload("res://addons/better-tile-editor/icons/paint-symmetry/SymmetryRotateClockwise.svg"),
	preload("res://addons/better-tile-editor/icons/paint-symmetry/SymmetryRotateCounterClockwise.svg"),
	preload("res://addons/better-tile-editor/icons/paint-symmetry/SymmetryRotate180.svg"),
	preload("res://addons/better-tile-editor/icons/paint-symmetry/SymmetryRotateAll.svg"),
	preload("res://addons/better-tile-editor/icons/paint-symmetry/SymmetryAll.svg"),
]

# Draw checkerboard and tiles with specific  materials in
# individual canvas items via rendering server
var _canvas_item_map = {}
var _canvas_item_background : RID

var tileset: TileSet
var disabled_sources: Array[int] = []: set = set_disabled_sources
var show_grid := false:
	set(value):
		show_grid = value
		queue_redraw()

var dim_unassigned_tiles := true
# Off for pickers that only need the plain atlas
var show_terrain_marks := true
var paint := BetterTerrain.TileCategory.NON_TERRAIN
var paint_symmetry := BetterTerrain.SymmetryType.NONE
var highlighted_tile_part := { valid = false }
var zoom_level := 1.0

var tiles_size : Vector2
var tile_size : Vector2i
var tile_part_size : Vector2
var alternate_size : Vector2
var alternate_lookup := []
var initial_click : Vector2i
var prev_position : Vector2i
var current_position : Vector2i

var selection_start : Vector2i
var selection_end : Vector2i
var selection_rect : Rect2i
var selected_tile_states : Array[Dictionary] = []
var copied_tile_states : Array[Dictionary] = []
var staged_paste_tile_states : Array[Dictionary] = []

var pick_icon_terrain : int = -1
var pick_icon_terrain_cancel := false

var single_tile_favorites := false
var pick_tiles := false
var marked_blocks: Array = []
var mark_colour := Color.WHITE
var _pick_from := Vector2i(-1, -1)
var _pick_to := Vector2i(-1, -1)
var _pick_source := -1

var undo_manager : EditorUndoRedoManager
var terrain_undo

# Modes for painting
enum PaintMode {
	NO_PAINT,
	PAINT_TYPE,
	PAINT_PEERING,
	PAINT_SYMMETRY,
	SELECT,
	PASTE,
	PAINT_OBJECT_LONE,
	PAINT_OBJECT_JOINED,
}

var paint_mode := PaintMode.NO_PAINT

# Actual interactions for painting
enum PaintAction {
	NO_ACTION,
	DRAW_TYPE,
	ERASE_TYPE,
	DRAW_PEERING,
	ERASE_PEERING,
	DRAW_SYMMETRY,
	ERASE_SYMMETRY,
	SELECT,
	PASTE,
	DRAW_OBJECT_LONE,
	DRAW_OBJECT_JOINED,
	ERASE_OBJECT_BLOCK,
}

var paint_action := PaintAction.NO_ACTION

var _panning := false

const ALTERNATE_TILE_MARGIN := 18

func _seen_window() -> Rect2:
	var scroll := get_parent() as ScrollContainer
	if scroll == null:
		return Rect2()
	return Rect2(Vector2(scroll.scroll_horizontal, scroll.scroll_vertical), scroll.size)


const DRAW_MARGIN := 64.0

func _visible_window() -> Rect2:
	var seen := _seen_window()
	if seen.size == Vector2.ZERO:
		return Rect2()
	return seen.grow(DRAW_MARGIN)


func _watch_scroll() -> void:
	var scroll := get_parent() as ScrollContainer
	if scroll == null:
		return
	for bar in [scroll.get_h_scroll_bar(), scroll.get_v_scroll_bar()]:
		if bar != null and not bar.value_changed.is_connected(_on_view_moved):
			bar.value_changed.connect(_on_view_moved)
	if not scroll.resized.is_connected(queue_redraw):
		scroll.resized.connect(queue_redraw)


var _drawn_window := Rect2()

func _on_view_moved(_value: float) -> void:
	var seen := _seen_window()
	if seen.size == Vector2.ZERO or not _drawn_window.encloses(seen):
		queue_redraw()


func _enter_tree() -> void:
	_canvas_item_background = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_canvas_item_background, get_canvas_item())
	RenderingServer.canvas_item_set_draw_behind_parent(_canvas_item_background, true)
	_watch_scroll()


func _exit_tree() -> void:
	RenderingServer.free_rid(_canvas_item_background)
	for p in _canvas_item_map:
		RenderingServer.free_rid(_canvas_item_map[p])
	_canvas_item_map.clear()


func refresh_tileset(ts: TileSet) -> void:
	tileset = ts
	
	tiles_size = Vector2.ZERO
	alternate_size = Vector2.ZERO
	alternate_lookup = []
	disabled_sources = disabled_sources.filter(
		func(id):
			return ts.has_source(id)
	)
	
	if !tileset:
		return
	
	for s in tileset.get_source_count():
		var source_id := tileset.get_source_id(s)
		var source := tileset.get_source(source_id) as TileSetAtlasSource
		if !source or !source.texture:
			continue
		
		tiles_size.x = max(tiles_size.x, source.texture.get_width())
		tiles_size.y += source.texture.get_height()
		
		tile_size = source.texture_region_size
		tile_part_size = Vector2(tile_size) / 3.0
		
		for t in source.get_tiles_count():
			var coord := source.get_tile_id(t)
			var alt_count := source.get_alternative_tiles_count(coord)
			if alt_count <= 1:
				continue
			
			var rect := source.get_tile_texture_region(coord, 0)
			alternate_lookup.append([rect.size, source_id, coord])
			alternate_size.x = max(alternate_size.x, rect.size.x * (alt_count - 1))
			alternate_size.y += rect.size.y
	
	_on_zoom_value_changed(zoom_level)


func is_tile_in_source(source: TileSetAtlasSource, coord: Vector2i) -> bool:
	var origin := source.get_tile_at_coords(coord)
	if origin == Vector2i(-1, -1):
		return false
	
	# Animation frames are not needed
	var span := source.get_tile_size_in_atlas(origin)
	return coord.x < origin.x + span.x and coord.y < origin.y + span.y


func _build_tile_part_from_position(result: Dictionary, pos: Vector2i, rect: Rect2) -> void:
	result.rect = rect
	var type := BetterTerrain.get_tile_terrain_type(result.data)
	if type == BetterTerrain.TileCategory.NON_TERRAIN:
		return
	result.terrain_type = type
	
	var normalize_position := (Vector2(pos) - rect.position) / rect.size
	
	var terrain := BetterTerrain.get_terrain(tileset, type)
	if !terrain.valid:
		return
	for p in BetterTerrain.data.get_terrain_peering_cells(tileset, terrain.type):
		var side_polygon = BetterTerrain.data.peering_polygon(tileset, terrain.type, p)
		if Geometry2D.is_point_in_polygon(normalize_position, side_polygon):
			result.peering = p
			result.polygon = side_polygon
			break


# Blocks stay in one atlas: off it, keep the last corner reached.
func _pick_target() -> Vector2i:
	if highlighted_tile_part.valid and highlighted_tile_part.source_id == _pick_source:
		return highlighted_tile_part.coord
	var cell := _atlas_cell_at(current_position)
	if not cell.is_empty() and cell.source_id == _pick_source:
		return cell.coord
	return _pick_to if _pick_to.x >= 0 else _pick_from


## Atlas grid cell under the position, tile or not, or {}.
func _atlas_cell_at(pos: Vector2) -> Dictionary:
	if tileset == null:
		return {}
	var offset := Vector2.ZERO
	for s in tileset.get_source_count():
		var source_id := tileset.get_source_id(s)
		if source_id in disabled_sources:
			continue
		var source := tileset.get_source(source_id) as TileSetAtlasSource
		if source == null or source.texture == null:
			continue
		var area := Rect2(offset, zoom_level * Vector2(source.texture.get_size()))
		if area.has_point(pos):
			var step := Vector2(source.texture_region_size + source.separation)
			var local := (pos - offset) / zoom_level - Vector2(source.margins)
			var coord := Vector2i((local / step).floor())
			var grid := source.get_atlas_grid_size()
			if coord.x < 0 or coord.y < 0 or coord.x >= grid.x or coord.y >= grid.y:
				return {}
			return {source_id = source_id, coord = coord}
		offset.y += zoom_level * source.texture.get_height()
	return {}


# Trim the picked rect to cells that hold a tile.
func _trim_to_tiles(source_id: int, box: Rect2i) -> Rect2i:
	var source: TileSetAtlasSource = null
	if tileset and tileset.has_source(source_id):
		source = tileset.get_source(source_id) as TileSetAtlasSource
	if source == null:
		return box
	var used := Rect2i()
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if source.get_tile_at_coords(Vector2i(x, y)) == Vector2i(-1, -1):
				continue
			var cell := Rect2i(x, y, 1, 1)
			used = cell if used.size == Vector2i.ZERO else used.merge(cell)
	return used if used.size != Vector2i.ZERO else Rect2i(box.position, Vector2i.ONE)


func tile_part_from_position(pos: Vector2i) -> Dictionary:
	if !tileset:
		return { valid = false }
	
	var offset := Vector2.ZERO
	var alt_offset := Vector2.RIGHT * (zoom_level * tiles_size.x + ALTERNATE_TILE_MARGIN)
	if Rect2(alt_offset, zoom_level * alternate_size).has_point(pos):
		for a in alternate_lookup:
			if a[1] in disabled_sources:
				continue
			var next_offset_y = alt_offset.y + zoom_level * a[0].y
			if pos.y > next_offset_y:
				alt_offset.y = next_offset_y
				continue
			
			var source := tileset.get_source(a[1]) as TileSetAtlasSource
			if !source:
				break
			
			var count := source.get_alternative_tiles_count(a[2])
			var index := int((pos.x - alt_offset.x) / (zoom_level * a[0].x)) + 1
			
			if index < count:
				var alt_id := source.get_alternative_tile_id(a[2], index)
				var target_rect := Rect2(
					alt_offset + Vector2.RIGHT * (index - 1) * zoom_level * a[0].x,
					zoom_level * a[0]
				)
				
				var result := {
					valid = true,
					source_id = a[1],
					coord = a[2],
					alternate = alt_id,
					data = source.get_tile_data(a[2], alt_id)
				}
				_build_tile_part_from_position(result, pos, target_rect)
				return result
	
	else:
		for s in tileset.get_source_count():
			var source_id := tileset.get_source_id(s)
			if source_id in disabled_sources:
				continue
			var source := tileset.get_source(source_id) as TileSetAtlasSource
			if !source || !source.texture:
				continue
			for t in source.get_tiles_count():
				var coord := source.get_tile_id(t)
				var rect := source.get_tile_texture_region(coord, 0)
				var target_rect := Rect2(offset + zoom_level * rect.position, zoom_level * rect.size)
				if !target_rect.has_point(pos):
					continue
				
				var result := {
					valid = true,
					source_id = source_id,
					coord = coord,
					alternate = 0,
					data = source.get_tile_data(coord, 0)
				}
				_build_tile_part_from_position(result, pos, target_rect)
				return result
			
			offset.y += zoom_level * source.texture.get_height()
	
	return { valid = false }


func tile_rect_from_position(pos: Vector2i) -> Rect2:
	if !tileset:
		return Rect2(-1,-1,0,0)
	
	var offset := Vector2.ZERO
	var alt_offset := Vector2.RIGHT * (zoom_level * tiles_size.x + ALTERNATE_TILE_MARGIN)
	if Rect2(alt_offset, zoom_level * alternate_size).has_point(pos):
		for a in alternate_lookup:
			if a[1] in disabled_sources:
				continue
			var next_offset_y = alt_offset.y + zoom_level * a[0].y
			if pos.y > next_offset_y:
				alt_offset.y = next_offset_y
				continue
			
			var source := tileset.get_source(a[1]) as TileSetAtlasSource
			if !source:
				break
			
			var count := source.get_alternative_tiles_count(a[2])
			var index := int((pos.x - alt_offset.x) / (zoom_level * a[0].x)) + 1
			
			if index < count:
				var target_rect := Rect2(
					alt_offset + Vector2.RIGHT * (index - 1) * zoom_level * a[0].x,
					zoom_level * a[0]
				)
				return target_rect
	
	else:
		for s in tileset.get_source_count():
			var source_id := tileset.get_source_id(s)
			if source_id in disabled_sources:
				continue
			var source := tileset.get_source(source_id) as TileSetAtlasSource
			if !source:
				continue
			for t in source.get_tiles_count():
				var coord := source.get_tile_id(t)
				var rect := source.get_tile_texture_region(coord, 0)
				var target_rect := Rect2(offset + zoom_level * rect.position, zoom_level * rect.size)
				if target_rect.has_point(pos):
					return target_rect
			
			offset.y += zoom_level * source.texture.get_height()
	
	return Rect2(-1,-1,0,0)


func tile_parts_from_rect(rect:Rect2) -> Array[Dictionary]:
	if !tileset:
		return []
	
	var tiles:Array[Dictionary] = []
	
	var offset := Vector2.ZERO
	var alt_offset := Vector2.RIGHT * (zoom_level * tiles_size.x + ALTERNATE_TILE_MARGIN)
	for s in tileset.get_source_count():
		var source_id := tileset.get_source_id(s)
		if source_id in disabled_sources:
			continue
		var source := tileset.get_source(source_id) as TileSetAtlasSource
		if !source:
			continue
		for t in source.get_tiles_count():
			var coord := source.get_tile_id(t)
			var tile_rect := source.get_tile_texture_region(coord, 0)
			var target_rect := Rect2(offset + zoom_level * tile_rect.position, zoom_level * tile_rect.size)
			if target_rect.intersects(rect):
				var result := {
					valid = true,
					source_id = source_id,
					coord = coord,
					alternate = 0,
					data = source.get_tile_data(coord, 0)
				}
				var pos = target_rect.position + target_rect.size/2
				_build_tile_part_from_position(result, pos, target_rect)
				tiles.push_back(result)
			var alt_count := source.get_alternative_tiles_count(coord)
			for a in alt_count:
				var alt_id := 0
				if a == 0:
					continue
				
				target_rect = Rect2(alt_offset + zoom_level * (a - 1) * tile_rect.size.x * Vector2.RIGHT, zoom_level * tile_rect.size)
				alt_id = source.get_alternative_tile_id(coord, a)
				if target_rect.intersects(rect):
					var td := source.get_tile_data(coord, alt_id)
					var result := {
						valid = true,
						source_id = source_id,
						coord = coord,
						alternate = alt_id,
						data = td
					}
					var pos = target_rect.position + target_rect.size/2
					_build_tile_part_from_position(result, pos, target_rect)
					tiles.push_back(result)
			if alt_count > 1:
				alt_offset.y += zoom_level * tile_rect.size.y
		
		offset.y += zoom_level * source.texture.get_height()
	
	return tiles


func _get_canvas_item(td: TileData) -> RID:
	if !td.material:
		return self.get_canvas_item()
	if _canvas_item_map.has(td.material):
		return _canvas_item_map[td.material]
	
	var rid = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_material(rid, td.material.get_rid())
	RenderingServer.canvas_item_set_parent(rid, get_canvas_item())
	RenderingServer.canvas_item_set_draw_behind_parent(rid, true)
	RenderingServer.canvas_item_set_default_texture_filter(rid, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
	_canvas_item_map[td.material] = rid
	return rid


# Batch terrain diamonds into one mesh to avoid one GPU allocation per polygon.
var _poly_points := PackedVector2Array()
var _poly_colors := PackedColorArray()
var _poly_indices := PackedInt32Array()


func _queue_polygon(points: PackedVector2Array, color: Color) -> void:
	var base := _poly_points.size()
	_poly_points.append_array(points)
	for i in points.size():
		_poly_colors.push_back(color)
	for i in range(1, points.size() - 1):
		_poly_indices.push_back(base)
		_poly_indices.push_back(base + i)
		_poly_indices.push_back(base + i + 1)


func _flush_polygons() -> void:
	if _poly_indices.is_empty():
		return

	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(),
		_poly_indices,
		_poly_points,
		_poly_colors
	)
	_poly_points.clear()
	_poly_colors.clear()
	_poly_indices.clear()


var _draw_terrains := {}
var _draw_polygons := {}

func _drawing_terrain(id: int) -> Dictionary:
	if not _draw_terrains.has(id):
		var terrain := BetterTerrain.get_terrain(tileset, id)
		if terrain.valid:
			terrain["peering_cells"] = BetterTerrain.data.get_terrain_peering_cells(tileset, terrain.type)
		_draw_terrains[id] = terrain
	return _draw_terrains[id]

func _drawing_polygon(type: int, bit: int) -> PackedVector2Array:
	var key := Vector2i(type, bit)
	if not _draw_polygons.has(key):
		_draw_polygons[key] = BetterTerrain.data.peering_polygon(tileset, type, bit)
	return _draw_polygons[key]

func editing_rules() -> bool:
	return paint_action in [PaintAction.DRAW_TYPE, PaintAction.ERASE_TYPE,
		PaintAction.DRAW_PEERING, PaintAction.ERASE_PEERING,
		PaintAction.DRAW_SYMMETRY, PaintAction.ERASE_SYMMETRY]


func _draw_tile_data(texture: Texture2D, rect: Rect2, src_rect: Rect2, td: TileData, draw_sides: bool = true) -> void:
	var flipped_rect := rect
	if td.flip_h:
		flipped_rect.size.x = -rect.size.x
	if td.flip_v:
		flipped_rect.size.y = -rect.size.y

	RenderingServer.canvas_item_add_texture_rect_region(
		_get_canvas_item(td),
		flipped_rect,
		texture.get_rid(),
		src_rect,
		td.modulate,
		td.transpose
	)

	if not show_terrain_marks:
		return
	var type := BetterTerrain.get_tile_terrain_type(td)
	if type == BetterTerrain.TileCategory.NON_TERRAIN:
		if dim_unassigned_tiles:
			draw_rect(rect, Color(0.1, 0.1, 0.1, 0.5), true)
		return

	var terrain := _drawing_terrain(type)
	if !terrain.valid:
		return

	var transform := Transform2D(0.0, rect.size, 0.0, rect.position)
	var center_polygon = transform * _drawing_polygon(terrain.type, -1)
	if terrain.type == BetterTerrain.TerrainType.DECORATION:
		draw_colored_polygon(center_polygon, Color(terrain.color, 0.6))
		center_polygon.append(center_polygon[0])
		draw_polyline(center_polygon, Color.BLACK)
	else:
		_queue_polygon(center_polygon, Color(terrain.color, 0.6))

	if paint < BetterTerrain.TileCategory.EMPTY or paint >= BetterTerrain.terrain_count(tileset):
		return

	if not draw_sides:
		return

	var paint_terrain := _drawing_terrain(paint)
	var paint_color := Color(paint_terrain.color, 0.6)
	var paint_is_decoration: bool = paint_terrain.type == BetterTerrain.TerrainType.DECORATION
	for p in terrain.peering_cells:
		if paint in BetterTerrain.tile_peering_types(td, p):
			var side_polygon = transform * _drawing_polygon(terrain.type, p)
			if paint_is_decoration:
				draw_colored_polygon(side_polygon, paint_color)
				side_polygon.append(side_polygon[0])
				draw_polyline(side_polygon, Color.BLACK)
			else:
				_queue_polygon(side_polygon, paint_color)
		elif paint in BetterTerrain.tile_not_peering_types(td, p):
			for shape in BetterTerrain.data.not_marker(transform * _drawing_polygon(terrain.type, p)):
				_queue_polygon(shape[0], BetterTerrain.data.NOT_RED if shape[1] else Color(paint_terrain.color, 0.9))


func _draw_tile_symmetry(texture: Texture2D, rect: Rect2, src_rect: Rect2, td: TileData, draw_icon: bool = true) -> void:
	var flipped_rect := rect
	if td.flip_h:
		flipped_rect.size.x = -rect.size.x
	if td.flip_v:
		flipped_rect.size.y = -rect.size.y
	
	RenderingServer.canvas_item_add_texture_rect_region(
		_get_canvas_item(td),
		flipped_rect,
		texture.get_rid(),
		src_rect,
		td.modulate,
		td.transpose
	)
	
	if not draw_icon:
		return
	
	var symmetry_type = BetterTerrain.get_tile_symmetry_type(td)
	if symmetry_type == 0:
		return
	var symmetry_icon = paint_symmetry_icons[symmetry_type]
	
	RenderingServer.canvas_item_add_texture_rect_region(
		_get_canvas_item(td),
		rect,
		symmetry_icon.get_rid(),
		Rect2(Vector2.ZERO, symmetry_icon.get_size()),
		Color(1,1,1,0.5)
	)


func _draw() -> void:
	_draw_terrains.clear()
	_draw_polygons.clear()
	_poly_points.clear()
	_poly_colors.clear()
	_poly_indices.clear()
	if !tileset:
		return

	# Clear material-based render targets
	RenderingServer.canvas_item_clear(_canvas_item_background)
	for p in _canvas_item_map:
		RenderingServer.canvas_item_clear(_canvas_item_map[p])
	
	var offset := Vector2.ZERO
	var alt_offset := Vector2.RIGHT * (zoom_level * tiles_size.x + ALTERNATE_TILE_MARGIN)
	# An empty window means no ScrollContainer clipping is available.
	var window := _visible_window()
	var cull := window.size != Vector2.ZERO
	_drawn_window = window
	
	RenderingServer.canvas_item_add_texture_rect(
		_canvas_item_background,
		Rect2(alt_offset, zoom_level * alternate_size),
		checkerboard.get_rid(),
		true
	)
	
	for s in tileset.get_source_count():
		var source_id := tileset.get_source_id(s)
		if source_id in disabled_sources:
			continue
		var source := tileset.get_source(source_id) as TileSetAtlasSource
		if !source or !source.texture:
			continue
		
		RenderingServer.canvas_item_add_texture_rect(
			_canvas_item_background,
			Rect2(offset, zoom_level * source.texture.get_size()),
			checkerboard.get_rid(),
			true
		)
		var band := Rect2(offset, zoom_level * source.texture.get_size())
		var band_seen := not cull or window.intersects(band)
		for t in source.get_tiles_count():
			var coord := source.get_tile_id(t)
			var rect := source.get_tile_texture_region(coord, 0)
			var alt_count := source.get_alternative_tiles_count(coord)
			if cull and not band_seen and alt_count < 2:
				continue
			var target_rect : Rect2
			for a in alt_count:
				var alt_id := 0
				if a == 0:
					target_rect = Rect2(offset + zoom_level * rect.position, zoom_level * rect.size)
				else:
					target_rect = Rect2(alt_offset + zoom_level * (a - 1) * rect.size.x * Vector2.RIGHT, zoom_level * rect.size)
					alt_id = source.get_alternative_tile_id(coord, a)
				
				if cull and not window.intersects(target_rect):
					continue
				var td := source.get_tile_data(coord, alt_id)
				var drawing_current = BetterTerrain.get_tile_terrain_type(td) == paint
				if paint_mode == PaintMode.PAINT_SYMMETRY:
					_draw_tile_symmetry(source.texture, target_rect, rect, td, drawing_current)
				else:
					_draw_tile_data(source.texture, target_rect, rect, td)
				
				if show_grid and a > 0:
					draw_rect(target_rect, Color(0.75, 0.8, 0.85, 0.28), false, 1.0)
				if drawing_current:
					draw_rect(target_rect.grow(-1), Color(0,0,0, 0.75), false, 1)
					draw_rect(target_rect, Color(1,1,1, 0.75), false, 1)
				
				if paint_mode == PaintMode.SELECT:
					var _hit := selected_tile_states.any(func(v):
						return v.part.data == td
						)
					if _hit:
						draw_rect(target_rect.grow(-1), Color.DEEP_SKY_BLUE, false, 2)
			
			if alt_count > 1:
				alt_offset.y += zoom_level * rect.size.y
		
		_draw_exemplar_outline(source, offset)
		_draw_marked_blocks(source, source_id, offset)

		# Blank out unused or uninteresting tiles
		var grid_size := source.get_atlas_grid_size()
		var from := Vector2i.ZERO
		var to := grid_size
		if cull:
			if not band_seen:
				from = grid_size
			else:
				var step := source.separation + source.texture_region_size
				var local := Vector2(window.position - offset) / zoom_level
				from = Vector2i(
					maxi(0, int(floor((local.x - source.margins.x) / step.x))),
					maxi(0, int(floor((local.y - source.margins.y) / step.y))))
				to = Vector2i(
					mini(grid_size.x, int(ceil((local.x + window.size.x / zoom_level - source.margins.x) / step.x)) + 1),
					mini(grid_size.y, int(ceil((local.y + window.size.y / zoom_level - source.margins.y) / step.y)) + 1))
		for y in range(from.y, to.y):
			for x in range(from.x, to.x):
				var pos := Vector2i(x, y)
				if show_grid:
					var grid_pos := source.margins + pos * (source.separation + source.texture_region_size)
					draw_rect(Rect2(offset + zoom_level * grid_pos, zoom_level * source.texture_region_size), Color(0.75, 0.8, 0.85, 0.28), false, 1.0)
				if !is_tile_in_source(source, pos):
					var atlas_pos := source.margins + pos * (source.separation + source.texture_region_size)
					draw_rect(Rect2(offset + zoom_level * atlas_pos, zoom_level * source.texture_region_size), Color(0.0, 0.0, 0.0, 0.8), true)
		
		offset.y += zoom_level * source.texture.get_height()
	
	# Blank out unused alternate tile sections
	alt_offset = Vector2.RIGHT * (zoom_level * tiles_size.x + ALTERNATE_TILE_MARGIN)
	for a in alternate_lookup:
		if a[1] in disabled_sources:
			continue
		var source := tileset.get_source(a[1]) as TileSetAtlasSource
		if source:
			var count := source.get_alternative_tiles_count(a[2]) - 1
			var occupied_width = count * zoom_level * a[0].x
			var area := Rect2(
				alt_offset.x + occupied_width,
				alt_offset.y,
				zoom_level * alternate_size.x - occupied_width,
				zoom_level * a[0].y
			)
			draw_rect(area, Color(0.0, 0.0, 0.0, 0.8), true)
		alt_offset.y += zoom_level * a[0].y

	_flush_polygons()

	if highlighted_tile_part.valid:
		if paint_mode == PaintMode.PAINT_PEERING and highlighted_tile_part.has("polygon"):
			var transform := Transform2D(0.0, highlighted_tile_part.rect.size - 2 * Vector2.ONE, 0.0, highlighted_tile_part.rect.position + Vector2.ONE)
			draw_colored_polygon(transform * highlighted_tile_part.polygon, Color(Color.WHITE, 0.2))
		if paint_mode != PaintMode.NO_PAINT:
			var span := _object_span()
			var rect_size: Vector2 = highlighted_tile_part.rect.size * Vector2(span)
			var inner_rect := Rect2(highlighted_tile_part.rect.position + Vector2.ONE, rect_size - 2 * Vector2.ONE)
			draw_rect(inner_rect, Color.WHITE, false, 2.0 if span != Vector2i.ONE else -1.0)
		elif pick_tiles and _pick_from.x < 0:
			var r: Rect2 = highlighted_tile_part.rect
			draw_rect(Rect2(r.position + Vector2.ONE, r.size - 2 * Vector2.ONE), Color.WHITE, false)
		if paint_mode == PaintMode.PAINT_SYMMETRY:
			if paint_symmetry > 0:
				var symmetry_icon = paint_symmetry_icons[paint_symmetry]
				draw_texture_rect(symmetry_icon, highlighted_tile_part.rect, false, Color(0.5,0.75,1,0.5))
	
	if paint_mode == PaintMode.SELECT:
		draw_rect(selection_rect, Color.WHITE, false)
	
	if paint_mode == PaintMode.PASTE:
		if staged_paste_tile_states.size() > 0:
			var base_rect = staged_paste_tile_states[0].base_rect
			var paint_terrain := BetterTerrain.get_terrain(tileset, paint)
			var paint_terrain_type = paint_terrain.type
			if paint_terrain_type == BetterTerrain.TerrainType.CATEGORY:
				paint_terrain_type = 0
			for state in staged_paste_tile_states:
				var staged_rect:Rect2 = state.base_rect
				staged_rect.position -= base_rect.position + base_rect.size / 2
				
				staged_rect.position *= zoom_level
				staged_rect.size *= zoom_level
				
				staged_rect.position += Vector2(current_position)
				
				var real_rect = tile_rect_from_position(staged_rect.get_center())
				if real_rect.position.x >= 0:
					draw_rect(real_rect, Color(0,0,0, 0.3), true)
					var transform := Transform2D(0.0, real_rect.size, 0.0, real_rect.position)
					var tile_sides = BetterTerrain.data.get_terrain_peering_cells(tileset, paint_terrain_type)
					for p in tile_sides:
						if state.paint in BetterTerrain.tile_peering_types(state.part.data, p):
							var side_polygon = BetterTerrain.data.peering_polygon(tileset, paint_terrain_type, p)
							var color = Color(paint_terrain.color, 0.6)
							draw_colored_polygon(transform * side_polygon, color)
						elif state.paint in BetterTerrain.tile_not_peering_types(state.part.data, p):
							var side_polygon = transform * BetterTerrain.data.peering_polygon(tileset, paint_terrain_type, p)
							for shape in BetterTerrain.data.not_marker(side_polygon):
								draw_colored_polygon(shape[0], BetterTerrain.data.NOT_RED if shape[1] else Color(paint_terrain.color, 0.6))
				
				draw_rect(staged_rect, Color.DEEP_PINK, false)


func delete_selection():
	if selected_tile_states.is_empty():
		return
	undo_manager.create_action("Delete tile terrain peering types", UndoRedo.MERGE_DISABLE, tileset)
	for t in selected_tile_states:
		for side in range(16):
			var old_peering = BetterTerrain.tile_peering_types(t.part.data, side)
			if old_peering.has(paint):
				undo_manager.add_do_method(BetterTerrain, &"remove_tile_peering_type", tileset, t.part.data, side, paint)
				undo_manager.add_undo_method(BetterTerrain, &"add_tile_peering_type", tileset, t.part.data, side, paint)
			if BetterTerrain.tile_not_peering_types(t.part.data, side).has(paint):
				undo_manager.add_do_method(BetterTerrain, &"remove_tile_not_peering_type", tileset, t.part.data, side, paint)
				undo_manager.add_undo_method(BetterTerrain, &"add_tile_not_peering_type", tileset, t.part.data, side, paint)
	
	undo_manager.add_do_method(self, &"queue_redraw")
	undo_manager.add_undo_method(self, &"queue_redraw")
	undo_manager.commit_action()


func toggle_selection():
	undo_manager.create_action("Toggle tile terrain", UndoRedo.MERGE_DISABLE, tileset, true)
	for t in selected_tile_states:
		var type := BetterTerrain.get_tile_terrain_type(t.part.data)
		var goal := paint if paint != type else BetterTerrain.TileCategory.NON_TERRAIN
		
		terrain_undo.add_do_method(undo_manager, BetterTerrain, &"set_tile_terrain_type", [tileset, t.part.data, goal])
		if goal == BetterTerrain.TileCategory.NON_TERRAIN:
			terrain_undo.create_peering_restore_point_tile(
				undo_manager,
				tileset,
				t.part.source_id,
				t.part.coord,
				t.part.alternate
			)
		else:
			undo_manager.add_undo_method(BetterTerrain, &"set_tile_terrain_type", tileset, t.part.data, type)
	
	terrain_undo.add_do_method(undo_manager, self, &"queue_redraw", [])
	undo_manager.add_undo_method(self, &"queue_redraw")
	undo_manager.commit_action()
	terrain_undo.action_count += 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and highlighted_tile_part.valid:
		highlighted_tile_part = {valid = false}
		queue_redraw()


func _draw_marked_blocks(source: TileSetAtlasSource, source_id: int, offset: Vector2) -> void:
	if marked_blocks.is_empty() and not pick_tiles:
		return
	var cell := Vector2(source.texture_region_size)
	var step := Vector2(source.texture_region_size + source.separation)
	var at := func(c: Vector2i) -> Vector2:
		return offset + zoom_level * (Vector2(source.margins) + Vector2(c) * step)

	for e in marked_blocks:
		if single_tile_favorites and _pick_from.x >= 0:
			continue
		if int(e.source) != source_id:
			continue
		var r := Rect2(at.call(e.origin), zoom_level * cell * Vector2(e.size))
		if single_tile_favorites and Vector2i(e.size) == Vector2i.ONE:
			draw_rect(r.grow(-1), Color.WHITE, false, 1.5)
			continue
		draw_rect(r.grow(-1), Color(0, 0, 0, 0.55), false, 3.0)
		draw_rect(r.grow(-1), mark_colour, false, 1.5)

	if pick_tiles and _pick_from.x >= 0 and _pick_source == source_id:
		var to := _pick_target()
		var lo := Vector2i(mini(_pick_from.x, to.x), mini(_pick_from.y, to.y))
		var hi := Vector2i(maxi(_pick_from.x, to.x), maxi(_pick_from.y, to.y))
		var box := Rect2(at.call(lo), zoom_level * cell * Vector2(hi - lo + Vector2i.ONE))
		if single_tile_favorites and hi == lo:
			draw_rect(box.grow(-1), Color.WHITE, false, 1.5)
			return
		draw_rect(box, Color(1.0, 1.0, 1.0, 0.12))
		draw_rect(box, Color(1.0, 0.95, 0.4), false, 2.0)


func _draw_exemplar_outline(source: TileSetAtlasSource, offset: Vector2) -> void:
	if tileset == null or paint < 0:
		return
	var t := BetterTerrain.get_terrain(tileset, paint)
	if not t.valid or t.type != BetterTerrain.TerrainType.EXEMPLAR:
		return
	var source_id := -1
	for i in tileset.get_source_count():
		if tileset.get_source(tileset.get_source_id(i)) == source:
			source_id = tileset.get_source_id(i)
			break
	var cell := Vector2(source.texture_region_size)
	var step := Vector2(source.texture_region_size + source.separation)
	var at := func(c: Vector2i) -> Vector2:
		return offset + zoom_level * (Vector2(source.margins) + Vector2(c) * step)
	var font := get_theme_default_font()
	var fsize := get_theme_default_font_size()

	var pinned := ExemplarData.drawing_of(tileset, paint)
	var lo: Vector2i
	var hi: Vector2i
	var label := ""
	var marked := {}
	if not pinned.is_empty():
		if int(pinned.source) != source_id:
			return
		var r: Rect2i = pinned.rect
		lo = r.position
		hi = r.end - Vector2i.ONE
		label = "drawing (pinned)"
		for y in r.size.y:
			for x in r.size.x:
				marked[r.position + Vector2i(x, y)] = true
	else:
		lo = Vector2i(1 << 30, 1 << 30)
		hi = Vector2i(-(1 << 30), -(1 << 30))
		for i in source.get_tiles_count():
			var coord := source.get_tile_id(i)
			if BetterTerrain.get_tile_terrain_type(source.get_tile_data(coord, 0)) != paint:
				continue
			marked[coord] = true
			lo = Vector2i(mini(lo.x, coord.x), mini(lo.y, coord.y))
			hi = Vector2i(maxi(hi.x, coord.x), maxi(hi.y, coord.y))
		if marked.is_empty():
			return
		label = "drawing: the marked tiles, read on the first stroke"

	var block := Rect2(at.call(lo), at.call(hi) - at.call(lo) + zoom_level * cell)
	draw_rect(block.grow(2), Color(0, 0, 0, 0.6), false, 4.0)
	draw_rect(block.grow(2), Color(1.0, 0.85, 0.3), false, 2.0)
	draw_string(font, block.position + Vector2(4, -6), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1.0, 0.85, 0.3))

	var wlo := Vector2i(1 << 30, 1 << 30)
	var whi := Vector2i(-(1 << 30), -(1 << 30))
	for c in marked:
		var solid := true
		for d in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			if not marked.has(c + d):
				solid = false
				break
		if solid:
			wlo = Vector2i(mini(wlo.x, c.x), mini(wlo.y, c.y))
			whi = Vector2i(maxi(whi.x, c.x), maxi(whi.y, c.y))
	var note_y: float = block.position.y + block.size.y + fsize + 4
	if whi.x < wlo.x:
		draw_string(font, Vector2(block.position.x + 4, note_y),
			"nothing inside yet: mark the whole drawing, bank and all",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1.0, 0.45, 0.35))
		return
	var water := Rect2(at.call(wlo), at.call(whi) - at.call(wlo) + zoom_level * cell)
	draw_rect(water, Color(0, 0, 0, 0.6), false, 3.0)
	draw_rect(water, Color(0.45, 0.85, 1.0), false, 1.5)
	var wsize := whi - wlo + Vector2i.ONE
	var note := "inside %dx%d" % [wsize.x, wsize.y]
	var colour := Color(0.45, 0.85, 1.0)
	if wsize.x < 3 or wsize.y < 3:
		note += "  (needs 3 or more each way to stretch)"
		colour = Color(1.0, 0.45, 0.35)
	draw_string(font, Vector2(block.position.x + 4, note_y), note,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, colour)

	if not pinned.is_empty():
		var strays: Array = ExemplarData.strays(tileset, paint)
		for c in strays:
			var r := Rect2(at.call(c), zoom_level * cell)
			draw_line(r.position, r.end, Color(1.0, 0.3, 0.3), 2.0)
			draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color(1.0, 0.3, 0.3), 2.0)
		if not strays.is_empty():
			draw_string(font, Vector2(block.position.x + 4, note_y + fsize + 4),
				"%d tile%s of this drawing %s marked as another terrain. It is read anyway; re-mark %s if that was a slip." % [
					strays.size(), "" if strays.size() == 1 else "s", "is" if strays.size() == 1 else "are",
					"it" if strays.size() == 1 else "them"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1.0, 0.45, 0.35))


func _object_span() -> Vector2i:
	if paint_mode != PaintMode.PAINT_OBJECT_LONE and paint_mode != PaintMode.PAINT_OBJECT_JOINED:
		return Vector2i.ONE
	return ObjectTerrain.object_size(tileset, paint)


func _paint_object_block(is_lone: bool) -> void:
	var cfg := ObjectTerrain.object_config(tileset, paint)
	if cfg.is_empty():
		return
	var object_size := ObjectTerrain.object_size(tileset, paint)
	var origin: Vector2i = highlighted_tile_part.coord
	var src := tileset.get_source(highlighted_tile_part.source_id) as TileSetAtlasSource
	if src == null:
		return

	var data := []
	for dy in object_size.y:
		for dx in object_size.x:
			var c: Vector2i = origin + Vector2i(dx, dy)
			if src.get_tile_at_coords(c) != c:
				return
			data.push_back(src.get_tile_data(c, 0))

	undo_manager.create_action("Mark object block", UndoRedo.MERGE_DISABLE, tileset, true)
	for d in data:
		var before := BetterTerrain.get_tile_terrain_type(d)
		undo_manager.add_do_method(BetterTerrain, &"set_tile_terrain_type", tileset, d, paint)
		undo_manager.add_undo_method(BetterTerrain, &"set_tile_terrain_type", tileset, d, before)
	if is_lone:
		var updated := cfg.duplicate()
		updated["size"] = [object_size.x, object_size.y]
		updated["lone"] = [origin.x, origin.y]
		undo_manager.add_do_method(BetterTerrain, &"set_terrain_object", tileset, paint, updated)
		undo_manager.add_undo_method(BetterTerrain, &"set_terrain_object", tileset, paint, cfg)
	undo_manager.add_do_method(self, &"queue_redraw")
	undo_manager.add_undo_method(self, &"queue_redraw")
	undo_manager.commit_action()


func _erase_object_block() -> void:
	var cfg := ObjectTerrain.object_config(tileset, paint)
	if cfg.is_empty():
		return
	var object_size := ObjectTerrain.object_size(tileset, paint)
	var origin: Vector2i = highlighted_tile_part.coord
	var src := tileset.get_source(highlighted_tile_part.source_id) as TileSetAtlasSource
	if src == null:
		return

	var data := []
	for dy in object_size.y:
		for dx in object_size.x:
			var c: Vector2i = origin + Vector2i(dx, dy)
			if src.get_tile_at_coords(c) != c:
				continue
			var d := src.get_tile_data(c, 0)
			if BetterTerrain.get_tile_terrain_type(d) == paint:
				data.push_back(d)
	if data.is_empty():
		return

	undo_manager.create_action("Clear object block", UndoRedo.MERGE_DISABLE, tileset, true)
	for d in data:
		undo_manager.add_do_method(BetterTerrain, &"set_tile_terrain_type", tileset, d, BetterTerrain.TileCategory.NON_TERRAIN)
		undo_manager.add_undo_method(BetterTerrain, &"set_tile_terrain_type", tileset, d, paint)
	var lone: Array = cfg.get("lone", [])
	if lone.size() == 2 and Vector2i(lone[0], lone[1]) == origin:
		var updated := cfg.duplicate()
		updated.erase("lone")
		undo_manager.add_do_method(BetterTerrain, &"set_terrain_object", tileset, paint, updated)
		undo_manager.add_undo_method(BetterTerrain, &"set_terrain_object", tileset, paint, cfg)
	undo_manager.add_do_method(self, &"queue_redraw")
	undo_manager.add_undo_method(self, &"queue_redraw")
	undo_manager.commit_action()


func copy_selection():
	copied_tile_states = selected_tile_states


func paste_selection():
	staged_paste_tile_states = copied_tile_states
	selected_tile_states = []
	paint_mode = PaintMode.PASTE
	paint_action = PaintAction.PASTE
	paste_occurred.emit()
	queue_redraw()


func set_disabled_sources(list):
	disabled_sources = list
	queue_redraw()


func emit_terrain_updated(index):
	terrain_updated.emit(index)


## Disable atlas cut shortcuts while the map selection tool owns them.
var shortcuts_blocked := false


func _gui_input(event) -> void:
	if event is InputEventKey and event.is_pressed() and shortcuts_blocked:
		match event.keycode:
			KEY_DELETE, KEY_C, KEY_X, KEY_V:
				return
	if event is InputEventKey and event.is_pressed():
		if event.keycode == KEY_DELETE and not event.echo:
			accept_event()
			delete_selection()
		if event.keycode == KEY_ENTER and not event.echo:
			accept_event()
			toggle_selection()
		if event.keycode == KEY_ESCAPE and not event.echo:
			accept_event()
			if paint_action == PaintAction.PASTE:
				staged_paste_tile_states = []
				paint_mode = PaintMode.SELECT
				paint_action = PaintAction.NO_ACTION
				selection_start = Vector2i(-1,-1)
		if event.keycode == KEY_C and (event.ctrl_pressed or event.meta_pressed) and not event.echo:
			accept_event()
			copy_selection()
		if event.keycode == KEY_X and (event.ctrl_pressed or event.meta_pressed) and not event.echo:
			accept_event()
			copy_selection()
			delete_selection()
		if event.keycode == KEY_V and (event.ctrl_pressed or event.meta_pressed) and not event.echo:
			accept_event()
			paste_selection()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			accept_event()
			_zoom_at_cursor(event.position, 1.1)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			accept_event()
			_zoom_at_cursor(event.position, 1.0 / 1.1)
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and single_tile_favorites:
			accept_event()
			if event.pressed:
				favorite_requested.emit()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			accept_event()
			_panning = event.pressed
			return

	if _panning and event is InputEventMouseMotion:
		var scroll := get_parent() as ScrollContainer
		if scroll:
			scroll.scroll_horizontal -= int(event.relative.x)
			scroll.scroll_vertical -= int(event.relative.y)
		accept_event()
		return
	
	var released : bool = event is InputEventMouseButton and (not event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT))
	if released:
		paint_action = PaintAction.NO_ACTION
	
	if event is InputEventMouseMotion:
		prev_position = current_position
		current_position = event.position
		var tile := tile_part_from_position(event.position)
		if tile.valid != highlighted_tile_part.valid or\
			(tile.valid and tile.data != highlighted_tile_part.data) or\
			(tile.valid and tile.get("peering") != highlighted_tile_part.get("peering")) or\
			event.button_mask & MOUSE_BUTTON_LEFT and paint_action == PaintAction.SELECT:
			queue_redraw()
		highlighted_tile_part = tile
	
	var clicked : bool = event is InputEventMouseButton and (event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT))
	if clicked:
		initial_click = current_position
		selection_start = Vector2i(-1,-1)
		terrain_undo.action_index += 1
		terrain_undo.action_count = 0
	if released:
		terrain_undo.finish_action()
		selection_rect = Rect2i(0,0,0,0)
		queue_redraw()

	if pick_tiles:
		if clicked or released:
			highlighted_tile_part = tile_part_from_position(event.position)
		if clicked and event.button_index == MOUSE_BUTTON_RIGHT:
			if highlighted_tile_part.valid:
				tile_dropped.emit(highlighted_tile_part.source_id, highlighted_tile_part.coord)
			return
		if clicked and event.button_index == MOUSE_BUTTON_LEFT:
			# Drags can start on an empty cell, it gets trimmed on release.
			var start := _atlas_cell_at(event.position)
			if highlighted_tile_part.valid:
				start = {source_id = highlighted_tile_part.source_id, coord = highlighted_tile_part.coord}
			if not start.is_empty():
				_pick_from = start.coord
				_pick_to = _pick_from
				_pick_source = start.source_id
			queue_redraw()
			return
		if event is InputEventMouseMotion:
			if _pick_from.x >= 0:
				_pick_to = _pick_target()
				queue_redraw()
			return
		if released and _pick_from.x >= 0:
			var to := _pick_target()
			var lo := Vector2i(mini(_pick_from.x, to.x), mini(_pick_from.y, to.y))
			var hi := Vector2i(maxi(_pick_from.x, to.x), maxi(_pick_from.y, to.y))
			var box := _trim_to_tiles(_pick_source, Rect2i(lo, hi - lo + Vector2i.ONE))
			tile_picked.emit(_pick_source, box.position, box.size)
			_pick_from = Vector2i(-1, -1)
			_pick_to = Vector2i(-1, -1)
			_pick_source = -1
			queue_redraw()
			return
		return

	if paint_action == PaintAction.PASTE:
		if event is InputEventMouseMotion:
			queue_redraw()
		
		if clicked:
			if event.button_index == MOUSE_BUTTON_LEFT and staged_paste_tile_states.size() > 0:
				undo_manager.create_action("Paste tile terrain peering types", UndoRedo.MERGE_DISABLE, tileset)
				var base_rect = staged_paste_tile_states[0].base_rect
				for p in staged_paste_tile_states:
					var staged_rect:Rect2 = p.base_rect
					staged_rect.position -= base_rect.position + base_rect.size / 2
					
					staged_rect.position *= zoom_level
					staged_rect.size *= zoom_level
					
					staged_rect.position += Vector2(current_position)
					
					var old_tile_part = tile_part_from_position(staged_rect.get_center())
					var new_tile_state = p
					if (not old_tile_part.valid) or (not new_tile_state.part.valid):
						continue
					
					for side in range(16):
						var old_peering = BetterTerrain.tile_peering_types(old_tile_part.data, side)
						var new_sides = new_tile_state.sides
						if new_sides.has(side) and not old_peering.has(paint):
							undo_manager.add_do_method(BetterTerrain, &"add_tile_peering_type", tileset, old_tile_part.data, side, paint)
							undo_manager.add_undo_method(BetterTerrain, &"remove_tile_peering_type", tileset, old_tile_part.data, side, paint)
						elif old_peering.has(paint) and not new_sides.has(side):
							undo_manager.add_do_method(BetterTerrain, &"remove_tile_peering_type", tileset, old_tile_part.data, side, paint)
							undo_manager.add_undo_method(BetterTerrain, &"add_tile_peering_type", tileset, old_tile_part.data, side, paint)
						
						var old_not = BetterTerrain.tile_not_peering_types(old_tile_part.data, side)
						var new_not_sides = new_tile_state.get("not_sides", [])
						if new_not_sides.has(side) and not old_not.has(paint):
							undo_manager.add_do_method(BetterTerrain, &"add_tile_not_peering_type", tileset, old_tile_part.data, side, paint)
							undo_manager.add_undo_method(BetterTerrain, &"remove_tile_not_peering_type", tileset, old_tile_part.data, side, paint)
						elif old_not.has(paint) and not new_not_sides.has(side):
							undo_manager.add_do_method(BetterTerrain, &"remove_tile_not_peering_type", tileset, old_tile_part.data, side, paint)
							undo_manager.add_undo_method(BetterTerrain, &"add_tile_not_peering_type", tileset, old_tile_part.data, side, paint)
					
					var old_symmetry = BetterTerrain.get_tile_symmetry_type(old_tile_part.data)
					var new_symmetry = new_tile_state.symmetry
					if new_symmetry != old_symmetry:
						undo_manager.add_do_method(BetterTerrain, &"set_tile_symmetry_type", tileset, old_tile_part.data, new_symmetry)
						undo_manager.add_undo_method(BetterTerrain, &"set_tile_symmetry_type", tileset, old_tile_part.data, old_symmetry)
					
				undo_manager.add_do_method(self, &"queue_redraw")
				undo_manager.add_undo_method(self, &"queue_redraw")
				undo_manager.commit_action()
			
			staged_paste_tile_states = []
			paint_mode = PaintMode.SELECT
			paint_action = PaintAction.SELECT
		return
	
	if clicked and pick_icon_terrain >= 0:
		highlighted_tile_part = tile_part_from_position(current_position)
		if !highlighted_tile_part.valid:
			return
		
		var t = BetterTerrain.get_terrain(tileset, paint)
		var prev_icon = t.icon.duplicate()
		var icon = {
			source_id = highlighted_tile_part.source_id,
			coord = highlighted_tile_part.coord
		}
		undo_manager.create_action("Edit terrain details", UndoRedo.MERGE_DISABLE, tileset)
		undo_manager.add_do_method(BetterTerrain, &"set_terrain", tileset, paint, t.name, t.color, t.type, t.categories, icon)
		undo_manager.add_do_method(self, &"emit_terrain_updated", paint)
		undo_manager.add_undo_method(BetterTerrain, &"set_terrain", tileset, paint, t.name, t.color, t.type, t.categories, prev_icon)
		undo_manager.add_undo_method(self, &"emit_terrain_updated", paint)
		undo_manager.commit_action()
		pick_icon_terrain = -1
		return
	
	if pick_icon_terrain_cancel:
		pick_icon_terrain = -1
		pick_icon_terrain_cancel = false
	
	if paint != BetterTerrain.TileCategory.NON_TERRAIN and clicked:
		paint_action = PaintAction.NO_ACTION
		if highlighted_tile_part.valid:
			match [paint_mode, event.button_index]:
				[PaintMode.PAINT_TYPE, MOUSE_BUTTON_LEFT]: paint_action = PaintAction.DRAW_TYPE
				[PaintMode.PAINT_TYPE, MOUSE_BUTTON_RIGHT]: paint_action = PaintAction.ERASE_TYPE
				[PaintMode.PAINT_PEERING, MOUSE_BUTTON_LEFT]: paint_action = PaintAction.DRAW_PEERING
				[PaintMode.PAINT_PEERING, MOUSE_BUTTON_RIGHT]: paint_action = PaintAction.ERASE_PEERING
				[PaintMode.PAINT_SYMMETRY, MOUSE_BUTTON_LEFT]: paint_action = PaintAction.DRAW_SYMMETRY
				[PaintMode.PAINT_SYMMETRY, MOUSE_BUTTON_RIGHT]: paint_action = PaintAction.ERASE_SYMMETRY
				[PaintMode.SELECT, MOUSE_BUTTON_LEFT]: paint_action = PaintAction.SELECT
				[PaintMode.PAINT_OBJECT_LONE, MOUSE_BUTTON_LEFT]: paint_action = PaintAction.DRAW_OBJECT_LONE
				[PaintMode.PAINT_OBJECT_JOINED, MOUSE_BUTTON_LEFT]: paint_action = PaintAction.DRAW_OBJECT_JOINED
				[PaintMode.PAINT_OBJECT_LONE, MOUSE_BUTTON_RIGHT]: paint_action = PaintAction.ERASE_OBJECT_BLOCK
				[PaintMode.PAINT_OBJECT_JOINED, MOUSE_BUTTON_RIGHT]: paint_action = PaintAction.ERASE_OBJECT_BLOCK
		else:
			match [paint_mode, event.button_index]:
				[PaintMode.SELECT, MOUSE_BUTTON_LEFT]: paint_action = PaintAction.SELECT
	
	if (clicked or event is InputEventMouseMotion) and paint_action != PaintAction.NO_ACTION:
		
		if paint_action == PaintAction.SELECT:
			if clicked:
				selection_start = Vector2i(-1,-1)
				queue_redraw()
			if selection_start.x < 0:
				selection_start = current_position
			selection_end = current_position
			
			selection_rect = Rect2i(selection_start, selection_end - selection_start).abs()
			var selected_tile_parts = tile_parts_from_rect(selection_rect)
			selected_tile_states = []
			for t in selected_tile_parts:
				var not_sides := []
				for side in range(16):
					if paint in BetterTerrain.tile_not_peering_types(t.data, side):
						not_sides.push_back(side)
				var state := {
					part = t,
					base_rect = Rect2(t.rect.position / zoom_level, t.rect.size / zoom_level),
					paint = paint,
					sides = BetterTerrain.tile_peering_for_type(t.data, paint),
					not_sides = not_sides,
					symmetry = BetterTerrain.get_tile_symmetry_type(t.data)
				}
				selected_tile_states.push_back(state)
		else:
			if !highlighted_tile_part.valid:
				return
			#slightly crude and non-optimal but way simpler than the "correct" solution
			var current_position_vec2 = Vector2(current_position)
			var prev_position_vec2 = Vector2(prev_position)
			var mouse_dist = current_position_vec2.distance_to(prev_position_vec2)
			var step_size = (tile_part_size.x * zoom_level)
			var steps = ceil(mouse_dist / step_size) + 1
			for i in range(steps):
				var t = float(i) / steps 
				var check_position = prev_position_vec2.lerp(current_position_vec2, t)
				highlighted_tile_part = tile_part_from_position(check_position)
			
				if !highlighted_tile_part.valid:
					continue
				
				if paint_action == PaintAction.DRAW_OBJECT_LONE or paint_action == PaintAction.DRAW_OBJECT_JOINED:
					_paint_object_block(paint_action == PaintAction.DRAW_OBJECT_LONE)
				elif paint_action == PaintAction.ERASE_OBJECT_BLOCK:
					_erase_object_block()
				elif paint_action == PaintAction.DRAW_TYPE or paint_action == PaintAction.ERASE_TYPE:
					var type := BetterTerrain.get_tile_terrain_type(highlighted_tile_part.data)
					var goal := paint if paint_action == PaintAction.DRAW_TYPE else BetterTerrain.TileCategory.NON_TERRAIN
					if type != goal:
						undo_manager.create_action("Set tile terrain type " + str(terrain_undo.action_index), UndoRedo.MERGE_ALL, tileset, true)
						terrain_undo.add_do_method(undo_manager, BetterTerrain, &"set_tile_terrain_type", [tileset, highlighted_tile_part.data, goal])
						terrain_undo.add_do_method(undo_manager, self, &"queue_redraw", [])
						if goal == BetterTerrain.TileCategory.NON_TERRAIN:
							terrain_undo.create_peering_restore_point_tile(
								undo_manager,
								tileset,
								highlighted_tile_part.source_id,
								highlighted_tile_part.coord,
								highlighted_tile_part.alternate
							)
						else:
							undo_manager.add_undo_method(BetterTerrain, &"set_tile_terrain_type", tileset, highlighted_tile_part.data, type)
						undo_manager.add_undo_method(self, &"queue_redraw")
						undo_manager.commit_action()
						terrain_undo.action_count += 1
				elif paint_action == PaintAction.DRAW_PEERING:
					if highlighted_tile_part.has("peering"):
						var td = highlighted_tile_part.data
						var side = highlighted_tile_part.peering
						var has_match = paint in BetterTerrain.tile_peering_types(td, side)
						var has_not = paint in BetterTerrain.tile_not_peering_types(td, side)
						if clicked and (has_match or has_not):
							# A click on a set side flips it between match and must-not-match
							var from_add := &"add_tile_peering_type" if has_match else &"add_tile_not_peering_type"
							var from_remove := &"remove_tile_peering_type" if has_match else &"remove_tile_not_peering_type"
							var to_add := &"add_tile_not_peering_type" if has_match else &"add_tile_peering_type"
							var to_remove := &"remove_tile_not_peering_type" if has_match else &"remove_tile_peering_type"
							undo_manager.create_action("Toggle tile terrain peering type " + str(terrain_undo.action_index), UndoRedo.MERGE_ALL, tileset, true)
							terrain_undo.add_do_method(undo_manager, BetterTerrain, from_remove, [tileset, td, side, paint])
							terrain_undo.add_do_method(undo_manager, BetterTerrain, to_add, [tileset, td, side, paint])
							terrain_undo.add_do_method(undo_manager, self, &"queue_redraw", [])
							undo_manager.add_undo_method(self, &"queue_redraw")
							undo_manager.add_undo_method(BetterTerrain, from_add, tileset, td, side, paint)
							undo_manager.add_undo_method(BetterTerrain, to_remove, tileset, td, side, paint)
							undo_manager.commit_action()
							terrain_undo.action_count += 1
							break
						elif !has_match and !has_not:
							undo_manager.create_action("Set tile terrain peering type " + str(terrain_undo.action_index), UndoRedo.MERGE_ALL, tileset, true)
							terrain_undo.add_do_method(undo_manager, BetterTerrain, &"add_tile_peering_type", [tileset, td, side, paint])
							terrain_undo.add_do_method(undo_manager, self, &"queue_redraw", [])
							undo_manager.add_undo_method(BetterTerrain, &"remove_tile_peering_type", tileset, td, side, paint)
							undo_manager.add_undo_method(self, &"queue_redraw")
							undo_manager.commit_action()
							terrain_undo.action_count += 1
							if clicked:
								break
				elif paint_action == PaintAction.ERASE_PEERING:
					if highlighted_tile_part.has("peering"):
						var td = highlighted_tile_part.data
						var side = highlighted_tile_part.peering
						var has_match = paint in BetterTerrain.tile_peering_types(td, side)
						var has_not = paint in BetterTerrain.tile_not_peering_types(td, side)
						if has_match or has_not:
							undo_manager.create_action("Remove tile terrain peering type " + str(terrain_undo.action_index), UndoRedo.MERGE_ALL, tileset, true)
							if has_match:
								terrain_undo.add_do_method(undo_manager, BetterTerrain, &"remove_tile_peering_type", [tileset, td, side, paint])
								undo_manager.add_undo_method(BetterTerrain, &"add_tile_peering_type", tileset, td, side, paint)
							if has_not:
								terrain_undo.add_do_method(undo_manager, BetterTerrain, &"remove_tile_not_peering_type", [tileset, td, side, paint])
								undo_manager.add_undo_method(BetterTerrain, &"add_tile_not_peering_type", tileset, td, side, paint)
							terrain_undo.add_do_method(undo_manager, self, &"queue_redraw", [])
							undo_manager.add_undo_method(self, &"queue_redraw")
							undo_manager.commit_action()
							terrain_undo.action_count += 1
				elif paint_action == PaintAction.DRAW_SYMMETRY:
					if paint == BetterTerrain.get_tile_terrain_type(highlighted_tile_part.data):
						undo_manager.create_action("Set tile symmetry type " + str(terrain_undo.action_index), UndoRedo.MERGE_ALL, tileset, true)
						var old_symmetry = BetterTerrain.get_tile_symmetry_type(highlighted_tile_part.data)
						terrain_undo.add_do_method(undo_manager, BetterTerrain, &"set_tile_symmetry_type", [tileset, highlighted_tile_part.data, paint_symmetry])
						terrain_undo.add_do_method(undo_manager, self, &"queue_redraw", [])
						undo_manager.add_undo_method(BetterTerrain, &"set_tile_symmetry_type", tileset, highlighted_tile_part.data, old_symmetry)
						undo_manager.add_undo_method(self, &"queue_redraw")
						undo_manager.commit_action()
						terrain_undo.action_count += 1
				elif paint_action == PaintAction.ERASE_SYMMETRY:
					if paint == BetterTerrain.get_tile_terrain_type(highlighted_tile_part.data):
						undo_manager.create_action("Remove tile symmetry type " + str(terrain_undo.action_index), UndoRedo.MERGE_ALL, tileset, true)
						var old_symmetry = BetterTerrain.get_tile_symmetry_type(highlighted_tile_part.data)
						terrain_undo.add_do_method(undo_manager, BetterTerrain, &"set_tile_symmetry_type", [tileset, highlighted_tile_part.data, BetterTerrain.SymmetryType.NONE])
						terrain_undo.add_do_method(undo_manager, self, &"queue_redraw", [])
						undo_manager.add_undo_method(BetterTerrain, &"set_tile_symmetry_type", tileset, highlighted_tile_part.data, old_symmetry)
						undo_manager.add_undo_method(self, &"queue_redraw")
						undo_manager.commit_action()
						terrain_undo.action_count += 1


func _on_zoom_value_changed(value) -> void:
	zoom_level = value
	custom_minimum_size.x = zoom_level * tiles_size.x
	if alternate_size.x > 0:
		custom_minimum_size.x += ALTERNATE_TILE_MARGIN + zoom_level * alternate_size.x
	custom_minimum_size.y = zoom_level * max(tiles_size.y, alternate_size.y)
	queue_redraw()


func _zoom_at_cursor(mouse_local: Vector2, factor: float) -> void:
	var old_zoom := zoom_level
	change_zoom_level.emit(old_zoom * factor)
	# The signal handler clamps and applies zoom_level before control returns.
	var new_zoom := zoom_level
	if is_equal_approx(new_zoom, old_zoom):
		return
	var ratio := new_zoom / old_zoom
	var scroll := get_parent() as ScrollContainer
	if scroll:
		var dx := mouse_local.x * (ratio - 1.0)
		var dy := mouse_local.y * (ratio - 1.0)
		scroll.scroll_horizontal += int(round(dx))
		scroll.scroll_vertical += int(round(dy))


func clear_highlighted_tile() -> void:
	highlighted_tile_part = { valid = false }
	queue_redraw()
