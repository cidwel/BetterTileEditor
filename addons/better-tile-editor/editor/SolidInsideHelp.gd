@tool
extends AcceptDialog
## Shows "Solid inside groups" on the terrain's own drawing: a group of objects with its
## collisions, with the option off and on.

const ObjectTerrain := preload("res://addons/better-tile-editor/ObjectTerrain.gd")

const GROUP := Vector2i(2, 3)
const SHAPE_FILL := Color(1.0, 0.25, 0.25, 0.45)
const SHAPE_LINE := Color(1.0, 0.4, 0.4)

var _src: TileSetAtlasSource
var _cells := {}
var _covered := {}
var _zoom := 3.0
var _has_physics := false


func setup(ts: TileSet, terrain_id: int) -> void:
	title = "Solid inside groups"
	_has_physics = ts.get_physics_layers_count() > 0
	ok_button_text = "Close"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var text := Label.new()
	text.text = "Off, each object keeps its own collision, so a group of them has notches\n" \
		+ "on its sides. On, an object with another one right above it gets a whole-tile\n" \
		+ "top row: the group is solid and only its north edge keeps the drawing's shape."
	box.add_child(text)
	if not _lay_out(ts, terrain_id):
		var missing := Label.new()
		missing.text = "Mark the object's drawing to see it here with your own tiles."
		box.add_child(missing)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	box.add_child(row)
	for on in [false, true]:
		var col := VBoxContainer.new()
		row.add_child(col)
		var caption := Label.new()
		caption.text = "On" if on else "Off"
		col.add_child(caption)
		var canvas := Control.new()
		canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		canvas.custom_minimum_size = Vector2(_src.texture_region_size * _extent()) * _zoom
		canvas.draw.connect(_draw_group.bind(canvas, on))
		col.add_child(canvas)


## Builds the group on a scratch layer the way painting does, with the option off.
func _lay_out(ts: TileSet, terrain_id: int) -> bool:
	var o := {}
	for found in ObjectTerrain.get_objects(ts):
		if found["id"] == terrain_id:
			o = found.duplicate()
	if o.is_empty():
		return false
	o["solid_inside"] = false
	var size: Vector2i = o["size"]
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	var source := -1
	for id_index in ts.get_source_count():
		var sid := ts.get_source_id(id_index)
		var src := ts.get_source(sid) as TileSetAtlasSource
		if src != null and src.has_tile(o["closed"]) and ObjectTerrain.texture_name(ts, sid) == o["atlas"]:
			source = sid
			_src = src
			break
	if source < 0:
		layer.free()
		return false
	for by in GROUP.y:
		for bx in GROUP.x:
			for c in ObjectTerrain.cells_of(size):
				layer.set_cell(Vector2i(bx, by) * size + c["off"], source, o["closed"] + c["off"])
	var objects := [o]
	for by in GROUP.y:
		for bx in GROUP.x:
			ObjectTerrain._rebuild(layer, Vector2i(bx, by) * size, o, objects)
	for cell in layer.get_used_cells():
		_cells[cell] = layer.get_cell_atlas_coords(cell)
		_covered[cell] = cell.y % size.y == 0 and cell.y >= size.y
	layer.free()
	_zoom = clampf(floorf(300.0 / (_src.texture_region_size.y * _extent().y)), 1.0, 4.0)
	return true


func _extent() -> Vector2i:
	var most := Vector2i.ZERO
	for cell: Vector2i in _cells:
		most = Vector2i(maxi(most.x, cell.x + 1), maxi(most.y, cell.y + 1))
	return most


func _draw_group(canvas: Control, on: bool) -> void:
	var tile := Vector2(_src.texture_region_size) * _zoom
	for cell: Vector2i in _cells:
		var where := Rect2(Vector2(cell) * tile, tile)
		canvas.draw_texture_rect_region(_src.texture, where, _src.get_tile_texture_region(_cells[cell]))
	for cell: Vector2i in _cells:
		var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * tile
		var shapes := []
		var data := _src.get_tile_data(_cells[cell], 0)
		var count := data.get_collision_polygons_count(0) if _has_physics else 0
		if count == 0:
			continue
		if on and _covered[cell]:
			var half := tile / 2.0
			shapes.append(PackedVector2Array([-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]))
		else:
			for i in count:
				var points := PackedVector2Array()
				for p in data.get_collision_polygon_points(0, i):
					points.append(p * _zoom)
				shapes.append(points)
		for shape: PackedVector2Array in shapes:
			var moved := Transform2D(0.0, centre) * shape
			canvas.draw_colored_polygon(moved, SHAPE_FILL)
			moved.append(moved[0])
			canvas.draw_polyline(moved, SHAPE_LINE, 1.0)
