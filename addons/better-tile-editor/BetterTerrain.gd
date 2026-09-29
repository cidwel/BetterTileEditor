@tool
extends Node

## A [TileMapLayer] terrain / auto-tiling system.
##
## This is a drop-in replacement for Godot 4's tilemap terrain system, offering
## more versatile and straightforward autotiling. It can be used with any
## existing [TileMapLayer] or [TileSet], either through the editor plugin, or
## directly via code.
## [br][br]
## The [b]BetterTerrain[/b] class contains only static functions, each of which
## either takes a [TileMapLayer], a [TileSet], and sometimes a [TileData].
## Meta-data is embedded inside the [TileSet] and the [TileData] types to store
## the terrain information. See [method Object.get_meta] for information.
## [br][br]
## Once terrain is set up, it can be written to the tilemap using [method set_cells].
## Similar to Godot 3.x, setting the cells does not run the terrain solver, so once
## the cells have been set, you need to call an update function such as [method update_terrain_cells].


## The meta-data key used to store terrain information.
const TERRAIN_META = &"_better_terrain"

## The current version. Used to handle future upgrades.
const TERRAIN_SYSTEM_VERSION = "0.3"

const DEFAULT_GROUP := ""

const ObjectTerrain := preload("res://addons/better-tile-editor/ObjectTerrain.gd")

var _tile_cache = {}
var rng = RandomNumberGenerator.new()
var use_seed := true

## A helper class that provides functions detailing valid peering bits and
## polygons for different tile types.
var data := load("res://addons/better-tile-editor/BetterTerrainData.gd"):
	get:
		return data

enum TerrainType {
	MATCH_TILES, ## Selects tiles by matching against adjacent tiles.
	MATCH_VERTICES, ## Select tiles by analysing vertices, similar to wang-style tiles.
	CATEGORY, ## Declares a matching type for more sophisticated rules.
	DECORATION, ## Fills empty tiles by matching adjacent tiles
	OBJECT,
	EXEMPLAR,
	SCATTER,
	SINGLE,
	MAX,
}

enum TileCategory {
	EMPTY = -1, ## An empty cell, or a tile marked as decoration
	NON_TERRAIN = -2, ## A non-empty cell that does not contain a terrain tile
	ERROR = -3,
	SINGLE = -4,
}

enum SymmetryType {
	NONE,
	MIRROR, ## Horizontally mirror
	FLIP, ## Vertically flip
	REFLECT, ## All four reflections
	ROTATE_CLOCKWISE,
	ROTATE_COUNTER_CLOCKWISE,
	ROTATE_180,
	ROTATE_ALL, ## All four rotated forms
	ALL ## All rotated and reflected forms
}


func _intersect(first: Array, second: Array) -> bool:
	if first.size() > second.size():
		return _intersect(second, first) # Array 'has' is fast compared to gdscript loop
	for f in first:
		if second.has(f):
			return true
	return false


## Returns [source_id, coord, alternate], or []. Picking a brush preserves tile terrain membership.
func single_tile_of(ts: TileSet, type: int) -> Array:
	if ts == null or (type < 0 and type != TileCategory.SINGLE):
		return []
	var ts_meta := _get_terrain_meta(ts)
	var terrain: Array
	if type == TileCategory.SINGLE:
		terrain = _single_meta(ts_meta)
	elif type >= ts_meta.terrains.size():
		return []
	else:
		terrain = ts_meta.terrains[type]
	if terrain[2] != TerrainType.SINGLE or terrain.size() < 7 or typeof(terrain[6]) != TYPE_DICTIONARY:
		return []
	var tile = terrain[6].get("tile", {})
	if typeof(tile) != TYPE_DICTIONARY or not tile.has("coord"):
		return []
	var at: Array = tile.coord
	return [int(tile.get("source", 0)), Vector2i(int(at[0]), int(at[1])), int(tile.get("alt", 0))]


## Set notify=false for brush pxcks that do not change terrain rules.
func set_single_tile(ts: TileSet, source: int, coord: Vector2i, alternate := 0,
		size := Vector2i.ONE, notify := true) -> void:
	if ts == null:
		return
	var ts_meta := _get_terrain_meta(ts)
	var entry := _single_meta(ts_meta)
	if source < 0:
		entry[6] = {}
	else:
		entry[6] = {tile = {source = source, coord = [coord.x, coord.y], alt = alternate,
			size = [maxi(1, size.x), maxi(1, size.y)]}}
	if notify:
		_set_terrain_meta(ts, ts_meta)
	else:
		ts.set_meta(TERRAIN_META, ts_meta)


## Returns {source, origin, alternate, size}, or {} when no brush is picked.
func single_block_of(ts: TileSet, type: int) -> Dictionary:
	var one := single_tile_of(ts, type)
	if one.is_empty():
		return {}
	var size := Vector2i.ONE
	var ts_meta := _get_terrain_meta(ts)
	var entry: Array = _single_meta(ts_meta) if type == TileCategory.SINGLE \
		else ts_meta.terrains[type]
	var tile = entry[6].get("tile", {})
	if typeof(tile) == TYPE_DICTIONARY and tile.has("size"):
		var at: Array = tile.size
		size = Vector2i(maxi(1, int(at[0])), maxi(1, int(at[1])))
	return {source = one[0], origin = one[1], alt = one[2], size = size}


# Atlas cells with no tile (gaps, the body of a bigger tile) are skipped, not written as unknown.
func _set_single_cell(tm: TileMapLayer, coord: Vector2i, block: Dictionary, anchor: Vector2i) -> bool:
	var atlas := _single_at(block, coord, anchor)
	var source: TileSetAtlasSource = null
	if tm.tile_set.has_source(block.source):
		source = tm.tile_set.get_source(block.source) as TileSetAtlasSource
	if source != null and not source.has_tile(atlas):
		return false
	tm.set_cell(coord, block.source, atlas, block.alt)
	return true


func _single_at(block: Dictionary, coord: Vector2i, anchor := Vector2i.ZERO) -> Vector2i:
	var size: Vector2i = block.size
	var from := coord - anchor
	return block.origin + Vector2i(posmod(from.x, size.x), posmod(from.y, size.y))


func single_block_cells(ts: TileSet, type: int, coords: Array, anchor := Vector2i.ZERO) -> Array:
	var block := single_block_of(ts, type)
	if block.is_empty() or block.size == Vector2i.ONE:
		return coords
	var size: Vector2i = block.size
	var seen := {}
	for c in coords:
		var from: Vector2i = Vector2i(c) - anchor
		var corner := anchor + from - Vector2i(posmod(from.x, size.x), posmod(from.y, size.y))
		for dy in size.y:
			for dx in size.x:
				seen[corner + Vector2i(dx, dy)] = true
	return seen.keys()


# Meta-data functions

func _get_terrain_meta(ts: TileSet) -> Dictionary:
	return ts.get_meta(TERRAIN_META) if ts and ts.has_meta(TERRAIN_META) else {
		terrains = [],
		groups = [],
		decoration = ["Decoration", Color.DIM_GRAY, TerrainType.DECORATION, [], {path = "res://addons/better-tile-editor/icons/Decoration.svg"}],
		single = _fresh_single(),
		version = TERRAIN_SYSTEM_VERSION
	}


func _fresh_single() -> Array:
	return ["Single tile", Color(0.75, 0.78, 0.85), TerrainType.SINGLE, [],
		{path = "res://addons/better-tile-editor/icons/SingleTile.svg"}, "", {}]


func _single_meta(ts_meta: Dictionary) -> Array:
	if not ts_meta.has("single") or typeof(ts_meta["single"]) != TYPE_ARRAY \
			or ts_meta["single"].size() < 7:
		ts_meta["single"] = _fresh_single()
	return ts_meta["single"]


# Pre-0.3 terrains and the decoration entry have no group element.
func _terrain_group_of(terrain: Array) -> String:
	return terrain[5] if terrain.size() > 5 else DEFAULT_GROUP


# Older terrain records have no seventh element and use an empty configuration.
func _terrain_object_of(terrain: Array) -> Dictionary:
	return terrain[6] if terrain.size() > 6 else {}


func _set_terrain_meta(ts: TileSet, meta : Dictionary) -> void:
	ts.set_meta(TERRAIN_META, meta)
	ts.emit_changed()


func _get_tile_meta(td: TileData) -> Dictionary:
	return td.get_meta(TERRAIN_META) if td.has_meta(TERRAIN_META) else {
		type = TileCategory.NON_TERRAIN
	}


func _set_tile_meta(ts: TileSet, td: TileData, meta) -> void:
	td.set_meta(TERRAIN_META, meta)
	ts.emit_changed()


func _get_cache(ts: TileSet) -> Array:
	if _tile_cache.has(ts):
		return _tile_cache[ts]
	
	var cache := []
	if !ts:
		return cache
	_tile_cache[ts] = cache

	var watcher = Node.new()
	watcher.set_script(load("res://addons/better-tile-editor/Watcher.gd"))
	watcher.tileset = ts
	watcher.trigger.connect(_purge_cache.bind(ts))
	add_child(watcher)
	ts.changed.connect(watcher.activate)
	
	var types = {}
	
	var ts_meta := _get_terrain_meta(ts)
	for t in ts_meta.terrains.size():
		var terrain = ts_meta.terrains[t]
		var bits = terrain[3].duplicate()
		bits.push_back(t)
		types[t] = bits
		cache.push_back([])
	
	# Decoration
	types[-1] = [TileCategory.EMPTY]
	cache.push_back([[-1, Vector2.ZERO, -1, {}, 1.0, {}]])
	
	for s in ts.get_source_count():
		var source_id := ts.get_source_id(s)
		var source := ts.get_source(source_id) as TileSetAtlasSource
		if !source:
			continue
		source.changed.connect(watcher.activate)
		for c in source.get_tiles_count():
			var coord := source.get_tile_id(c)
			for a in source.get_alternative_tiles_count(coord):
				var alternate := source.get_alternative_tile_id(coord, a)
				var td := source.get_tile_data(coord, alternate)
				if td.get_meta(ObjectTerrain.MASS_MARKER, false):
					continue
				var td_meta := _get_tile_meta(td)
				if td_meta.type < TileCategory.EMPTY or td_meta.type >= cache.size():
					continue
				
				td.changed.connect(watcher.activate)
				var peering := {}
				for key in td_meta.keys():
					if !(key is int):
						continue
					
					var targets := []
					for k in types:
						if _intersect(types[k], td_meta[key]):
							targets.push_back(k)
					
					peering[key] = targets
				
				var not_peering := {}
				var not_meta: Dictionary = td_meta.get("not", {})
				for key in not_meta:
					var targets := []
					for k in types:
						if _intersect(types[k], not_meta[key]):
							targets.push_back(k)
					not_peering[key] = targets
				
				# Decoration tiles without peering are skipped
				if td_meta.type == TileCategory.EMPTY and !peering:
					continue
				
				var _unused_marker = 0
				var symmetry = td_meta.get("symmetry", SymmetryType.NONE)
				# Branch out no symmetry tiles early
				if symmetry == SymmetryType.NONE:
					cache[td_meta.type].push_back([source_id, coord, alternate, peering, td.probability, not_peering])
					continue
				
				# calculate the symmetry order for this tile
				var symmetry_order := 0
				for flags in data.symmetry_mapping[symmetry]:
					var symmetric_peering = data.peering_bits_after_symmetry(peering, flags)
					if symmetric_peering == peering:
						symmetry_order += 1
				
				var adjusted_probability = td.probability / symmetry_order
				for flags in data.symmetry_mapping[symmetry]:
					var symmetric_peering = data.peering_bits_after_symmetry(peering, flags)
					var symmetric_not = data.peering_bits_after_symmetry(not_peering, flags)
					cache[td_meta.type].push_back([source_id, coord, alternate | flags, symmetric_peering, adjusted_probability, symmetric_not])
	
	return cache


func _get_cache_terrain(ts_meta : Dictionary, index: int) -> Array:
	# the cache and the terrains in ts_meta don't line up because
	# decorations are cached too
	if index == TileCategory.SINGLE:
		return _single_meta(ts_meta)
	if index < 0 or index >= ts_meta.terrains.size():
		return ts_meta.decoration
	return ts_meta.terrains[index]


func _purge_cache(ts: TileSet) -> void:
	ObjectTerrain.invalidate(ts)
	_tile_cache.erase(ts)
	for c in get_children():
		if c.tileset == ts:
			c.tidy()
			break


func _clear_invalid_peering_types(ts: TileSet) -> void:
	var ts_meta := _get_terrain_meta(ts)
	
	var cache := _get_cache(ts)
	for t in cache.size():
		var type = _get_cache_terrain(ts_meta, t)[2]
		var valid_peering_types = data.get_terrain_peering_cells(ts, type)
		
		for c in cache[t]:
			if c[0] < 0:
				continue
			var source := ts.get_source(c[0]) as TileSetAtlasSource
			if !source:
				continue
			var td := source.get_tile_data(c[1], c[2])
			var td_meta := _get_tile_meta(td)
			
			for peering in c[3].keys():
				if valid_peering_types.has(peering):
					continue
				td_meta.erase(peering)
			
			var not_dict: Dictionary = td_meta.get("not", {})
			for peering in not_dict.keys():
				if !valid_peering_types.has(peering):
					not_dict.erase(peering)
			if not_dict.is_empty():
				td_meta.erase("not")
			
			_set_tile_meta(ts, td, td_meta)
	
	# Not strictly necessary
	_purge_cache(ts)


func _has_invalid_peering_types(ts: TileSet) -> bool:
	var ts_meta := _get_terrain_meta(ts)
	
	var cache := _get_cache(ts)
	for t in cache.size():
		var type = _get_cache_terrain(ts_meta, t)[2]
		var valid_peering_types = data.get_terrain_peering_cells(ts, type)
		
		for c in cache[t]:
			for peering in c[3].keys():
				if !valid_peering_types.has(peering):
					return true
			for peering in c[5].keys():
				if !valid_peering_types.has(peering):
					return true
	
	return false


func _update_terrain_data(ts: TileSet) -> void:
	var ts_meta = _get_terrain_meta(ts)
	var previous_version = ts_meta.get("version")
	
	# First release: no version info
	if !ts_meta.has("version"):
		ts_meta["version"] = "0.0"
	
	# 0.0 -> 0.1: add categories
	if ts_meta.version == "0.0":
		for t in ts_meta.terrains:
			if t.size() == 3:
				t.push_back([])
		ts_meta.version = "0.1"
	
	# 0.1 -> 0.2: add decoration tiles and terrain icons
	if ts_meta.version == "0.1":
		# Add terrain icon containers
		for t in ts_meta.terrains:
			if t.size() == 4:
				t.push_back({})
		
		# Add default decoration data
		ts_meta["decoration"] = ["Decoration", Color.DIM_GRAY, TerrainType.DECORATION, [], {path = "res://addons/better-tile-editor/icons/Decoration.svg"}]
		ts_meta.version = "0.2"

	if ts_meta.version == "0.2":
		for t in ts_meta.terrains:
			if t.size() == 5:
				t.push_back(DEFAULT_GROUP)

		ts_meta["groups"] = []
		ts_meta.version = "0.3"

	# Early 0.3 tilesets may have terrain groups without a grouf list.
	if !ts_meta.has("groups"):
		ts_meta["groups"] = []

	if previous_version != ts_meta.version:
		_set_terrain_meta(ts, ts_meta)


func _weighted_selection(choices: Array, apply_empty_probability: bool):
	if choices.is_empty():
		return null
	
	var weight = choices.reduce(func(a, c): return a + c[4], 0.0)
	
	if apply_empty_probability and weight < 1.0 and rng.randf() > weight:
		return [-1, Vector2.ZERO, -1, {}, 1.0, {}]
	
	if choices.size() == 1:
		return choices[0]
	
	if weight == 0.0:
		return choices[rng.randi() % choices.size()]
	
	var pick = rng.randf() * weight
	for c in choices:
		if pick < c[4]:
			return c
		pick -= c[4]
	return choices.back()


func _weighted_selection_seeded(choices: Array, coord: Vector2i, apply_empty_probability: bool):
	if use_seed:
		rng.seed = hash(coord)
	return _weighted_selection(choices, apply_empty_probability)


func _update_tile_tiles(tm: TileMapLayer, coord: Vector2i, types: Dictionary, cache: Array, apply_empty_probability: bool):
	var type = types[coord]
	
	const reward := 3
	var penalty := -2000 if apply_empty_probability else -10
	
	var best_score := -1000 # Impossibly bad score
	var best := []
	for t in cache[type]:
		var score := 0
		for peering in t[3]:
			score += reward if t[3][peering].has(types[tm.get_neighbor_cell(coord, peering)]) else penalty
		# A broken must-not rule costs a penalty; a kept one only earns on sides without a match rule
		for peering in t[5]:
			if t[5][peering].has(types[tm.get_neighbor_cell(coord, peering)]):
				score += penalty
			elif !t[3].has(peering):
				score += reward
		
		if score > best_score:
			best_score = score
			best = [t]
		elif score == best_score:
			best.append(t)
	
	return _weighted_selection_seeded(best, coord, apply_empty_probability)


func _probe(tm: TileMapLayer, coord: Vector2i, peering: int, type: int, types: Dictionary) -> int:
	var targets = data.associated_vertex_cells(tm, coord, peering)
	targets = targets.map(func(c): return types[c])
	
	var first = targets[0]
	if targets.all(func(t): return t == first):
		return first
	
	# if different, use the lowest  non-same
	targets = targets.filter(func(t): return t != type)
	return targets.reduce(func(a, t): return min(a, t))


func _update_tile_vertices(tm: TileMapLayer, coord: Vector2i, types: Dictionary, cache: Array):
	var type = types[coord]
	
	const reward := 3
	const penalty := -10
	
	var best_score := -1000 # Impossibly bad score
	var best := []
	for t in cache[type]:
		var score := 0
		for peering in t[3]:
			score += reward if _probe(tm, coord, peering, type, types) in t[3][peering] else penalty
		for peering in t[5]:
			if _probe(tm, coord, peering, type, types) in t[5][peering]:
				score += penalty
			elif !t[3].has(peering):
				score += reward
		
		if score > best_score:
			best_score = score
			best = [t]
		elif score == best_score:
			best.append(t)
	
	return _weighted_selection_seeded(best, coord, false)


func _update_tile_immediate(tm: TileMapLayer, coord: Vector2i, ts_meta: Dictionary, types: Dictionary, cache: Array) -> void:
	var type = types[coord]
	if type < TileCategory.EMPTY or type >= ts_meta.terrains.size():
		return
	
	var placement
	var terrain = _get_cache_terrain(ts_meta, type)
	if terrain[2] in [TerrainType.MATCH_TILES, TerrainType.DECORATION]:
		placement = _update_tile_tiles(tm, coord, types, cache, terrain[2] == TerrainType.DECORATION)
	elif terrain[2] == TerrainType.MATCH_VERTICES:
		placement = _update_tile_vertices(tm, coord, types, cache)
	else:
		return
	
	if placement:
		tm.set_cell(coord, placement[0], placement[1], placement[2])


func _update_tile_deferred(tm: TileMapLayer, coord: Vector2i, ts_meta: Dictionary, types: Dictionary, cache: Array):
	var type = types[coord]
	if type >= TileCategory.EMPTY and type < ts_meta.terrains.size():
		var terrain = _get_cache_terrain(ts_meta, type)
		if terrain[2] in [TerrainType.MATCH_TILES, TerrainType.DECORATION]:
			return _update_tile_tiles(tm, coord, types, cache, terrain[2] == TerrainType.DECORATION)
		elif terrain[2] == TerrainType.MATCH_VERTICES:
			return _update_tile_vertices(tm, coord, types, cache)
	return null


func _widen(tm: TileMapLayer, coords: Array) -> Array:
	var result := {}
	var peering_neighbors = data.get_terrain_peering_cells(tm.tile_set, TerrainType.MATCH_TILES)
	for c in coords:
		result[c] = true
		var neighbors = data.neighboring_coords(tm, c, peering_neighbors)
		for t in neighbors:
			result[t] = true
	return result.keys()


func _widen_with_exclusion(tm: TileMapLayer, coords: Array, exclusion: Rect2i) -> Array:
	var result := {}
	var peering_neighbors = data.get_terrain_peering_cells(tm.tile_set, TerrainType.MATCH_TILES)
	for c in coords:
		if !exclusion.has_point(c):
			result[c] = true
		var neighbors = data.neighboring_coords(tm, c, peering_neighbors)
		for t in neighbors:
			if !exclusion.has_point(t):
				result[t] = true
	return result.keys()

# Terrains

## Returns an [Array] of categories. These are the terrains in the [TileSet] which
## are marked with [enum TerrainType] of [code]CATEGORY[/code]. Each entry in the
## array is a [Dictionary] with [code]name[/code], [code]color[/code], and [code]id[/code].
func get_terrain_categories(ts: TileSet) -> Array:
	var result := []
	if !ts:
		return result
	
	var ts_meta := _get_terrain_meta(ts)
	for id in ts_meta.terrains.size():
		var t = ts_meta.terrains[id]
		if t[2] == TerrainType.CATEGORY:
			result.push_back({name = t[0], color = t[1], id = id})
	
	return result


#region Display groups

# Display groups store [name, icon_terrain]; -1 uses the first member for the icon.


# The group API can be called before tileset migration.
func _groups_of(ts_meta: Dictionary) -> Array:
	return ts_meta.get("groups", [])


func _ensure_groups(ts_meta: Dictionary) -> Array:
	if !ts_meta.has("groups"):
		ts_meta["groups"] = []
	return ts_meta.groups


func _group_index(ts_meta: Dictionary, group_name: String) -> int:
	var groups := _groups_of(ts_meta)
	for i in groups.size():
		if groups[i][0] == group_name:
			return i
	return -1


func get_terrain_groups(ts: TileSet) -> Array:
	var result := []
	if !ts:
		return result

	var ts_meta := _get_terrain_meta(ts)
	var groups := _groups_of(ts_meta)
	for i in groups.size():
		var g = groups[i]
		var members := get_terrains_in_group(ts, g[0])

		var icon_terrain : int = g[1]
		if !members.has(icon_terrain):
			icon_terrain = members[0] if !members.is_empty() else -1

		var color := Color.DIM_GRAY
		if icon_terrain >= 0:
			var t := get_terrain(ts, icon_terrain)
			if t.valid:
				color = t.color

		result.push_back({
			name = g[0],
			color = color,
			index = i,
			icon_terrain = icon_terrain
		})

	return result


func get_terrains_in_group(ts: TileSet, group: String) -> Array:
	var result := []
	if !ts:
		return result

	var ts_meta := _get_terrain_meta(ts)
	for id in ts_meta.terrains.size():
		if _terrain_group_of(ts_meta.terrains[id]) == group:
			result.push_back(id)

	return result


## Display order is ungrouped first, then groups. Terrains with missing groups count as ungrouped.
func get_terrain_display_order(ts: TileSet) -> Array:
	var result := []
	if !ts:
		return result

	var ts_meta := _get_terrain_meta(ts)
	var known := {}
	for g in _groups_of(ts_meta):
		known[g[0]] = true

	for id in ts_meta.terrains.size():
		var group := _terrain_group_of(ts_meta.terrains[id])
		if group == DEFAULT_GROUP or !known.has(group):
			result.push_back(id)

	for g in _groups_of(ts_meta):
		result.append_array(get_terrains_in_group(ts, g[0]))

	return result


func has_terrain_groups(ts: TileSet) -> bool:
	if !ts:
		return false

	var ts_meta := _get_terrain_meta(ts)
	if _groups_of(ts_meta).is_empty():
		return false

	for g in _groups_of(ts_meta):
		if !get_terrains_in_group(ts, g[0]).is_empty():
			return true

	return false


func add_terrain_group(ts: TileSet, group_name: String) -> bool:
	if !ts or group_name.is_empty():
		return false

	var ts_meta := _get_terrain_meta(ts)
	if _group_index(ts_meta, group_name) != -1:
		return false

	_ensure_groups(ts_meta).push_back([group_name, -1])
	_set_terrain_meta(ts, ts_meta)
	return true


func remove_terrain_group(ts: TileSet, index: int) -> bool:
	if !ts or index < 0:
		return false

	var ts_meta := _get_terrain_meta(ts)
	if index >= _groups_of(ts_meta).size():
		return false

	var group_name : String = ts_meta.groups[index][0]
	for t in ts_meta.terrains:
		if _terrain_group_of(t) == group_name:
			t[5] = DEFAULT_GROUP

	ts_meta.groups.remove_at(index)
	_rename_scene_group(ts_meta, group_name, "")
	_set_terrain_meta(ts, ts_meta)
	return true


func rename_terrain_group(ts: TileSet, index: int, group_name: String) -> bool:
	if !ts or index < 0 or group_name.is_empty():
		return false

	var ts_meta := _get_terrain_meta(ts)
	if index >= _groups_of(ts_meta).size():
		return false

	var existing := _group_index(ts_meta, group_name)
	if existing != -1 and existing != index:
		return false

	var old_name : String = ts_meta.groups[index][0]
	if old_name == group_name:
		return true

	for t in ts_meta.terrains:
		if _terrain_group_of(t) == old_name:
			t[5] = group_name

	ts_meta.groups[index][0] = group_name
	_rename_scene_group(ts_meta, old_name, group_name)
	_set_terrain_meta(ts, ts_meta)
	return true


## Named groups a scene tile is listed in besides Scenes.
func get_scene_tile_groups(ts: TileSet, source_id: int, scene_id: int) -> Array:
	if !ts:
		return []
	var all: Dictionary = _get_terrain_meta(ts).get("scene_groups", {})
	return (all.get(_scene_tile_key(source_id, scene_id), []) as Array).duplicate()


## Unknown group names are dropped.
func set_scene_tile_groups(ts: TileSet, source_id: int, scene_id: int, groups: Array) -> void:
	if !ts:
		return
	var ts_meta := _get_terrain_meta(ts)
	var all: Dictionary = ts_meta.get("scene_groups", {})
	var kept := []
	for g in groups:
		if _group_index(ts_meta, g) != -1 and not kept.has(g):
			kept.push_back(g)
	var key := _scene_tile_key(source_id, scene_id)
	if kept.is_empty():
		all.erase(key)
	else:
		all[key] = kept
	if all.is_empty():
		ts_meta.erase("scene_groups")
	else:
		ts_meta["scene_groups"] = all
	_set_terrain_meta(ts, ts_meta)


func _scene_tile_key(source_id: int, scene_id: int) -> String:
	return "%d:%d" % [source_id, scene_id]


## An empty new_name removes the group from every scene tile.
func _rename_scene_group(ts_meta: Dictionary, old_name: String, new_name: String) -> void:
	var all: Dictionary = ts_meta.get("scene_groups", {})
	for key in all.keys():
		var groups: Array = all[key]
		var at := groups.find(old_name)
		if at == -1:
			continue
		if new_name.is_empty():
			groups.remove_at(at)
		else:
			groups[at] = new_name
		if groups.is_empty():
			all.erase(key)
	if all.is_empty():
		ts_meta.erase("scene_groups")


func move_terrain_group(ts: TileSet, from_index: int, to_index: int) -> bool:
	if !ts or from_index < 0 or to_index < 0 or from_index == to_index:
		return false

	var ts_meta := _get_terrain_meta(ts)
	if from_index >= _groups_of(ts_meta).size() or to_index >= _groups_of(ts_meta).size():
		return false

	var g = ts_meta.groups[from_index]
	ts_meta.groups.remove_at(from_index)
	ts_meta.groups.insert(to_index, g)
	_set_terrain_meta(ts, ts_meta)
	return true


## Pass -1 to use the first terrain in the group as its icon.
func set_terrain_group_icon_terrain(ts: TileSet, index: int, terrain_id: int) -> bool:
	if !ts or index < 0:
		return false

	var ts_meta := _get_terrain_meta(ts)
	if index >= _groups_of(ts_meta).size():
		return false
	if terrain_id >= ts_meta.terrains.size():
		return false

	ts_meta.groups[index][1] = terrain_id
	_set_terrain_meta(ts, ts_meta)
	return true


## Returns the terrain icon or first tile, or null when neither exists.
func get_terrain_icon_texture(ts: TileSet, index: int) -> Texture2D:
	if !ts or index < 0:
		return null

	var terrain := get_terrain(ts, index)
	if !terrain.valid:
		return null

	if terrain.icon.has("path") and !terrain.icon.path.is_empty():
		return load(terrain.icon.path)

	if terrain.icon.has("source_id") and ts.has_source(terrain.icon.source_id):
		return _atlas_slice(ts.get_source(terrain.icon.source_id) as TileSetAtlasSource, terrain.icon.coord)

	if terrain.type == TerrainType.OBJECT:
		var block := _object_lone_texture(ts, index, terrain)
		if block:
			return block

	var tiles := get_tile_sources_in_terrain(ts, index)
	if !tiles.is_empty():
		return _atlas_slice(tiles[0].source as TileSetAtlasSource, tiles[0].coord)

	return null


func _object_lone_texture(ts: TileSet, index: int, terrain: Dictionary) -> AtlasTexture:
	var cfg: Dictionary = terrain.get("object", {})
	var sz: Array = cfg.get("size", [2, 2])
	var size := Vector2i(sz[0], sz[1])
	var lone: Array = cfg.get("lone", [])
	if lone.size() != 2:
		return null

	var origin := Vector2i(lone[0], lone[1])
	for b in ObjectTerrain.detect_blocks(ts, index, size):
		if b["rect"].position != origin:
			continue
		var src := ts.get_source(b["source_id"]) as TileSetAtlasSource
		if !src or !src.texture:
			return null
		var one_tile := src.get_tile_texture_region(origin, 0)
		var atlas := AtlasTexture.new()
		atlas.atlas = src.texture
		atlas.region = Rect2(one_tile.position, Vector2(one_tile.size) * Vector2(size))
		return atlas
	return null


func _atlas_slice(source: TileSetAtlasSource, coord: Vector2i) -> AtlasTexture:
	if !source or !source.texture:
		return null

	var atlas := AtlasTexture.new()
	atlas.atlas = source.texture
	atlas.region = source.get_tile_texture_region(coord, 0)
	return atlas


## The group must exist. Pass an empty string to remove the terrain from its group.
func set_terrain_group(ts: TileSet, index: int, group: String) -> bool:
	if !ts or index < 0:
		return false

	var ts_meta := _get_terrain_meta(ts)
	if index >= ts_meta.terrains.size():
		return false
	if !group.is_empty() and _group_index(ts_meta, group) == -1:
		return false

	var t = ts_meta.terrains[index]
	while t.size() < 6:
		t.push_back(DEFAULT_GROUP)
	t[5] = group

	_set_terrain_meta(ts, ts_meta)
	return true

#endregion


## Adds a new terrain to the [TileSet]. Returns [code]true[/code] if this is successful.
## [br][br]
## [code]type[/code] must be one of [enum TerrainType].[br]
## [code]categories[/code] is an indexed list of terrain categories that this terrain
## can match as. The indexes must be valid terrains of the CATEGORY type.
## [code]icon[/code] is a [Dictionary] with either a [code]path[/code] string pointing
## to a resource, or a [code]source_id[/code] [int] and a [code]coord[/code] [Vector2i].
## The former takes priority if both are present.
func add_terrain(ts: TileSet, terrain_name: String, color: Color, type: int, categories: Array = [], icon: Dictionary = {}, group: String = DEFAULT_GROUP, object: Dictionary = {}) -> bool:
	if !ts or terrain_name.is_empty() or type < 0 or type == TerrainType.DECORATION or type >= TerrainType.MAX:
		return false

	var ts_meta := _get_terrain_meta(ts)

	if !group.is_empty() and _group_index(ts_meta, group) == -1:
		return false

	# check categories
	if type == TerrainType.CATEGORY and !categories.is_empty():
		return false
	for c in categories:
		if c < 0 or c >= ts_meta.terrains.size() or ts_meta.terrains[c][2] != TerrainType.CATEGORY:
			return false
	
	if icon and not (icon.has("path") or (icon.has("source_id") and icon.has("coord"))):
		return false
	
	ts_meta.terrains.push_back([terrain_name, color, type, categories, icon, group, object])
	_set_terrain_meta(ts, ts_meta)
	_purge_cache(ts)
	return true


func set_terrain_object(ts: TileSet, index: int, object: Dictionary) -> bool:
	if !ts or index < 0:
		return false
	var ts_meta := _get_terrain_meta(ts)
	if index >= ts_meta.terrains.size():
		return false
	var t: Array = ts_meta.terrains[index]
	while t.size() < 7:
		if t.size() == 5:
			t.push_back(DEFAULT_GROUP)
		else:
			t.push_back({})
	t[6] = object
	_set_terrain_meta(ts, ts_meta)
	return true


## Removes the terrain at [code]index[/code] from the [TileSet]. Returns [code]true[/code]
## if the deletion is successful.
func remove_terrain(ts: TileSet, index: int) -> bool:
	if !ts or index < 0:
		return false
	
	var ts_meta := _get_terrain_meta(ts)
	if index >= ts_meta.terrains.size():
		return false
	
	if ts_meta.terrains[index][2] == TerrainType.CATEGORY:
		for t in ts_meta.terrains:
			t[3].erase(index)

	for g in _groups_of(ts_meta):
		if g[1] == index:
			g[1] = -1
		elif g[1] > index:
			g[1] -= 1

	for s in ts.get_source_count():
		var source := ts.get_source(ts.get_source_id(s)) as TileSetAtlasSource
		if !source:
			continue
		for t in source.get_tiles_count():
			var coord := source.get_tile_id(t)
			for a in source.get_alternative_tiles_count(coord):
				var alternate := source.get_alternative_tile_id(coord, a)
				var td := source.get_tile_data(coord, alternate)
				
				var td_meta := _get_tile_meta(td)
				if td_meta.type == TileCategory.NON_TERRAIN:
					continue
				
				if td_meta.type == index:
					_set_tile_meta(ts, td, null)
					continue
				
				if td_meta.type > index:
					td_meta.type -= 1
				
				for peering in td_meta.keys():
					if !(peering is int):
						continue
					
					var fixed_peering = []
					for p in td_meta[peering]:
						if p < index:
							fixed_peering.append(p)
						elif p > index:
							fixed_peering.append(p - 1)
					
					if fixed_peering.is_empty():
						td_meta.erase(peering)
					else:
						td_meta[peering] = fixed_peering
				
				var not_dict: Dictionary = td_meta.get("not", {})
				for peering in not_dict.keys():
					var fixed_not = []
					for p in not_dict[peering]:
						if p < index:
							fixed_not.append(p)
						elif p > index:
							fixed_not.append(p - 1)
					if fixed_not.is_empty():
						not_dict.erase(peering)
					else:
						not_dict[peering] = fixed_not
				if not_dict.is_empty():
					td_meta.erase("not")
				
				_set_tile_meta(ts, td, td_meta)
	
	ts_meta.terrains.remove_at(index)
	_set_terrain_meta(ts, ts_meta)
	
	_purge_cache(ts)	
	return true


## Returns the number of terrains in the [TileSet].
func terrain_count(ts: TileSet) -> int:
	if !ts:
		return 0
	
	var ts_meta := _get_terrain_meta(ts)
	return ts_meta.terrains.size()


## Retrieves information about the terrain at [code]index[/code] in the [TileSet].
## [br][br]
## Returns a [Dictionary] describing the terrain. If it succeeds, the key [code]valid[/code]
## will be set to [code]true[/code]. Other keys are [code]name[/code], [code]color[/code],
## [code]type[/code] (a [enum TerrainType]), [code]categories[/code] which is
## an [Array] of category type terrains that this terrain matches as, and
## [code]icon[/code] which is a [Dictionary] with a [code]path[/code] [String] or
## a [code]source_id[/code] [int] and [code]coord[/code] [Vector2i]
func get_terrain(ts: TileSet, index: int) -> Dictionary:
	if !ts or (index < TileCategory.EMPTY and index != TileCategory.SINGLE):
		return {valid = false}
	
	var ts_meta := _get_terrain_meta(ts)
	if index >= ts_meta.terrains.size():
		return {valid = false}
	
	var terrain := _get_cache_terrain(ts_meta, index)
	return {
		id = index,
		name = terrain[0],
		color = terrain[1],
		type = terrain[2],
		categories = terrain[3].duplicate(),
		icon = terrain[4].duplicate(),
		group = _terrain_group_of(terrain),
		object = _terrain_object_of(terrain),
		valid = true
	}


## Updates the details of the terrain at [code]index[/code] in [TileSet]. Returns
## [code]true[/code] if this succeeds.
## [br][br]
## If supplied, the [code]categories[/code] must be a list of indexes to other [code]CATEGORY[/code]
## type terrains.
## [code]icon[/code] is a [Dictionary] with either a [code]path[/code] string pointing
## to a resource, or a [code]source_id[/code] [int] and a [code]coord[/code] [Vector2i].
func set_terrain(ts: TileSet, index: int, terrain_name: String, color: Color, type: int, categories: Array = [], icon: Dictionary = {valid = false}, group = null, object: Dictionary = {}) -> bool:
	if !ts or terrain_name.is_empty() or index < 0 or type < 0 or type == TerrainType.DECORATION or type >= TerrainType.MAX:
		return false
	
	var ts_meta := _get_terrain_meta(ts)
	if index >= ts_meta.terrains.size():
		return false
	
	if type == TerrainType.CATEGORY and !categories.is_empty():
		return false
	for c in categories:
		if c < 0 or c == index or c >= ts_meta.terrains.size() or ts_meta.terrains[c][2] != TerrainType.CATEGORY:
			return false
	
	var icon_valid = icon.get("valid", "true")
	if icon_valid:
		match icon:
			{}, {"path"}, {"source_id", "coord"}: pass
			_: return false
	
	if type != TerrainType.CATEGORY:
		for t in ts_meta.terrains:
			t[3].erase(index)

	var new_group : String = _terrain_group_of(ts_meta.terrains[index]) if group == null else group
	if !new_group.is_empty() and _group_index(ts_meta, new_group) == -1:
		new_group = DEFAULT_GROUP

	ts_meta.terrains[index] = [terrain_name, color, type, categories, icon, new_group, object]
	_set_terrain_meta(ts, ts_meta)
	
	_clear_invalid_peering_types(ts)
	_purge_cache(ts)
	return true


## Swaps the terrains at [code]index1[/code] and [code]index2[/code] in [TileSet].
func swap_terrains(ts: TileSet, index1: int, index2: int) -> bool:
	if !ts or index1 < 0 or index2 < 0 or index1 == index2:
		return false
	
	var ts_meta := _get_terrain_meta(ts)
	if index1 >= ts_meta.terrains.size() or index2 >= ts_meta.terrains.size():
		return false
	
	for g in _groups_of(ts_meta):
		if g[1] == index1:
			g[1] = index2
		elif g[1] == index2:
			g[1] = index1

	for t in ts_meta.terrains:
		var has1 = t[3].has(index1)
		var has2 = t[3].has(index2)

		if has1 and !has2:
			t[3].erase(index1)
			t[3].push_back(index2)
		elif has2 and !has1:
			t[3].erase(index2)
			t[3].push_back(index1)
	
	for s in ts.get_source_count():
		var source := ts.get_source(ts.get_source_id(s)) as TileSetAtlasSource
		if !source:
			continue
		for t in source.get_tiles_count():
			var coord := source.get_tile_id(t)
			for a in source.get_alternative_tiles_count(coord):
				var alternate := source.get_alternative_tile_id(coord, a)
				var td := source.get_tile_data(coord, alternate)
				
				var td_meta := _get_tile_meta(td)
				if td_meta.type == TileCategory.NON_TERRAIN:
					continue
				
				if td_meta.type == index1:
					td_meta.type = index2
				elif td_meta.type == index2:
					td_meta.type = index1
				
				for peering in td_meta.keys():
					if !(peering is int):
						continue
					
					var fixed_peering = []
					for p in td_meta[peering]:
						if p == index1:
							fixed_peering.append(index2)
						elif p == index2:
							fixed_peering.append(index1)
						else:
							fixed_peering.append(p)
					td_meta[peering] = fixed_peering
				
				var not_dict: Dictionary = td_meta.get("not", {})
				for peering in not_dict:
					var fixed_not = []
					for p in not_dict[peering]:
						if p == index1:
							fixed_not.append(index2)
						elif p == index2:
							fixed_not.append(index1)
						else:
							fixed_not.append(p)
					not_dict[peering] = fixed_not
				
				_set_tile_meta(ts, td, td_meta)
	
	var temp = ts_meta.terrains[index1]
	ts_meta.terrains[index1] = ts_meta.terrains[index2]
	ts_meta.terrains[index2] = temp
	_set_terrain_meta(ts, ts_meta)
	
	_purge_cache(ts)
	return true


# Terrain tile data

## For a tile in a [TileSet] as specified by [TileData], set the terrain associated
## with that tile to [code]type[/code], which is an index of an existing terrain.
## Returns [code]true[/code] on success.
func set_tile_terrain_type(ts: TileSet, td: TileData, type: int) -> bool:
	if !ts or !td or type < TileCategory.NON_TERRAIN:
		return false
	
	var td_meta = _get_tile_meta(td)
	td_meta.type = type
	if type == TileCategory.NON_TERRAIN:
		td_meta = null
	elif type >= TileCategory.EMPTY and type < terrain_count(ts):
		var terrain := get_terrain(ts, type)
		var valid_peering = data.get_terrain_peering_cells(ts, terrain.type)
		for key in td_meta.keys():
			if key is int and not valid_peering.has(key):
				td_meta.erase(key)
		var not_dict: Dictionary = td_meta.get("not", {})
		for key in not_dict.keys():
			if not valid_peering.has(key):
				not_dict.erase(key)
		if not_dict.is_empty():
			td_meta.erase("not")
	_set_tile_meta(ts, td, td_meta)
	_purge_cache(ts)
	return true


## Returns the terrain type associated with tile specified by [TileData]. Returns
## -1 if the tile has no associated terrain.
func get_tile_terrain_type(td: TileData) -> int:
	if !td:
		return TileCategory.ERROR
	var td_meta := _get_tile_meta(td)
	return td_meta.type


## For a tile represented by [TileData] [code]td[/code] in [TileSet]
## [code]ts[/code], sets [enum SymmetryType] [code]type[/code]. This controls
## how the tile is rotated/mirrored during placement.
func set_tile_symmetry_type(ts: TileSet, td: TileData, type: int) -> bool:
	if !ts or !td or type < SymmetryType.NONE or type > SymmetryType.ALL:
		return false
	
	var td_meta := _get_tile_meta(td)
	if td_meta.type == TileCategory.NON_TERRAIN:
		return false
	
	td_meta.symmetry = type
	_set_tile_meta(ts, td, td_meta)
	_purge_cache(ts)
	return true


## For a tile [code]td[/code], returns the [enum SymmetryType] which that
## tile uses.
func get_tile_symmetry_type(td: TileData) -> int:
	if !td:
		return SymmetryType.NONE
	
	var td_meta := _get_tile_meta(td)
	return td_meta.get("symmetry", SymmetryType.NONE)


## Returns an Array of all [TileData] tiles included in the specified
## terrain [code]type[/code] for the [TileSet] [code]ts[/code]
func get_tiles_in_terrain(ts: TileSet, type: int) -> Array[TileData]:
	var result:Array[TileData] = []
	if !ts or type < TileCategory.EMPTY:
		return result
	
	var cache := _get_cache(ts)
	if type > cache.size():
		return result
	
	var tiles = cache[type]
	if !tiles:
		return result
	for c in tiles:
		if c[0] < 0:
			continue
		var source := ts.get_source(c[0]) as TileSetAtlasSource
		var td := source.get_tile_data(c[1], c[2])
		result.push_back(td)
	
	return result


## Returns an [Array] of [Dictionary] items including information about each 
## tile included in the specified terrain [code]type[/code] for 
## the [TileSet] [code]ts[/code]. Each Dictionary item includes 
## [TileSetAtlasSource] [code]source[/code], [TileData] [code]td[/code], 
## [Vector2i] [code]coord[/code], and [int] [code]alt_id[/code].
func get_tile_sources_in_terrain(ts: TileSet, type: int) -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	
	var cache := _get_cache(ts)
	var tiles = cache[type]
	if !tiles:
		return result
	for c in tiles:
		if c[0] < 0:
			continue
		var source := ts.get_source(c[0]) as TileSetAtlasSource
		if not source:
			continue
		var td := source.get_tile_data(c[1], c[2])
		result.push_back({
			source = source,
			td = td,
			coord = c[1],
			alt_id = c[2]
		})
	
	return result


## For a [TileSet]'s tile, specified by [TileData], add terrain [code]type[/code]
## (an index of a terrain) to match this tile in direction [code]peering[/code],
## which is of type [enum TileSet.CellNeighbor]. Returns [code]true[/code] on success.
func add_tile_peering_type(ts: TileSet, td: TileData, peering: int, type: int) -> bool:
	if !ts or !td or peering < 0 or peering > 15 or type < TileCategory.EMPTY:
		return false
	
	var ts_meta := _get_terrain_meta(ts)
	var td_meta := _get_tile_meta(td)
	if td_meta.type < TileCategory.EMPTY or td_meta.type >= ts_meta.terrains.size():
		return false
	
	# A type can't be both required and forbidden on the same side
	var not_dict: Dictionary = td_meta.get("not", {})
	if not_dict.has(peering) and not_dict[peering].has(type):
		return false
	
	if !td_meta.has(peering):
		td_meta[peering] = [type]
	elif !td_meta[peering].has(type):
		td_meta[peering].append(type)
	else:
		return false
	_set_tile_meta(ts, td, td_meta)
	_purge_cache(ts)
	return true


## For a [TileSet]'s tile, specified by [TileData], remove terrain [code]type[/code]
## from matching in direction [code]peering[/code], which is of type [enum TileSet.CellNeighbor].
## Returns [code]true[/code] on success.
func remove_tile_peering_type(ts: TileSet, td: TileData, peering: int, type: int) -> bool:
	if !ts or !td or peering < 0 or peering > 15 or type < TileCategory.EMPTY:
		return false
	
	var td_meta := _get_tile_meta(td)
	if !td_meta.has(peering):
		return false
	if !td_meta[peering].has(type):
		return false
	td_meta[peering].erase(type)
	if td_meta[peering].is_empty():
		td_meta.erase(peering)
	_set_tile_meta(ts, td, td_meta)
	_purge_cache(ts)
	return true


## A type can't be both required and forbidden on one side.
func add_tile_not_peering_type(ts: TileSet, td: TileData, peering: int, type: int) -> bool:
	if !ts or !td or peering < 0 or peering > 15 or type < TileCategory.EMPTY:
		return false
	
	var ts_meta := _get_terrain_meta(ts)
	var td_meta := _get_tile_meta(td)
	if td_meta.type < TileCategory.EMPTY or td_meta.type >= ts_meta.terrains.size():
		return false
	if td_meta.has(peering) and td_meta[peering].has(type):
		return false
	
	if !td_meta.has("not"):
		td_meta["not"] = {}
	var not_dict: Dictionary = td_meta["not"]
	if !not_dict.has(peering):
		not_dict[peering] = [type]
	elif !not_dict[peering].has(type):
		not_dict[peering].append(type)
	else:
		return false
	_set_tile_meta(ts, td, td_meta)
	_purge_cache(ts)
	return true


func remove_tile_not_peering_type(ts: TileSet, td: TileData, peering: int, type: int) -> bool:
	if !ts or !td or peering < 0 or peering > 15 or type < TileCategory.EMPTY:
		return false
	
	var td_meta := _get_tile_meta(td)
	var not_dict: Dictionary = td_meta.get("not", {})
	if !not_dict.has(peering) or !not_dict[peering].has(type):
		return false
	not_dict[peering].erase(type)
	if not_dict[peering].is_empty():
		not_dict.erase(peering)
	if not_dict.is_empty():
		td_meta.erase("not")
	_set_tile_meta(ts, td, td_meta)
	_purge_cache(ts)
	return true


## For the tile specified by [TileData], return an [Array] of peering directions
## for which terrain matching is set up. These will be of type [enum TileSet.CellNeighbor].
func tile_peering_keys(td: TileData) -> Array:
	if !td:
		return []
	
	var td_meta := _get_tile_meta(td)
	var result := []
	for k in td_meta:
		if k is int:
			result.append(k)
	for k in td_meta.get("not", {}):
		if k not in result:
			result.append(k)
	return result


## For the tile specified by [TileData], return the [Array] of terrains that match
## for the direction [code]peering[/code] which should be of type [enum TileSet.CellNeighbor].
func tile_peering_types(td: TileData, peering: int) -> Array:
	if !td or peering < 0 or peering > 15:
		return []
	
	var td_meta := _get_tile_meta(td)
	return td_meta[peering].duplicate() if td_meta.has(peering) else []


func tile_not_peering_types(td: TileData, peering: int) -> Array:
	if !td or peering < 0 or peering > 15:
		return []
	
	var not_dict: Dictionary = _get_tile_meta(td).get("not", {})
	return not_dict[peering].duplicate() if not_dict.has(peering) else []


## For the tile specified by [TileData], return the [Array] of peering directions
## for the specified terrain type [code]type[/code].
func tile_peering_for_type(td: TileData, type: int) -> Array:
	if !td:
		return []
	
	var td_meta := _get_tile_meta(td)
	var result := []
	var sides := tile_peering_keys(td)
	for side in sides:
		if td_meta.has(side) and td_meta[side].has(type):
			result.push_back(side)
	
	result.sort()
	return result


# Painting

## Applies the terrain [code]type[/code] to the [TileMapLayer] for the [Vector2i]
## [code]coord[/code]. Returns [code]true[/code] if it succeeds. Use [method set_cells]
## to change multiple tiles at once.
## [br][br]
## Use terrain type -1 to erase cells.
func set_cell(tm: TileMapLayer, coord: Vector2i, type: int, anchor := Vector2i.ZERO) -> bool:
	if !tm or !tm.tile_set or (type < TileCategory.EMPTY and type != TileCategory.SINGLE):
		return false
	
	if type == TileCategory.EMPTY:
		tm.erase_cell(coord)
		return true
	
	var block := single_block_of(tm.tile_set, type)
	if not block.is_empty():
		_set_single_cell(tm, coord, block, anchor)
		return true
	if type < 0:
		return false
	
	var cache := _get_cache(tm.tile_set)
	if type >= cache.size():
		return false
	
	if cache[type].is_empty():
		return false
	
	var tile = cache[type].front()
	tm.set_cell(coord, tile[0], tile[1], tile[2])
	return true


## Applies the terrain [code]type[/code] to the [TileMapLayer] for the
## [Vector2i] [code]coords[/code]. Returns [code]true[/code] if it succeeds.
## [br][br]
## Note that this does not cause the terrain solver to run, so this will just place
## an arbitrary terrain-associated tile in the given position. To run the solver,
## you must set the require cells, and then call either [method update_terrain_cell],
## [method update_terrain_cels], or [method update_terrain_area].
## [br][br]
## If you want to prepare changes to the tiles in advance, you can use [method create_terrain_changeset]
## and the associated functions.
## [br][br]
## Use terrain type -1 to erase cells.
func set_cells(tm: TileMapLayer, coords: Array, type: int, anchor := Vector2i.ZERO) -> bool:
	if !tm or !tm.tile_set or (type < TileCategory.EMPTY and type != TileCategory.SINGLE):
		return false
	
	if type == TileCategory.EMPTY:
		for c in coords:
			tm.erase_cell(c)
		return true
	
	var block := single_block_of(tm.tile_set, type)
	if not block.is_empty():
		for c in coords:
			_set_single_cell(tm, c, block, anchor)
		return true
	if type < 0:
		return false
	
	var cache := _get_cache(tm.tile_set)
	if type >= cache.size():
		return false
	
	if cache[type].is_empty():
		return false
	
	var tile = cache[type].front()
	for c in coords:
		tm.set_cell(c, tile[0], tile[1], tile[2])
	return true


## Replaces an existing tile on the [TileMapLayer] for the [Vector2i]
## [code]coord[/code] with a new tile in the provided terrain [code]type[/code] 
## *only if* there is a tile with a matching set of peering sides in this terrain.
## Returns [code]true[/code] if any tiles were changed. Use [method replace_cells]
## to replace multiple tiles at once.
func replace_cell(tm: TileMapLayer, coord: Vector2i, type: int, anchor := Vector2i.ZERO) -> bool:
	if !tm or !tm.tile_set or (type < 0 and type != TileCategory.SINGLE):
		return false
	
	var block := single_block_of(tm.tile_set, type)
	if not block.is_empty():
		if tm.get_cell_source_id(coord) == -1:
			return false
		return _set_single_cell(tm, coord, block, anchor)
	if type < 0:
		return false
	
	var cache := _get_cache(tm.tile_set)
	if type >= cache.size():
		return false
	
	if cache[type].is_empty():
		return false
	
	var td = tm.get_cell_tile_data(coord)
	if !td:
		return false
	
	var ts_meta := _get_terrain_meta(tm.tile_set)
	var categories = ts_meta.terrains[type][3]
	var check_types = [type] + categories
	
	for check_type in check_types:
		var placed_peering = tile_peering_for_type(td, check_type)
		for pt in get_tiles_in_terrain(tm.tile_set, type):
			var check_peering := tile_peering_for_type(pt, check_type)
			if placed_peering == check_peering:
				var tile = cache[type].front()
				tm.set_cell(coord, tile[0], tile[1], tile[2])
				return true
	
	return false


## Replaces existing tiles on the [TileMapLayer] for the [Vector2i]
## [code]coords[/code] with new tiles in the provided terrain [code]type[/code] 
## *only if* there is a tile with a matching set of peering sides in this terrain
## for each tile.
## Returns [code]true[/code] if any tiles were changed.
func replace_cells(tm: TileMapLayer, coords: Array, type: int, anchor := Vector2i.ZERO) -> bool:
	if !tm or !tm.tile_set or (type < 0 and type != TileCategory.SINGLE):
		return false
	
	var block := single_block_of(tm.tile_set, type)
	if not block.is_empty():
		var any := false
		for c in coords:
			if tm.get_cell_source_id(c) == -1:
				continue
			any = _set_single_cell(tm, c, block, anchor) or any
		return any
	if type < 0:
		return false
	
	var cache := _get_cache(tm.tile_set)
	if type >= cache.size():
		return false
	
	if cache[type].is_empty():
		return false
	
	var ts_meta := _get_terrain_meta(tm.tile_set)
	var categories = ts_meta.terrains[type][3]
	var check_types = [type] + categories
	
	var changed = false
	var potential_tiles = get_tiles_in_terrain(tm.tile_set, type)
	for c in coords:
		var found = false
		var td = tm.get_cell_tile_data(c)
		if !td:
			continue
		for check_type in check_types:
			var placed_peering = tile_peering_for_type(td, check_type)
			for pt in potential_tiles:
				var check_peering = tile_peering_for_type(pt, check_type)
				if placed_peering == check_peering:
					var tile = cache[type].front()
					tm.set_cell(c, tile[0], tile[1], tile[2])
					changed = true
					found = true
					break
			
			if found:
				break
	
	return changed


## Returns the terrain type detected in the [TileMapLayer] at specified [Vector2i]
## [code]coord[/code]. Returns -1 if tile is not valid or does not contain a
## tile associated with a terrain.
func get_cell(tm: TileMapLayer, coord: Vector2i) -> int:
	if !tm or !tm.tile_set:
		return TileCategory.ERROR
	
	if tm.get_cell_source_id(coord) == -1:
		return TileCategory.EMPTY
	
	var t := tm.get_cell_tile_data(coord)
	if !t:
		return TileCategory.NON_TERRAIN
	
	var type: int = _get_tile_meta(t).type
	if type == TileCategory.NON_TERRAIN:
		type = _single_terrain_at(tm.tile_set, tm.get_cell_source_id(coord),
			tm.get_cell_atlas_coords(coord), tm.get_cell_alternative_tile(coord))
	return type


func _single_terrain_at(ts: TileSet, source: int, coord: Vector2i, alternate: int) -> int:
	var ts_meta := _get_terrain_meta(ts)
	var reserved := single_block_of(ts, TileCategory.SINGLE)
	if not reserved.is_empty() and reserved.source == source and reserved.alt == alternate \
			and Rect2i(reserved.origin, reserved.size).has_point(coord):
		return TileCategory.SINGLE
	for i in ts_meta.terrains.size():
		if ts_meta.terrains[i][2] != TerrainType.SINGLE:
			continue
		var one := single_tile_of(ts, i)
		if one.size() == 3 and one[0] == source and one[1] == coord and one[2] == alternate:
			return i
	return TileCategory.NON_TERRAIN


## Terrain cells match by terrain ID; unmarked cells match by tile. A brush block remains one
## region.
func same_fill_region(tm: TileMapLayer, a: Vector2i, b: Vector2i) -> bool:
	var type := get_cell(tm, a)
	if type != get_cell(tm, b):
		return false
	if type != TileCategory.NON_TERRAIN:
		return true
	return tm.get_cell_source_id(a) == tm.get_cell_source_id(b) \
		and tm.get_cell_atlas_coords(a) == tm.get_cell_atlas_coords(b) \
		and tm.get_cell_alternative_tile(a) == tm.get_cell_alternative_tile(b)


## Returns the nearest precedcng sibling with a visible tile here; generated children are excluded.
func layer_below(tm: TileMapLayer, coord: Vector2i) -> TileMapLayer:
	if tm == null or tm.get_parent() == null:
		return null
	var siblings := tm.get_parent().get_children()
	var mine := tm.get_index()
	for i in range(mine - 1, -1, -1):
		var other = siblings[i]
		if other is TileMapLayer and other.visible and other.get_cell_source_id(coord) != -1:
			return other
	return null


func top_layer_at(tm: TileMapLayer, coord: Vector2i) -> TileMapLayer:
	if tm == null:
		return null
	if tm.get_parent() == null:
		return tm if tm.get_cell_source_id(coord) != -1 else null
	var siblings := tm.get_parent().get_children()
	for i in range(siblings.size() - 1, -1, -1):
		var other = siblings[i]
		if other is TileMapLayer and other.visible and other.get_cell_source_id(coord) != -1:
			return other
	return null


func same_visible_region(tm: TileMapLayer, a: Vector2i, b: Vector2i) -> bool:
	var top_a := top_layer_at(tm, a)
	var top_b := top_layer_at(tm, b)
	if top_a != top_b:
		return false
	if top_a == null:
		return true
	return same_fill_region(top_a, a, b)


## Runs the tile solving algorithm on the [TileMapLayer] for the given
## [Vector2i] coordinates in the [code]cells[/code] parameter. By default,
## the surrounding cells are also solved, but this can be adjusted by passing [code]false[/code]
## to the [code]and_surrounding_cells[/code] parameter.
## [br][br]
## See also [method update_terrain_area] and [method update_terrain_cell].
func update_terrain_cells(tm: TileMapLayer, cells: Array, and_surrounding_cells := true) -> void:
	if !tm or !tm.tile_set:
		return
	
	if and_surrounding_cells:
		cells = _widen(tm, cells)
	var needed_cells := _widen(tm, cells)
	
	var types := {}
	for c in needed_cells:
		types[c] = get_cell(tm, c)
	
	var ts_meta := _get_terrain_meta(tm.tile_set)
	var cache := _get_cache(tm.tile_set)
	for c in cells:
		_update_tile_immediate(tm, c, ts_meta, types, cache)


## Runs the tile solving algorithm on the [TileMapLayer] for the given [Vector2i]
## [code]cell[/code]. By default, the surrounding cells are also solved, but
## this can be adjusted by passing [code]false[/code] to the [code]and_surrounding_cells[/code]
## parameter. This calls through to [method update_terrain_cells].
func update_terrain_cell(tm: TileMapLayer, cell: Vector2i, and_surrounding_cells := true) -> void:
	update_terrain_cells(tm, [cell], and_surrounding_cells)


## Runs the tile solving algorithm on the [TileMapLayer] for the given [Rect2i]
## [code]area[/code]. By default, the surrounding cells are also solved, but
## this can be adjusted by passing [code]false[/code] to the [code]and_surrounding_cells[/code]
## parameter.
## [br][br]
## See also [method update_terrain_cells].
func update_terrain_area(tm: TileMapLayer, area: Rect2i, and_surrounding_cells := true) -> void:
	if !tm or !tm.tile_set:
		return
	
	# Normalize area and extend so tiles cover inclusive space
	area = area.abs()
	area.size += Vector2i.ONE
	
	var edges = []
	for x in range(area.position.x, area.end.x):
		edges.append(Vector2i(x, area.position.y))
		edges.append(Vector2i(x, area.end.y - 1))
	for y in range(area.position.y + 1, area.end.y - 1):
		edges.append(Vector2i(area.position.x, y))
		edges.append(Vector2i(area.end.x - 1, y))
	
	var additional_cells := []
	var needed_cells := _widen_with_exclusion(tm, edges, area)
	
	if and_surrounding_cells:
		additional_cells = needed_cells
		needed_cells = _widen_with_exclusion(tm, needed_cells, area)
	
	var types := {}
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var coord = Vector2i(x, y)
			types[coord] = get_cell(tm, coord)
	for c in needed_cells:
		types[c] = get_cell(tm, c)
	
	var ts_meta := _get_terrain_meta(tm.tile_set)
	var cache := _get_cache(tm.tile_set)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var coord := Vector2i(x, y)
			_update_tile_immediate(tm, coord, ts_meta, types, cache)
	for c in additional_cells:
		_update_tile_immediate(tm, c, ts_meta, types, cache)


## For a [TileMapLayer], create a changeset that will
## be calculated via a [WorkerThreadPool], so it will not delay processing the current
## frame or affect the framerate.
## [br][br]
## The [code]paint[/code] parameter must be a [Dictionary] with keys of type [Vector2i]
## representing map coordinates, and integer values representing terrain types.
## [br][br]
## Returns a [Dictionary] with internal details. See also [method is_terrain_changeset_ready],
## [method apply_terrain_changeset], and [method wait_for_terrain_changeset].
func create_terrain_changeset(tm: TileMapLayer, paint: Dictionary) -> Dictionary:
	# Force cache rebuild if required
	var _cache := _get_cache(tm.tile_set)
	
	var cells := paint.keys()
	var needed_cells := _widen(tm, cells)
	
	var types := {}
	for c in needed_cells:
		types[c] = paint[c] if paint.has(c) else get_cell(tm, c)
	
	var placements := []
	placements.resize(cells.size())
	
	var ts_meta := _get_terrain_meta(tm.tile_set)
	var work := func(n: int):
		placements[n] = _update_tile_deferred(tm, cells[n], ts_meta, types, _cache)
	
	return {
		"valid": true,
		"tilemap": tm,
		"cells": cells,
		"placements": placements,
		"group_id": WorkerThreadPool.add_group_task(work, cells.size(), -1, false, "BetterTerrain")
	}


## Returns [code]true[/code] if a changeset created by [method create_terrain_changeset]
## has finished the threaded calculation and is ready to be applied by [method apply_terrain_changeset].
## See also [method wait_for_terrain_changeset].
func is_terrain_changeset_ready(change: Dictionary) -> bool:
	if !change.has("group_id"):
		return false
	
	return WorkerThreadPool.is_group_task_completed(change.group_id)


## Blocks until a changeset created by [method create_terrain_changeset] finishes.
## This is useful to tidy up threaded work in the event that a node is to be removed
## whilst still waiting on threads.
## [br][br]
## Usage example:
## [codeblock]
## func _exit_tree():
##     if changeset.valid:
##         BetterTerrain.wait_for_terrain_changeset(changeset)
## [/codeblock]
func wait_for_terrain_changeset(change: Dictionary) -> void:
	if change.has("group_id"):
		WorkerThreadPool.wait_for_group_task_completion(change.group_id)


## Apply the changes in a changeset created by [method create_terrain_changeset]
## once it is confirmed by [method is_terrain_changeset_ready]. The changes will
## be applied to the [TileMapLayer] that the changeset was initialized with.
## [br][br]
## Completed changesets can be applied multiple times, and stored for as long as
## needed once calculated.
func apply_terrain_changeset(change: Dictionary) -> void:
	for n in change.cells.size():
		var placement = change.placements[n]
		if placement:
			change.tilemap.set_cell(change.cells[n], placement[0], placement[1], placement[2])
