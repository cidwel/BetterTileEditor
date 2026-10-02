@tool
extends RefCounted
## Tile custom data, as Godot keeps it: TileSet custom data layers, one value per tile and alternative.

const Collisions := preload("res://addons/better-tile-editor/editor/Collisions.gd")
const ALT_SCOPE_SETTING := "editors/better_terrain/custom_data_alternatives"
## Named configurations, kept in the tile set: [{name, values: {field name: value}}].
const PRESETS_META := &"_better_terrain_data_presets"

## Fields a tile names on itself before the rest become "+N".
const SUMMARY_LINES := 5

## Types offered when adding a field; others are shown but edited in the inspector.
const TYPES := [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_COLOR, TYPE_VECTOR2, TYPE_VECTOR2I]
const TYPE_NAMES := {
	TYPE_BOOL: "Bool", TYPE_INT: "Int", TYPE_FLOAT: "Float", TYPE_STRING: "String",
	TYPE_COLOR: "Color", TYPE_VECTOR2: "Vector2", TYPE_VECTOR2I: "Vector2i",
}


static func type_name(type: int) -> String:
	return TYPE_NAMES.get(type, type_string(type))


static func editable(type: int) -> bool:
	return type in TYPES


## What a tile holds before anything is set: Godot's default for the type.
static func default_for(type: int) -> Variant:
	match type:
		TYPE_BOOL: return false
		TYPE_INT: return 0
		TYPE_FLOAT: return 0.0
		TYPE_STRING: return ""
		TYPE_COLOR: return Color()
		TYPE_VECTOR2: return Vector2()
		TYPE_VECTOR2I: return Vector2i()
	return null


## Whether a value stands out from the default, so the tile is marked as having it.
static func is_set(value: Variant, type: int) -> bool:
	if value == null:
		return false
	var fallback: Variant = default_for(type)
	return fallback == null or value != fallback


static func format(value: Variant) -> String:
	if value is float:
		return str(snappedf(value, 0.001))
	if value is Color:
		return "#" + (value as Color).to_html(false)
	if value is String:
		return "\"%s\"" % value
	return str(value)


static func field_names(ts: TileSet) -> Array:
	var out := []
	for i in ts.get_custom_data_layers_count():
		out.append(ts.get_custom_data_layer_name(i))
	return out


## Which alternatives get a value written to the tile: all of them unless told otherwise,
## since a turned water tile is water too.
static func alt_scope() -> int:
	var settings := EditorInterface.get_editor_settings()
	return int(settings.get_setting(ALT_SCOPE_SETTING)) if settings.has_setting(ALT_SCOPE_SETTING) else Collisions.AltScope.ALL


static func set_alt_scope(scope: int) -> void:
	EditorInterface.get_editor_settings().set_setting(ALT_SCOPE_SETTING, scope)


## The values of some fields on some alternatives: [[alt, {field index: value}], ...].
static func tile_state(src: TileSetAtlasSource, coords: Vector2i, fields: Array, alts: Array) -> Array:
	var out := []
	for alt: int in alts:
		var td := src.get_tile_data(coords, alt)
		var values := {}
		for field: int in fields:
			var value: Variant = td.get_custom_data_by_layer_id(field)
			values[field] = value.duplicate() if value is Array or value is Dictionary else value
		out.append([alt, values])
	return out


static func apply_state(src: TileSetAtlasSource, coords: Vector2i, state: Array) -> void:
	if not src.has_tile(coords):
		return
	for entry: Array in state:
		if not src.has_alternative_tile(coords, entry[0]):
			continue
		var td := src.get_tile_data(coords, entry[0])
		for field: int in entry[1]:
			td.set_custom_data_by_layer_id(field, entry[1][field])


## The same values ({field index: value}) on the given alternatives.
static func values_state(values: Dictionary, alts: Array) -> Array:
	var out := []
	for alt: int in alts:
		out.append([alt, values.duplicate()])
	return out


## Every tile's value of one field, to put back when the field is removed or retyped:
## [[source_id, coords, alt, value], ...] for every alternative of every atlas tile.
static func field_snapshot(ts: TileSet, field: int) -> Array:
	var out := []
	for s in ts.get_source_count():
		var source_id := ts.get_source_id(s)
		var src := ts.get_source(source_id) as TileSetAtlasSource
		if src == null:
			continue
		for t in src.get_tiles_count():
			var coords := src.get_tile_id(t)
			for a in src.get_alternative_tiles_count(coords):
				var alt := src.get_alternative_tile_id(coords, a)
				out.append([source_id, coords, alt, src.get_tile_data(coords, alt).get_custom_data_by_layer_id(field)])
	return out


static func restore_field(ts: TileSet, field: int, snapshot: Array) -> void:
	for entry: Array in snapshot:
		var src := ts.get_source(entry[0]) as TileSetAtlasSource
		if src != null and src.has_tile(entry[1]) and src.has_alternative_tile(entry[1], entry[2]):
			src.get_tile_data(entry[1], entry[2]).set_custom_data_by_layer_id(field, entry[3])


## A tile's fields, one line each, for tooltips.
static func describe(ts: TileSet, td: TileData) -> String:
	var lines := []
	for i in ts.get_custom_data_layers_count():
		lines.append("%s = %s" % [ts.get_custom_data_layer_name(i), format(td.get_custom_data_by_layer_id(i))])
	return "\n".join(lines) if not lines.is_empty() else "No custom data fields."


## Whether a tile holds every value of a brush ({field index: value}).
static func matches(td: TileData, brush: Dictionary) -> bool:
	if brush.is_empty():
		return false
	for field: int in brush:
		var value: Variant = td.get_custom_data_by_layer_id(field)
		var wanted: Variant = brush[field]
		if value is float or wanted is float:
			if not is_equal_approx(float(value), float(wanted)):
				return false
		elif value != wanted:
			return false
	return true


## The field's name, with its value unless it is a bool: what a lit tile shows.
static func label(ts: TileSet, td: TileData, field: int) -> String:
	var field_name := ts.get_custom_data_layer_name(field)
	if ts.get_custom_data_layer_type(field) == TYPE_BOOL:
		return field_name
	return "%s = %s" % [field_name, format(td.get_custom_data_by_layer_id(field))]


## What a tile holds, a line per set field: up to SUMMARY_LINES, then "+N" for the rest.
static func summary(ts: TileSet, td: TileData) -> String:
	var held := tile_values(ts, td).keys()
	var lines := []
	for field: int in held.slice(0, SUMMARY_LINES):
		lines.append(label(ts, td, field))
	if held.size() > SUMMARY_LINES:
		lines.append("+%d" % (held.size() - SUMMARY_LINES))
	return "\n".join(lines)


## Every editable field of a tile, unset ones at their default: picked as a brush, it paints the
## tile's configuration exactly instead of adding to what a tile already holds.
static func whole_config(ts: TileSet, td: TileData) -> Dictionary:
	var out := {}
	for i in ts.get_custom_data_layers_count():
		var type := ts.get_custom_data_layer_type(i)
		if editable(type):
			out[i] = td.get_custom_data_by_layer_id(i) if is_set(td.get_custom_data_by_layer_id(i), type) else default_for(type)
	return out


## The configuration a tile holds: {field index: value} for its fields not at their default.
static func tile_values(ts: TileSet, td: TileData) -> Dictionary:
	var out := {}
	for i in ts.get_custom_data_layers_count():
		var value: Variant = td.get_custom_data_by_layer_id(i)
		if is_set(value, ts.get_custom_data_layer_type(i)):
			out[i] = value
	return out


static func presets(ts: TileSet) -> Array:
	return (ts.get_meta(PRESETS_META, []) as Array).duplicate(true)


## A brush ({field index: value}) as a preset's values, by field name so it outlives reordering.
static func to_named(ts: TileSet, brush: Dictionary) -> Dictionary:
	var out := {}
	for field: int in brush:
		out[ts.get_custom_data_layer_name(field)] = brush[field]
	return out


## A preset's values as a brush; fields the tile set no longer has, or of another type now, are left out.
static func from_named(ts: TileSet, values: Dictionary) -> Dictionary:
	var out := {}
	for field_name: String in values:
		var field := ts.get_custom_data_layer_by_name(field_name)
		if field < 0:
			continue
		var value: Variant = values[field_name]
		var type := ts.get_custom_data_layer_type(field)
		if typeof(value) == type or (type == TYPE_FLOAT and value is int):
			out[field] = value
	return out


## The preset list with one put in (replacing one of the same name) or taken out (values null).
static func with_preset(list: Array, preset_name: String, values: Variant) -> Array:
	var out := list.duplicate(true)
	for i in range(out.size() - 1, -1, -1):
		if out[i].name == preset_name:
			if values == null:
				out.remove_at(i)
			else:
				out[i] = {name = preset_name, values = values}
			return out
	if values != null:
		out.append({name = preset_name, values = values})
	return out


static func set_presets(ts: TileSet, list: Array) -> void:
	if list.is_empty():
		ts.remove_meta(PRESETS_META)
	else:
		ts.set_meta(PRESETS_META, list.duplicate(true))


static func numeric(type: int) -> bool:
	return type == TYPE_INT or type == TYPE_FLOAT


## Heatmap colour of a number within the field's range: blue low, yellow middle, red high.
static func heat(value: float, range_: Vector2) -> Color:
	var t := 0.5 if is_equal_approx(range_.x, range_.y) else clampf((value - range_.x) / (range_.y - range_.x), 0.0, 1.0)
	if t < 0.5:
		return Color(0.25, 0.5, 1.0).lerp(Color(1.0, 0.85, 0.25), t * 2.0)
	return Color(1.0, 0.85, 0.25).lerp(Color(1.0, 0.3, 0.2), (t - 0.5) * 2.0)

