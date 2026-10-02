@tool
extends Control

const ObjectTerrain := preload("res://addons/better-tile-editor/ObjectTerrain.gd")
const ExemplarData := preload("res://addons/better-tile-editor/ExemplarData.gd")
const Collisions := preload("res://addons/better-tile-editor/editor/Collisions.gd")
const CustomData := preload("res://addons/better-tile-editor/editor/CustomData.gd")

signal paste_occurred
signal change_zoom_level(value)
signal terrain_updated(index)
signal tile_picked(source_id: int, origin: Vector2i, size: Vector2i)
## Right click in Single tile: the tile under the mouse (source -1 when none).
signal favorite_requested(source_id: int, coord: Vector2i, alternate: int)
signal tile_dropped(source_id: int, coord: Vector2i)
signal collision_marked(source_id: int, coord: Vector2i, solid: bool)
signal collision_stroke_ended
signal collision_copy_requested(source_id: int, coord: Vector2i)
signal collision_paste_requested(source_id: int, coord: Vector2i)
signal data_pick_requested(source_id: int, coord: Vector2i)
signal data_preset_key(index: int)

## Collisions tool: clicks mark tiles solid or clear, and each tile shows its polygons.
var collision_mode := false
## TileSet physics layer shown and painted, -1 when the tile set has none.
var collision_layer := -1
var collision_stroking := false
## Tells whether a left click takes the tile's collision shape instead (Stamp's picking).
var collision_pick_check: Callable
## Shape mode: a click or drag picks the tiles to open in the shape editor instead.
var collision_shape_mode := false
## Custom data tool; its clicks go through collision_mode. One view at a time: the tiles
## holding the whole brush (DATA_VIEW_MATCHES), nothing (DATA_VIEW_NONE) or one field (>= 0).
var data_mode := false
const DATA_VIEW_MATCHES := -1
const DATA_VIEW_NONE := -2
var data_view := DATA_VIEW_MATCHES
## The field the mouse rests on in the panel, shown instead of the view meanwhile.
var data_hover := -1
var data_brush := {}
## Tells whether a click takes the tile's fields instead: the picker's key, or the panel's picker.
var data_pick_check: Callable
## Inspect: clicks pick tiles; the selected ones, Vector3i(x, y, source), are outlined.
var data_inspect := false
var data_selected := {}
var data_color := Color(0.44, 0.73, 0.98)
## Numeric fields' ranges over the tile set, {field: Vector2(min, max)}, for the heatmap.
var data_ranges := {}
var _collision_solid := true

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
## Room above each atlas for its name, when more than one is shown.
const HEADER_HEIGHT := 20.0
const BAND_GAP := 6.0
## Room left where empty rows are cut out of an atlas.
const CUT_GAP := 14.0
## Shorter runs of empty rows stay: a row between drawings is spacing, not waste.
const MIN_CUT_ROWS := 2

## Leave out the atlases' empty space: trailing columns, trailing rows and runs of empty
## rows. A cell counts as empty with nothing drawn and no tile, so new art or tiles show up.
var trim_empty := true:
	set(value):
		trim_empty = value
		_on_zoom_value_changed(zoom_level)

## Where each shown atlas lands, in view pixels. Each segment is [texture y from, to, view y
## from the band's top]; cuts are the view y of the gaps between segments.
var _bands: Array[Dictionary] = []
var _content_height := 0.0
## Which cells of a texture have something drawn, {key: PackedByteArray}.
var _art_cache := {}

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


#region Layout

func _relayout() -> void:
	_bands.clear()
	tiles_size = Vector2.ZERO
	_content_height = 0.0
	if tileset == null:
		return
	var shown := []
	for s in tileset.get_source_count():
		var source_id := tileset.get_source_id(s)
		var source := tileset.get_source(source_id) as TileSetAtlasSource
		if source != null and source.texture != null and not source_id in disabled_sources:
			shown.append(source_id)
	var labelled := shown.size() > 1
	var y := 0.0
	for source_id: int in shown:
		var source := tileset.get_source(source_id) as TileSetAtlasSource
		var band := {
			source_id = source_id,
			source = source,
			label = source_label(source, source_id),
			header = y if labelled else -1.0,
			top = y + (HEADER_HEIGHT if labelled else 0.0),
		}
		_fill_band(band)
		_bands.append(band)
		y = band.top + band.height + BAND_GAP
		tiles_size.x = maxf(tiles_size.x, band.width)
	_content_height = maxf(0.0, y - BAND_GAP)
	tiles_size.y = _content_height / zoom_level


## The name an atlas goes by: its own, its texture's, or its file's, with its ID.
static func source_label(source: TileSetAtlasSource, source_id: int) -> String:
	var label := source.resource_name
	if label.is_empty() and source.texture != null:
		label = source.texture.resource_name
		if label.is_empty():
			label = source.texture.resource_path.get_file()
	return ("%s (ID: %d)" % [label, source_id]) if not label.is_empty() else "Atlas (ID: %d)" % source_id


func _fill_band(band: Dictionary) -> void:
	var source: TileSetAtlasSource = band.source
	var texture_size := Vector2(source.texture.get_size())
	band.width = texture_size.x
	band.segments = [[0.0, texture_size.y, 0.0]]
	band.cuts = []
	band.cut_bottom = false
	if trim_empty:
		_trim_band(band, texture_size)
	var last: Array = band.segments.back()
	band.height = last[2] + zoom_level * (last[1] - last[0])


func _trim_band(band: Dictionary, texture_size: Vector2) -> void:
	var source: TileSetAtlasSource = band.source
	var grid := source.get_atlas_grid_size()
	var art := _art_cells(source, grid)
	var rows := []
	var last_col := -1
	for y in grid.y:
		var used := false
		for x in grid.x:
			if art[y * grid.x + x] or source.get_tile_at_coords(Vector2i(x, y)) != Vector2i(-1, -1):
				used = true
				last_col = maxi(last_col, x)
		rows.append(used)
	if last_col < 0:
		return
	var step := Vector2(source.texture_region_size + source.separation)
	var margins := Vector2(source.margins)
	var right := margins.x + (last_col + 1) * step.x
	if right < texture_size.x:
		band.width = right
	var segments := []
	var from := 0.0
	var at := 0.0
	var row := 0
	while row < grid.y:
		if rows[row]:
			row += 1
			continue
		var end := row
		while end < grid.y and not rows[end]:
			end += 1
		var trailing := end == grid.y
		if trailing or end - row >= MIN_CUT_ROWS:
			var to := margins.y + row * step.y
			if to > from:
				segments.append([from, to, at])
				at += zoom_level * (to - from)
			if trailing:
				band.cut_bottom = true
				from = -1.0
				break
			band.cuts.append(at + CUT_GAP * 0.5)
			at += CUT_GAP
			from = margins.y + end * step.y
		row = end
	if from >= 0.0:
		segments.append([from, texture_size.y, at])
	band.segments = segments


func _art_cells(source: TileSetAtlasSource, grid: Vector2i) -> PackedByteArray:
	var texture := source.texture
	var key := "%d|%s|%s|%s" % [texture.get_instance_id(), source.texture_region_size, source.separation, source.margins]
	if _art_cache.has(key):
		return _art_cache[key]
	var cells := PackedByteArray()
	cells.resize(grid.x * grid.y)
	cells.fill(1)
	var image := texture.get_image()
	if image != null and image.detect_alpha() != Image.ALPHA_NONE:
		if image.is_compressed():
			image.decompress()
		var step := source.texture_region_size + source.separation
		for y in grid.y:
			for x in grid.x:
				var region := Rect2i(source.margins + Vector2i(x, y) * step, source.texture_region_size)
				cells[y * grid.x + x] = 0 if image.get_region(region).is_invisible() else 1
	_art_cache[key] = cells
	if not texture.changed.is_connected(_on_texture_changed):
		texture.changed.connect(_on_texture_changed)
	return cells


# New art in a texture may fill space that was cut.
func _on_texture_changed() -> void:
	_art_cache.clear()
	_on_zoom_value_changed(zoom_level)


func _band_of(source_id: int) -> Dictionary:
	for band in _bands:
		if band.source_id == source_id:
			return band
	return {}


func _segment_at(band: Dictionary, texture_y: float) -> Array:
	var found: Array = band.segments[0]
	for segment: Array in band.segments:
		if segment[0] <= texture_y:
			found = segment
	return found


## A point of an atlas texture in the view.
func _texture_point(band: Dictionary, p: Vector2) -> Vector2:
	var segment := _segment_at(band, p.y)
	var y := clampf(p.y, segment[0], segment[1])
	return Vector2(zoom_level * p.x, band.top + segment[2] + zoom_level * (y - segment[0]))


## A texture rect in the view, or an empty Rect2 when it lies in cut space.
func _texture_rect(band: Dictionary, r: Rect2) -> Rect2:
	var segment := _segment_at(band, r.position.y)
	if r.position.y >= segment[1] or r.position.x >= band.width:
		return Rect2()
	return Rect2(_texture_point(band, r.position), zoom_level * r.size)


## The view rect of a texture rect of an atlas, as drawn; empty when not shown.
func atlas_rect(source_id: int, r: Rect2) -> Rect2:
	var band := _band_of(source_id)
	return Rect2() if band.is_empty() else _texture_rect(band, r)


## The atlas and texture point under a view position: {band, point}, or {} off every atlas.
func _texture_at(pos: Vector2) -> Dictionary:
	for band in _bands:
		if pos.x < 0.0 or pos.x >= zoom_level * band.width:
			continue
		var local: float = pos.y - band.top
		for segment: Array in band.segments:
			if local >= segment[2] and local < segment[2] + zoom_level * (segment[1] - segment[0]):
				return {band = band, point = Vector2(pos.x / zoom_level, segment[0] + (local - segment[2]) / zoom_level)}
	return {}


func _draw_band_frame(band: Dictionary) -> void:
	var font := get_theme_default_font()
	var muted := get_theme_color("font_color", "Label")
	muted.a = 0.6
	if band.header >= 0.0:
		var font_size := maxi(9, get_theme_default_font_size() - 3)
		var label: String = band.label
		var baseline: float = band.header + HEADER_HEIGHT * 0.5 + font_size * 0.35
		draw_string(font, Vector2(2, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, muted)
		var after := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 8.0
		var line_y: float = band.header + HEADER_HEIGHT * 0.5
		if size.x > after:
			draw_line(Vector2(after, line_y), Vector2(size.x, line_y), muted, 1.0)
	var right: float = zoom_level * band.width
	for cut: float in band.cuts:
		_draw_cut(Vector2(0, band.top + cut), Vector2(right, band.top + cut), muted)
	if band.cut_bottom:
		var bottom: float = band.top + band.height + 2.0
		_draw_cut(Vector2(0, bottom), Vector2(right, bottom), muted)


# A wavy line, like a scissor cut: what was here is empty and left out.
func _draw_cut(from: Vector2, to: Vector2, colour: Color) -> void:
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var along := (to - from) / length
	var across := Vector2(-along.y, along.x)
	var points := PackedVector2Array()
	var steps := int(length / 2.0)
	for i in steps + 1:
		var d := length * i / maxf(1.0, steps)
		points.append(from + along * d + across * 2.0 * sin(d * TAU / 10.0))
	draw_polyline(points, Color(0, 0, 0, 0.45), 3.0)
	draw_polyline(points, colour, 1.0)

#endregion


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
	var hit := _texture_at(pos)
	if hit.is_empty():
		return {}
	var source: TileSetAtlasSource = hit.band.source
	var step := Vector2(source.texture_region_size + source.separation)
	var coord := Vector2i(((hit.point - Vector2(source.margins)) / step).floor())
	var grid := source.get_atlas_grid_size()
	if coord.x < 0 or coord.y < 0 or coord.x >= grid.x or coord.y >= grid.y:
		return {}
	return {source_id = hit.band.source_id, coord = coord}


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
		var hit := _texture_at(Vector2(pos))
		if not hit.is_empty():
			var band: Dictionary = hit.band
			var source_id: int = band.source_id
			var source: TileSetAtlasSource = band.source
			for t in source.get_tiles_count():
				var coord := source.get_tile_id(t)
				var rect := source.get_tile_texture_region(coord, 0)
				if not Rect2(rect).has_point(hit.point):
					continue
				var target_rect := _texture_rect(band, rect)
				
				var result := {
					valid = true,
					source_id = source_id,
					coord = coord,
					alternate = 0,
					data = source.get_tile_data(coord, 0)
				}
				_build_tile_part_from_position(result, pos, target_rect)
				return result
	
	return { valid = false }


func tile_rect_from_position(pos: Vector2i) -> Rect2:
	if !tileset:
		return Rect2(-1,-1,0,0)
	
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
		var hit := _texture_at(Vector2(pos))
		if not hit.is_empty():
			var source: TileSetAtlasSource = hit.band.source
			for t in source.get_tiles_count():
				var rect := source.get_tile_texture_region(source.get_tile_id(t), 0)
				if Rect2(rect).has_point(hit.point):
					return _texture_rect(hit.band, rect)
	
	return Rect2(-1,-1,0,0)


func tile_parts_from_rect(rect:Rect2) -> Array[Dictionary]:
	if !tileset:
		return []
	
	var tiles:Array[Dictionary] = []
	
	var alt_offset := Vector2.RIGHT * (zoom_level * tiles_size.x + ALTERNATE_TILE_MARGIN)
	for band in _bands:
		var source_id: int = band.source_id
		var source: TileSetAtlasSource = band.source
		for t in source.get_tiles_count():
			var coord := source.get_tile_id(t)
			var tile_rect := source.get_tile_texture_region(coord, 0)
			var target_rect := _texture_rect(band, tile_rect)
			if target_rect.has_area() and target_rect.intersects(rect):
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
	return collision_stroking or paint_action in [PaintAction.DRAW_TYPE, PaintAction.ERASE_TYPE,
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

	if not show_terrain_marks or collision_mode:
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


var collision_mesh := Collisions.new_mesh()
var collision_color := Collisions.DEFAULT_OVERLAY_COLOR


func _draw() -> void:
	collision_mesh = Collisions.new_mesh()
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
	
	for entry in _bands:
		var source_id: int = entry.source_id
		var source: TileSetAtlasSource = entry.source
		if not is_instance_valid(source) or source.texture == null:
			continue
		for segment: Array in entry.segments:
			RenderingServer.canvas_item_add_texture_rect(
				_canvas_item_background,
				Rect2(0, entry.top + segment[2], zoom_level * entry.width, zoom_level * (segment[1] - segment[0])),
				checkerboard.get_rid(),
				true
			)
		_draw_band_frame(entry)
		var band := Rect2(0, entry.top, zoom_level * entry.width, entry.height)
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
					target_rect = _texture_rect(entry, rect)
					if not target_rect.has_area():
						continue
				else:
					target_rect = Rect2(alt_offset + zoom_level * (a - 1) * rect.size.x * Vector2.RIGHT, zoom_level * rect.size)
					alt_id = source.get_alternative_tile_id(coord, a)
				
				if cull and not window.intersects(target_rect):
					continue
				var td := source.get_tile_data(coord, alt_id)
				var drawing_current = BetterTerrain.get_tile_terrain_type(td) == paint and not collision_mode
				if paint_mode == PaintMode.PAINT_SYMMETRY and not collision_mode:
					_draw_tile_symmetry(source.texture, target_rect, rect, td, drawing_current)
				else:
					_draw_tile_data(source.texture, target_rect, rect, td)
				if data_mode:
					_draw_data_marks(td, target_rect, Vector3i(coord.x, coord.y, source_id))
				if collision_mode and collision_layer >= 0:
					var center := target_rect.get_center() + Vector2(td.texture_origin) * zoom_level
					for polygon: PackedVector2Array in Collisions.cell_polygons(td, collision_layer):
						var shown := PackedVector2Array()
						for v in polygon:
							shown.append(center + v * zoom_level)
						Collisions.add_to_mesh(collision_mesh, shown, collision_color)
				
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
		
		_draw_exemplar_outline(entry)
		_draw_marked_blocks(entry)
		if band_seen:
			_draw_blank_cells(entry, window if cull else Rect2())
	
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
	if not collision_mesh.indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), collision_mesh.indices,
			collision_mesh.points, collision_mesh.colors)
	collision_mesh = Collisions.new_mesh()

	if collision_mode:
		if highlighted_tile_part.valid:
			var r: Rect2 = highlighted_tile_part.rect
			draw_rect(Rect2(r.position + Vector2.ONE, r.size - 2 * Vector2.ONE), Color.WHITE, false)
		return

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


# Grid lines, and a dark cover over cells that are not tiles.
func _draw_blank_cells(band: Dictionary, window: Rect2) -> void:
	var source: TileSetAtlasSource = band.source
	var grid_size := source.get_atlas_grid_size()
	var step := Vector2(source.separation + source.texture_region_size)
	var margins := Vector2(source.margins)
	var cell := zoom_level * Vector2(source.texture_region_size)
	var columns := mini(grid_size.x, int(ceil((band.width - margins.x) / step.x)))
	for segment: Array in band.segments:
		var top: float = band.top + segment[2]
		var from_y: float = segment[0]
		var to_y: float = segment[1]
		var from_x := 0.0
		var to_x: float = band.width
		if window.size != Vector2.ZERO:
			from_y = maxf(from_y, segment[0] + (window.position.y - top) / zoom_level)
			to_y = minf(to_y, segment[0] + (window.end.y - top) / zoom_level)
			from_x = maxf(0.0, window.position.x / zoom_level)
			to_x = minf(to_x, window.end.x / zoom_level)
			if from_y >= to_y or from_x >= to_x:
				continue
		var rows := Vector2i(maxi(0, int(floor((from_y - margins.y) / step.y))),
			mini(grid_size.y, int(ceil((to_y - margins.y) / step.y)) + 1))
		var cols := Vector2i(maxi(0, int(floor((from_x - margins.x) / step.x))),
			mini(columns, int(ceil((to_x - margins.x) / step.x)) + 1))
		for y in range(rows.x, rows.y):
			var cell_y: float = margins.y + y * step.y
			if cell_y < segment[0] or cell_y >= segment[1]:
				continue
			for x in range(cols.x, cols.y):
				var pos := Vector2i(x, y)
				var r := Rect2(Vector2(zoom_level * (margins.x + x * step.x), top + zoom_level * (cell_y - segment[0])), cell)
				if show_grid:
					draw_rect(r, Color(0.75, 0.8, 0.85, 0.28), false, 1.0)
				if !is_tile_in_source(source, pos):
					draw_rect(r, Color(0.0, 0.0, 0.0, 0.8), true)


func _draw_marked_blocks(band: Dictionary) -> void:
	if marked_blocks.is_empty() and not pick_tiles:
		return
	var source: TileSetAtlasSource = band.source
	var source_id: int = band.source_id
	var cell := Vector2(source.texture_region_size)
	var step := Vector2(source.texture_region_size + source.separation)
	var at := func(c: Vector2i) -> Vector2:
		return _texture_point(band, Vector2(source.margins) + Vector2(c) * step)
	# Spans of cells, so a block crossing a cut still covers both sides of it.
	var span := func(lo: Vector2i, hi: Vector2i) -> Rect2:
		var start: Vector2 = at.call(lo)
		return Rect2(start, at.call(hi) + zoom_level * cell - start)

	for e in marked_blocks:
		if single_tile_favorites and _pick_from.x >= 0:
			continue
		if int(e.source) != source_id:
			continue
		var r: Rect2 = span.call(e.origin, e.origin + e.size - Vector2i.ONE)
		if single_tile_favorites:
			# White, on a black edge so it reads over light art too.
			draw_rect(r.grow(-2), Color(0, 0, 0, 0.85), false, 3.5)
			draw_rect(r.grow(-2), Color.WHITE, false, 1.5)
			continue
		draw_rect(r.grow(-1), Color(0, 0, 0, 0.55), false, 3.0)
		draw_rect(r.grow(-1), mark_colour, false, 1.5)

	if pick_tiles and _pick_from.x >= 0 and _pick_source == source_id:
		var to := _pick_target()
		var lo := Vector2i(mini(_pick_from.x, to.x), mini(_pick_from.y, to.y))
		var hi := Vector2i(maxi(_pick_from.x, to.x), maxi(_pick_from.y, to.y))
		var box: Rect2 = span.call(lo, hi)
		if single_tile_favorites and hi == lo:
			draw_rect(box.grow(-1), Color.WHITE, false, 1.5)
			return
		draw_rect(box, Color(1.0, 1.0, 1.0, 0.12))
		draw_rect(box, Color(1.0, 0.95, 0.4), false, 2.0)


func _draw_exemplar_outline(band: Dictionary) -> void:
	if tileset == null or paint < 0:
		return
	var t := BetterTerrain.get_terrain(tileset, paint)
	if not t.valid or t.type != BetterTerrain.TerrainType.EXEMPLAR:
		return
	var source: TileSetAtlasSource = band.source
	var source_id: int = band.source_id
	var cell := Vector2(source.texture_region_size)
	var step := Vector2(source.texture_region_size + source.separation)
	var at := func(c: Vector2i) -> Vector2:
		return _texture_point(band, Vector2(source.margins) + Vector2(c) * step)
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
	_on_zoom_value_changed(zoom_level)


func emit_terrain_updated(index):
	terrain_updated.emit(index)


## Disable atlas cut shortcuts while the map selection tool owns them.
var shortcuts_blocked := false


func _gui_input(event) -> void:
	if collision_mode and _collision_input(event):
		return
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
				var hovered := tile_part_from_position(event.position)
				if hovered.valid:
					favorite_requested.emit(hovered.source_id, hovered.coord, hovered.alternate)
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


## Left drags mark tiles solid, right drags clear them; zoom and panning fall through.
func _collision_input(event: InputEvent) -> bool:
	# Keys are kept from the terrain shortcuts below, but only the ones used here are taken:
	# the rest, Ctrl+Z included, go on to the editor.
	if event is InputEventKey and data_mode:
		if event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode <= KEY_9 \
				and not event.is_command_or_control_pressed():
			data_preset_key.emit(event.keycode - KEY_1)
			accept_event()
		return true
	if event is InputEventKey:
		if event.pressed and not event.echo and event.is_command_or_control_pressed() and highlighted_tile_part.valid:
			if event.keycode == KEY_C:
				collision_copy_requested.emit(highlighted_tile_part.source_id, highlighted_tile_part.coord)
				accept_event()
			elif event.keycode == KEY_V:
				collision_paste_requested.emit(highlighted_tile_part.source_id, highlighted_tile_part.coord)
				accept_event()
		return true
	if collision_shape_mode or data_inspect:
		return false
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		accept_event()
		if not data_mode and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
				and collision_pick_check.is_valid() and collision_pick_check.call(event):
			var taken := tile_part_from_position(event.position)
			if taken.valid:
				collision_copy_requested.emit(taken.source_id, taken.coord)
			return true
		if data_mode and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
				and data_pick_check.is_valid() and data_pick_check.call(event):
			var picked := tile_part_from_position(event.position)
			if picked.valid:
				data_pick_requested.emit(picked.source_id, picked.coord)
			return true
		if event.pressed:
			collision_stroking = true
			_collision_solid = event.button_index == MOUSE_BUTTON_LEFT
			prev_position = event.position
			_collision_touch(event.position, event.position)
		elif collision_stroking:
			collision_stroking = false
			collision_stroke_ended.emit()
		return true
	if event is InputEventMouseMotion and not _panning:
		var part := tile_part_from_position(event.position)
		if part.valid != highlighted_tile_part.valid or (part.valid and part.data != highlighted_tile_part.data):
			queue_redraw()
		highlighted_tile_part = part
		if collision_stroking:
			if event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT) == 0:
				collision_stroking = false
				collision_stroke_ended.emit()
			else:
				_collision_touch(prev_position, event.position)
		prev_position = event.position
		return true
	return false


## Custom data overlay: badges per set field; a shown field lights its tiles, the brush outlines
## its matches, the Inspect selection is outlined thick.
func _draw_data_marks(td: TileData, rect: Rect2, key: Vector3i) -> void:
	var field := data_hover if data_hover >= 0 else data_view
	if field >= 0 and field < tileset.get_custom_data_layers_count():
		var value: Variant = td.get_custom_data_by_layer_id(field)
		if CustomData.is_set(value, tileset.get_custom_data_layer_type(field)):
			var lit := CustomData.heat(float(value), data_ranges[field]) if data_ranges.has(field) else data_color
			draw_rect(rect, Color(lit, 0.45 if data_ranges.has(field) else 0.3))
			draw_rect(rect.grow(-1), lit, false, 2.0)
			_draw_centered(CustomData.label(tileset, td, field), rect)
		else:
			draw_rect(rect, Color(0, 0, 0, 0.6))
	elif data_view == DATA_VIEW_MATCHES and CustomData.matches(td, data_brush):
		draw_rect(rect, Color(data_color, 0.25))
		draw_rect(rect.grow(-1), data_color, false, 2.0)
	if data_inspect and data_selected.has(key):
		draw_rect(rect.grow(-1), Color.WHITE, false, 3.0)


## Text in the middle of a tile, outlined so it reads on any art; shrunk to fit.
func _draw_centered(text: String, rect: Rect2) -> void:
	var font := get_theme_font("font", "Label")
	var font_size := 12
	while font_size > 7 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > rect.size.x - 2:
		font_size -= 1
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var at := rect.get_center() + Vector2(-minf(text_size.x, rect.size.x - 2) * 0.5, font.get_ascent(font_size) * 0.5 - 1)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 2, font_size, 3, Color.BLACK)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 2, font_size, Color.WHITE)


func _get_tooltip(at_position: Vector2) -> String:
	if not data_mode or tileset == null:
		return tooltip_text
	var part := tile_part_from_position(at_position)
	if not part.valid:
		return ""
	return "Tile %s%s\n%s" % [str(part.coord), "" if part.alternate == 0 else " (alternative %d)" % part.alternate,
		CustomData.describe(tileset, part.data)]


func _collision_touch(from: Vector2, to: Vector2) -> void:
	var steps := int(ceil(from.distance_to(to) / maxf(1.0, tile_part_size.x * zoom_level))) + 1
	var seen := {}
	for i in steps:
		var part := tile_part_from_position(from.lerp(to, float(i) / steps) if steps > 1 else to)
		if not part.valid:
			continue
		var key := Vector3i(part.coord.x, part.coord.y, part.source_id)
		if seen.has(key):
			continue
		seen[key] = true
		collision_marked.emit(part.source_id, part.coord, _collision_solid)


func _on_zoom_value_changed(value) -> void:
	zoom_level = value
	_relayout()
	custom_minimum_size.x = zoom_level * tiles_size.x
	if alternate_size.x > 0:
		custom_minimum_size.x += ALTERNATE_TILE_MARGIN + zoom_level * alternate_size.x
	custom_minimum_size.y = maxf(_content_height + 6.0, zoom_level * alternate_size.y)
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
