extends SceneTree
## Builds the demo tilesets (.tres) and scenes in addons/better-tile-editor/demos from the
## atlases that make_demo_art.py draws. Run it through tools/demos/build.sh.

const DIR := "res://addons/better-tile-editor/demos/"
const SIDES := {"r": 0, "br": 3, "b": 4, "bl": 7, "l": 8, "tl": 11, "t": 12, "tr": 15}
const BLOB_SIDES := {
	"tl": ["r", "b", "br"], "t": ["l", "r", "b", "bl", "br"], "tr": ["l", "b", "bl"],
	"l": ["t", "b", "r", "tr", "br"], "c": ["r", "br", "b", "bl", "l", "tl", "t", "tr"],
	"r": ["t", "b", "l", "tl", "bl"], "bl": ["r", "t", "tr"], "b": ["l", "r", "t", "tl", "tr"],
	"br": ["l", "t", "tl"],
	"itl": ["r", "br", "b", "bl", "l", "t", "tr"], "itr": ["r", "br", "b", "bl", "l", "tl", "t"],
	"ibl": ["r", "br", "b", "l", "tl", "t", "tr"], "ibr": ["r", "b", "bl", "l", "tl", "t", "tr"],
	"one": [],
}
const ScatterTerrain := preload("res://addons/better-tile-editor/ScatterTerrain.gd")
const ObjectTerrain := preload("res://addons/better-tile-editor/ObjectTerrain.gd")
const ExemplarData := preload("res://addons/better-tile-editor/ExemplarData.gd")
const ExemplarTerrain := preload("res://addons/better-tile-editor/ExemplarTerrain.gd")
const CliffData := preload("res://addons/better-tile-editor/CliffData.gd")
const CliffPattern := preload("res://addons/better-tile-editor/CliffPattern.gd")
const CliffTerrain := preload("res://addons/better-tile-editor/CliffTerrain.gd")
const SlopeTerrain := preload("res://addons/better-tile-editor/SlopeTerrain.gd")

var bt


func _init() -> void:
	await process_frame
	bt = root.get_node("BetterTerrain")
	var only := OS.get_environment("DEMO")
	for demo in ["match_tiles", "match_vertices", "categories", "decoration", "objects", "forest", "patch",
			"scatter", "single_tile", "cliffs", "slopes"]:
		if only.is_empty() or only == demo:
			call("_build_" + demo)
	quit()



func _layout(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DIR + "tilesets/" + name + ".json"))


func _tileset(name: String) -> Array:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var src := TileSetAtlasSource.new()
	src.texture = load(DIR + "tilesets/" + name + ".png")
	src.texture_region_size = Vector2i(16, 16)
	ts.add_source(src, 0)
	var layout := _layout(name)
	# Larger pieces are split into 1x1 tiles, as objects, patches and cliffs expect
	for piece in layout:
		var r: Array = layout[piece]
		for y in r[3]:
			for x in r[2]:
				src.create_tile(Vector2i(r[0] + x, r[1] + y))
	return [ts, src, layout]


func _td(src: TileSetAtlasSource, layout: Dictionary, piece: String) -> TileData:
	return src.get_tile_data(Vector2i(layout[piece][0], layout[piece][1]), 0)


func _terrain(ts: TileSet, name: String, color: Color, type: int, categories := []) -> int:
	bt.add_terrain(ts, name, color, type, categories)
	return bt.terrain_count(ts) - 1


# A blob-lite set: each piece peers on its sides to [param target]
func _blob(ts: TileSet, src, layout: Dictionary, terrain: int, target: int, prefix := "") -> void:
	for piece in BLOB_SIDES:
		var td := _td(src, layout, prefix + piece)
		bt.set_tile_terrain_type(ts, td, terrain)
		for side in BLOB_SIDES[piece]:
			bt.add_tile_peering_type(ts, td, SIDES[side], target)


func _fill_terrain(ts: TileSet, src, layout: Dictionary, piece: String, name: String, color: Color) -> int:
	var id := _terrain(ts, name, color, bt.TerrainType.MATCH_TILES)
	bt.set_tile_terrain_type(ts, _td(src, layout, piece), id)
	return id


func _save_tileset(ts: TileSet, name: String) -> TileSet:
	ResourceSaver.save(ts, DIR + "tilesets/" + name + ".tres")
	return load(DIR + "tilesets/" + name + ".tres")


func _scene(name: String) -> Node2D:
	var scene := Node2D.new()
	scene.name = name
	root.add_child(scene)
	return scene


func _layer(scene: Node, name: String, ts: TileSet) -> TileMapLayer:
	var tm := TileMapLayer.new()
	tm.name = name
	tm.tile_set = ts
	scene.add_child(tm)
	return tm


func _note(scene: Node, text: String) -> void:
	var label := Label.new()
	label.name = "About"
	label.position = Vector2(0, -64)
	label.add_theme_font_size_override("font_size", 8)
	label.text = text
	scene.add_child(label)


func _cells(rects: Array, holes := []) -> Array:
	var out := {}
	for r: Rect2i in rects:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				out[Vector2i(x, y)] = true
	for r: Rect2i in holes:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				out.erase(Vector2i(x, y))
	return out.keys()


func _paint(tm: TileMapLayer, cells: Array, terrain: int) -> void:
	bt.set_cells(tm, cells, terrain)
	bt.update_terrain_cells(tm, cells)


func _save_scene(scene: Node, file: String) -> void:
	# Painting can add tiles (the forest marker), so tilesets are saved again
	for tm in scene.find_children("*", "TileMapLayer", true, false):
		if not tm.tile_set.resource_path.is_empty():
			ResourceSaver.save(tm.tile_set, tm.tile_set.resource_path)
	_own(scene, scene)
	var ps := PackedScene.new()
	ps.pack(scene)
	print(file, " ", ResourceSaver.save(ps, DIR + file))
	scene.queue_free()


func _own(node: Node, owner: Node) -> void:
	for c in node.get_children():
		c.owner = owner
		_own(c, owner)


const GROUND_AREA := Rect2i(0, 0, 32, 18)
const ISLAND := [Rect2i(2, 2, 12, 7), Rect2i(6, 9, 6, 5), Rect2i(16, 3, 12, 11), Rect2i(14, 6, 2, 3)]
const ISLAND_HOLES := [Rect2i(20, 7, 4, 3), Rect2i(2, 2, 3, 2)]



func _build_match_tiles() -> void:
	var made := _tileset("match_tiles")
	var ts: TileSet = made[0]
	var dirt := _fill_terrain(ts, made[1], made[2], "dirt", "Dirt", Color(0.6, 0.45, 0.3))
	var grass := _terrain(ts, "Grass", Color(0.4, 0.7, 0.25), bt.TerrainType.MATCH_TILES)
	_blob(ts, made[1], made[2], grass, grass)
	ts = _save_tileset(ts, "match_tiles")
	var scene := _scene("MatchTiles")
	_paint(_layer(scene, "Dirt", ts), _cells([GROUND_AREA]), dirt)
	_paint(_layer(scene, "Grass", ts), _cells(ISLAND, ISLAND_HOLES), grass)
	_note(scene, "Match Tiles: each grass tile says which of its sides and corners continue as grass.\n"
		+ "Select the Grass layer, pick Grass in Better Tile Editor and paint: edges and corners follow.")
	_save_scene(scene, "01_match_tiles.tscn")


func _build_match_vertices() -> void:
	var made := _tileset("match_vertices")
	var ts: TileSet = made[0]
	var src: TileSetAtlasSource = made[1]
	var layout: Dictionary = made[2]
	var sand := _fill_terrain(ts, src, layout, "sand", "Sand", Color(0.85, 0.78, 0.55))
	var water := _terrain(ts, "Water", Color(0.3, 0.5, 0.85), bt.TerrainType.MATCH_VERTICES)
	var corners := [11, 15, 7, 3]  # tl tr bl br, the order the piece names use
	for piece in layout:
		if not piece.begins_with("v_"):
			continue
		var td := _td(src, layout, piece)
		bt.set_tile_terrain_type(ts, td, water)
		for i in 4:
			if piece[2 + i] == "#":
				bt.add_tile_peering_type(ts, td, corners[i], water)
	ts = _save_tileset(ts, "match_vertices")
	var scene := _scene("MatchVertices")
	_paint(_layer(scene, "Sand", ts), _cells([GROUND_AREA]), sand)
	_paint(_layer(scene, "Water", ts), _cells([Rect2i(3, 3, 9, 6), Rect2i(6, 9, 4, 4), Rect2i(18, 4, 3, 3),
		Rect2i(21, 7, 3, 3), Rect2i(24, 10, 4, 4), Rect2i(14, 12, 2, 2)]), water)
	_note(scene, "Match Vertices: each water tile says which of its four corners are water, so terrains\n"
		+ "meet at the corners. Pick Water and paint on the Water layer.")
	_save_scene(scene, "02_match_vertices.tscn")


func _build_categories() -> void:
	var made := _tileset("categories")
	var ts: TileSet = made[0]
	var dirt := _fill_terrain(ts, made[1], made[2], "dirt", "Dirt", Color(0.6, 0.45, 0.3))
	var lawn := _terrain(ts, "Lawn", Color(0.5, 0.6, 0.4), bt.TerrainType.CATEGORY)
	var grass := _terrain(ts, "Grass", Color(0.4, 0.7, 0.25), bt.TerrainType.MATCH_TILES, [lawn])
	var lush := _terrain(ts, "Lush grass", Color(0.25, 0.55, 0.3), bt.TerrainType.MATCH_TILES, [lawn])
	# Both peer to the category, so they meet with no edge between them
	_blob(ts, made[1], made[2], grass, lawn)
	_blob(ts, made[1], made[2], lush, lawn, "lush_")
	ts = _save_tileset(ts, "categories")
	var scene := _scene("Categories")
	_paint(_layer(scene, "Dirt", ts), _cells([GROUND_AREA]), dirt)
	var ground := _layer(scene, "Lawn", ts)
	var all := _cells(ISLAND, ISLAND_HOLES)
	var lush_cells := all.filter(func(c): return c.x >= 16 or (c.x >= 8 and c.y >= 8))
	bt.set_cells(ground, all.filter(func(c): return not c in lush_cells), grass)
	bt.set_cells(ground, lush_cells, lush)
	bt.update_terrain_cells(ground, all)
	_note(scene, "Categories: Grass and Lush grass both belong to the Lawn category and peer to it,\n"
		+ "so where they meet there is no edge, only where the lawn meets the dirt.")
	_save_scene(scene, "03_categories.tscn")


func _build_decoration() -> void:
	var made := _tileset("decoration")
	var ts: TileSet = made[0]
	var src: TileSetAtlasSource = made[1]
	var layout: Dictionary = made[2]
	var dirt := _fill_terrain(ts, src, layout, "dirt", "Dirt", Color(0.6, 0.45, 0.3))
	var grass := _terrain(ts, "Grass", Color(0.4, 0.7, 0.25), bt.TerrainType.MATCH_TILES)
	_blob(ts, src, layout, grass, grass)
	# Decoration fills an empty cell next to a match, so these need grass on one side
	for side in ["t", "b", "l", "r"]:
		var td := _td(src, layout, "tuft_" + side)
		bt.set_tile_terrain_type(ts, td, bt.TileCategory.EMPTY)
		bt.add_tile_peering_type(ts, td, SIDES[side], grass)
		td.probability = 0.6
	ts = _save_tileset(ts, "decoration")
	var scene := _scene("Decoration")
	_paint(_layer(scene, "Dirt", ts), _cells([GROUND_AREA]), dirt)
	var tm := _layer(scene, "Grass", ts)
	bt.set_cells(tm, _cells(ISLAND, ISLAND_HOLES), grass)
	bt.update_terrain_area(tm, GROUND_AREA)
	_note(scene, "Decoration: tufts are decoration tiles. Painting grass also fills the empty cells\n"
		+ "around it with tufts that face the grass, some of the time.")
	_save_scene(scene, "04_decoration.tscn")


func _build_scatter() -> void:
	var made := _tileset("scatter")
	var ts: TileSet = made[0]
	var layout: Dictionary = made[2]
	var dirt := _fill_terrain(ts, made[1], layout, "dirt", "Dirt", Color(0.6, 0.45, 0.3))
	var grass := _terrain(ts, "Grass", Color(0.4, 0.7, 0.25), bt.TerrainType.MATCH_TILES)
	_blob(ts, made[1], layout, grass, grass)
	var bag := []
	var weights := {"flower": 3.0, "tuft": 4.0, "pebble": 2.0, "mushroom": 1.0, "bush": 1.0}
	for piece in layout:
		var kind: String = piece.get_slice("_", 0)
		if weights.has(kind):
			bag.append(ScatterTerrain.make_entry(0, Vector2i(layout[piece][0], layout[piece][1]), Vector2i.ONE, weights[kind]))
	bt.add_terrain(ts, "Meadow", Color(0.9, 0.6, 0.7), bt.TerrainType.SCATTER)
	var meadow: int = bt.terrain_count(ts) - 1
	ScatterTerrain.set_config(ts, meadow, {bag = bag, empty_pct = 65.0, seed = 3, live = false, edge = 0})
	ts = _save_tileset(ts, "scatter")
	var scene := _scene("Scatter")
	_paint(_layer(scene, "Dirt", ts), _cells([GROUND_AREA]), dirt)
	var ground := _layer(scene, "Grass", ts)
	_paint(ground, _cells(ISLAND, ISLAND_HOLES), grass)
	ScatterTerrain.add_cells(ground, meadow, _cells([Rect2i(4, 4, 9, 4), Rect2i(17, 4, 10, 9)], [Rect2i(20, 7, 4, 3)]))
	_note(scene, "Scatter: Meadow is a bag of loose tiles (flowers, tufts, pebbles) thrown over a region.\n"
		+ "Paint Meadow on the Grass layer; its settings set the weights and how much stays empty.")
	_save_scene(scene, "08_scatter.tscn")


func _build_single_tile() -> void:
	var made := _tileset("single_tile")
	var ts: TileSet = made[0]
	var layout: Dictionary = made[2]
	var dirt := _fill_terrain(ts, made[1], layout, "dirt", "Dirt", Color(0.6, 0.45, 0.3))
	var grass := _terrain(ts, "Grass", Color(0.4, 0.7, 0.25), bt.TerrainType.MATCH_TILES)
	_blob(ts, made[1], layout, grass, grass)
	var stamps := {}
	for piece in ["sign", "well"]:
		var r: Array = layout[piece]
		bt.add_terrain(ts, piece.capitalize(), Color(0.8, 0.7, 0.4), bt.TerrainType.SINGLE)
		stamps[piece] = bt.terrain_count(ts) - 1
		bt.set_terrain_object(ts, stamps[piece], {tile = {source = 0, coord = [r[0], r[1]], alt = 0, size = [r[2], r[3]]}})
	ts = _save_tileset(ts, "single_tile")
	var scene := _scene("SingleTile")
	_paint(_layer(scene, "Dirt", ts), _cells([GROUND_AREA]), dirt)
	_paint(_layer(scene, "Grass", ts), _cells(ISLAND, ISLAND_HOLES), grass)
	var props := _layer(scene, "Props", ts)
	for at in [Vector2i(5, 5), Vector2i(12, 11), Vector2i(26, 4)]:
		bt.set_cells(props, [at], stamps.sign, at)
	bt.set_cells(props, bt.single_block_cells(ts, stamps.well, [Vector2i(18, 11)], Vector2i(18, 11)), stamps.well, Vector2i(18, 11))
	_note(scene, "Single tile: Sign and Well place one tile or one block as it is, with no rules.\n"
		+ "Pick one and paint on the Props layer; any tile can also be picked straight from the atlas.")
	_save_scene(scene, "09_single_tile.tscn")


func _mark_block(ts: TileSet, src, piece: Array, terrain: int) -> void:
	for y in piece[3]:
		for x in piece[2]:
			bt.set_tile_terrain_type(ts, src.get_tile_data(Vector2i(piece[0] + x, piece[1] + y), 0), terrain)


func _build_objects() -> void:
	var made := _tileset("objects")
	var ts: TileSet = made[0]
	var src: TileSetAtlasSource = made[1]
	var layout: Dictionary = made[2]
	var dirt := _fill_terrain(ts, src, layout, "dirt", "Dirt", Color(0.6, 0.45, 0.3))
	var grass := _terrain(ts, "Grass", Color(0.4, 0.7, 0.25), bt.TerrainType.MATCH_TILES)
	_blob(ts, src, layout, grass, grass)
	# Two 2x2 blocks: a lone tree, and the leaves it gets when touching another
	var lone: Array = layout.tree_lone
	bt.add_terrain(ts, "Tree", Color(0.25, 0.5, 0.25), bt.TerrainType.OBJECT, [], {}, "",
		ObjectTerrain.make_config(Vector2i(2, 2), Vector2i(lone[0], lone[1])))
	var tree: int = bt.terrain_count(ts) - 1
	_mark_block(ts, src, lone, tree)
	_mark_block(ts, src, layout.tree_joined, tree)
	ts = _save_tileset(ts, "objects")
	var scene := _scene("Objects")
	_paint(_layer(scene, "Dirt", ts), _cells([GROUND_AREA]), dirt)
	_paint(_layer(scene, "Grass", ts), _cells([Rect2i(1, 1, 30, 16)]), grass)
	var trees := _layer(scene, "Trees", ts)
	bt.set_cells(trees, _cells([Rect2i(4, 4, 2, 2), Rect2i(8, 8, 2, 2), Rect2i(4, 12, 2, 2),
		Rect2i(14, 4, 8, 6), Rect2i(22, 10, 4, 4)]), tree)
	ObjectTerrain.fix_layer(trees)
	_note(scene, "Objects: a tree is a 2x2 block, with a second block for where trees touch.\n"
		+ "Paint Tree on the Trees layer: single trees stay round, neighbours join into one canopy.")
	_save_scene(scene, "05_objects.tscn")


func _build_forest() -> void:
	var made := _tileset("forest")
	var ts: TileSet = made[0]
	var src: TileSetAtlasSource = made[1]
	var layout: Dictionary = made[2]
	var dirt := _fill_terrain(ts, src, layout, "dirt", "Dirt", Color(0.6, 0.45, 0.3))
	var grass := _terrain(ts, "Grass", Color(0.4, 0.7, 0.25), bt.TerrainType.MATCH_TILES)
	_blob(ts, src, layout, grass, grass)
	# One 2x3 tree whose bottom row must fit the painted area
	var pine: Array = layout.pine
	bt.add_terrain(ts, "Pine forest", Color(0.2, 0.45, 0.3), bt.TerrainType.OBJECT, [], {}, "",
		ObjectTerrain.make_config(Vector2i(2, 3), Vector2i(pine[0], pine[1]), true, Rect2i(0, 2, 2, 1)))
	var forest_id: int = bt.terrain_count(ts) - 1
	_mark_block(ts, src, pine, forest_id)
	ts = _save_tileset(ts, "forest")
	var scene := _scene("Forest")
	_paint(_layer(scene, "Dirt", ts), _cells([GROUND_AREA]), dirt)
	_paint(_layer(scene, "Grass", ts), _cells([Rect2i(1, 1, 30, 16)]), grass)
	var forest := _layer(scene, "Forest", ts)
	bt.set_cells(forest, _cells([Rect2i(3, 3, 12, 8), Rect2i(6, 11, 6, 4), Rect2i(19, 4, 9, 10)], [Rect2i(22, 7, 3, 3)]), forest_id)
	ObjectTerrain.fix_mass(forest)
	_note(scene, "Forest: Pine forest is an object painted as a mass. Paint an area and it fills with\n"
		+ "overlapping trees; leave a hole and it becomes a clearing.")
	_save_scene(scene, "06_forest.tscn")


func _build_patch() -> void:
	var made := _tileset("patch")
	var ts: TileSet = made[0]
	var src: TileSetAtlasSource = made[1]
	var layout: Dictionary = made[2]
	var grass := _fill_terrain(ts, src, layout, "grass", "Grass", Color(0.4, 0.7, 0.25))
	# Pond drawn once, whole; the terrain learns banks and corners from it
	var pond := _terrain(ts, "Pond", Color(0.3, 0.5, 0.85), bt.TerrainType.EXEMPLAR)
	_mark_block(ts, src, layout.pond, pond)
	ExemplarData.store_table(ts, "Pond", ExemplarData.learn_from_block(ts, pond, 0))
	ts = _save_tileset(ts, "patch")
	var scene := _scene("Patch")
	_paint(_layer(scene, "Grass", ts), _cells([GROUND_AREA]), grass)
	var water := _layer(scene, "Pond", ts)
	bt.set_cells(water, _cells([Rect2i(3, 3, 9, 5), Rect2i(7, 8, 4, 6), Rect2i(18, 4, 10, 9)], [Rect2i(21, 7, 3, 3)]), pond)
	ExemplarTerrain.rebuild(water, bt)
	_note(scene, "Patch: Pond is read from one drawing of a pond. Paint any shape on the Pond layer\n"
		+ "and it gets the banks, corners and water of that drawing.")
	_save_scene(scene, "07_patch.tscn")


func _build_cliffs() -> void:
	var made := _tileset("cliffs")
	var ts: TileSet = made[0]
	var src: TileSetAtlasSource = made[1]
	var layout: Dictionary = made[2]
	var high := _terrain(ts, "Highland", Color(0.4, 0.7, 0.25), bt.TerrainType.MATCH_TILES)
	_blob(ts, src, layout, high, high)
	# Face pattern: repeating body plus left, right and bottom edges
	var cfg := CliffPattern.default_config()
	cfg.source_id = 0
	cfg.rows_up = true
	for piece in ["body", "left", "right", "bottom", "bottom_left", "bottom_right"]:
		var r: Array = layout["wall_" + piece]
		cfg[piece] = {"use": true, "rect": Rect2i(r[0], r[1], r[2], r[3])}
	cfg.body["col_offset"] = 0
	cfg.body["row_offset"] = 0
	CliffData.store_config(ts, "Highland", cfg)
	ts = _save_tileset(ts, "cliffs")
	var scene := _scene("Cliffs")
	var levels := []
	for i in 3:
		levels.append(_layer(scene, "Level%d" % i, ts))
	_paint(levels[0], _cells([GROUND_AREA]), high)
	_paint(levels[1], _cells([Rect2i(3, 3, 12, 9), Rect2i(18, 4, 11, 10)], [Rect2i(22, 10, 3, 4)]), high)
	_paint(levels[2], _cells([Rect2i(5, 4, 6, 4), Rect2i(21, 5, 6, 3)]), high)
	for level in levels:
		CliffTerrain.rebuild(level, bt)
	_note(scene, "Cliffs: each layer is one level higher. Paint Highland on Level1 or Level2 and the rock\n"
		+ "faces under its edges are generated, one row tall per level.")
	_save_scene(scene, "10_cliffs.tscn")


func _build_slopes() -> void:
	var made := _tileset("slopes")
	var ts: TileSet = made[0]
	var src: TileSetAtlasSource = made[1]
	var layout: Dictionary = made[2]
	var ground := _terrain(ts, "Ground", Color(0.45, 0.75, 0.3), bt.TerrainType.MATCH_TILES)
	var solid := _terrain(ts, "Solid", Color(0.5, 0.5, 0.5), bt.TerrainType.CATEGORY)
	bt.set_terrain(ts, ground, "Ground", Color(0.45, 0.75, 0.3), bt.TerrainType.MATCH_TILES, [solid])
	var pieces := {"ground:tl": "tl", "ground:t": "t", "ground:tr": "tr", "ground:l": "l", "ground:c": "c",
		"ground:r": "r", "ground:bl": "bl", "ground:b": "b", "ground:br": "br", "ground:itl": "itl",
		"ground:itr": "itr", "ground:ibl": "ibl", "ground:ibr": "ibr"}
	for piece in pieces:
		var td := _td(src, layout, piece)
		bt.set_tile_terrain_type(ts, td, ground)
		for side in BLOB_SIDES[pieces[piece]]:
			bt.add_tile_peering_type(ts, td, SIDES[side], solid)
	for piece in {"ground:barl": ["r"], "ground:barm": ["l", "r"], "ground:barr": ["l"]}.keys():
		var td := _td(src, layout, piece)
		bt.set_tile_terrain_type(ts, td, ground)
		for side in {"ground:barl": ["r"], "ground:barm": ["l", "r"], "ground:barr": ["l"]}[piece]:
			bt.add_tile_peering_type(ts, td, SIDES[side], solid)
	# Slope pieces go in the way the Slopes window adds them, then its rules
	SlopeTerrain.assign(bt, ts, "ground", 0, Vector2i(layout["ground:c"][0], layout["ground:c"][1]))
	for slot in layout:
		if not slot.begins_with("ground"):
			SlopeTerrain.assign(bt, ts, slot, 0, Vector2i(layout[slot][0], layout[slot][1]))
	SlopeTerrain.add_rules(bt, ts)
	ts.remove_meta(SlopeTerrain.TAKEN_META)
	ts = _save_tileset(ts, "slopes")
	var scene := _scene("Slopes")
	var tm := _layer(scene, "Ground", ts)
	var slope := func(low: Vector2i, h_up: int, steps: int, steep: bool, thin := false) -> void:
		var found := SlopeTerrain.roles(ts)
		var members: Array = found.values()
		var plan := SlopeTerrain.build(found, func(c): return bt.get_cell(tm, c) in members, low, h_up, steps, steep, false, thin)
		for c in plan.erase:
			tm.erase_cell(c)
		for c in plan.cells:
			bt.set_cell(tm, c, plan.cells[c])
	var fill := func(r: Rect2i) -> void: bt.set_cells(tm, _cells([r]), ground)
	fill.call(Rect2i(0, 10, 72, 4))
	fill.call(Rect2i(10, 6, 6, 4))
	slope.call(Vector2i(2, 9), 1, 4, false)
	slope.call(Vector2i(19, 9), -1, 4, true)
	fill.call(Rect2i(22, 6, 3, 4))
	fill.call(Rect2i(33, 6, 3, 4))
	slope.call(Vector2i(28, 9), -1, 4, true)
	slope.call(Vector2i(29, 9), 1, 4, true)
	fill.call(Rect2i(52, 6, 4, 4))
	slope.call(Vector2i(43, 9), -1, 4, false)
	slope.call(Vector2i(44, 9), 1, 4, false)
	fill.call(Rect2i(60, 3, 10, 2))
	fill.call(Rect2i(62, 2, 6, 1))
	fill.call(Rect2i(64, 5, 2, 2))
	slope.call(Vector2i(60, 2), 1, 1, false)
	slope.call(Vector2i(69, 2), -1, 1, false)
	slope.call(Vector2i(63, 6), -1, 2, false)
	slope.call(Vector2i(66, 6), 1, 2, false)
	fill.call(Rect2i(11, 0, 3, 1))
	slope.call(Vector2i(3, 3), 1, 4, false, true)
	slope.call(Vector2i(24, 0), -1, 3, true, true)
	fill.call(Rect2i(40, 1, 5, 1))
	bt.update_terrain_cells(tm, tm.get_used_cells())
	_note(scene, "Slopes: pick Ground, then the slope tool next to the fill tool, and drag the ground's surface.\n"
		+ "Diagonal drags draw steep or gentle slopes; start under a ceiling for a ceiling slope; Shift for a thin one.\n"
		+ "The pieces are set up in Options > Slopes. The tileset also uses must-not rules.")
	_save_scene(scene, "11_slopes.tscn")
