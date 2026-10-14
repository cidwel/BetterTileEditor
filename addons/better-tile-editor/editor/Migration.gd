@tool
extends RefCounted

## Moves a project off the BetterTerrain autoload: calls become BetterTileEditor.*, a global
## class that needs no autoload. Original files are copied to BACKUP_DIR first.

const AUTOLOAD_NAME := "BetterTerrain"
const OWN_DIR := "res://addons/better-tile-editor"
const BACKUP_DIR := "res://.godot/better_tile_editor_migration"
const NEW_NAME := "BetterTileEditor"

# get_node("/root/BetterTerrain") and friends return the autoload; the class stands in for it.
static var _lookup := _compile(r'(?:get_node|get_node_or_null)\(\s*["\'](?:/root/)?BetterTerrain["\']\s*\)|\$["\']/root/BetterTerrain["\']')
static var _identifier := _compile(r'(?<![\w"\'/.])BetterTerrain\b(?![\w"\'\]])')
static var _leftover := _compile(r'(?<![\[\w])BetterTerrain\b(?![\]\w]|\.gd)')


static func _compile(pattern: String) -> RegEx:
	var re := RegEx.new()
	re.compile(pattern)
	return re


## Returns {files: {path: replacements}, manual: {path: leftover count}, autoload: bool}.
static func scan() -> Dictionary:
	var files := {}
	var manual := {}
	for path in _scripts("res://"):
		var text := FileAccess.get_file_as_string(path)
		var migrated := _migrate_text(text)
		if migrated.count > 0:
			files[path] = migrated.count
		var left := _leftover.search_all(migrated.text).size()
		if left > 0:
			manual[path] = left
	return {"files": files, "manual": manual, "autoload": autoload_is_ours()}


## Rewrites every script scan() found, then drops the autoload. Returns the files it changed.
static func apply() -> Array:
	var changed := []
	for path in scan().files:
		var text := FileAccess.get_file_as_string(path)
		if not _backup(path, text):
			push_warning("Better Tile Editor: could not back up %s, left untouched" % path)
			continue
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			continue
		file.store_string(_migrate_text(text).text)
		file.close()
		changed.push_back(path)
	remove_autoload()
	return changed


static func autoload_is_ours() -> bool:
	var key := "autoload/" + AUTOLOAD_NAME
	if not ProjectSettings.has_setting(key):
		return false
	var value := str(ProjectSettings.get_setting(key)).trim_prefix("*")
	if value.begins_with("uid://"):
		var id := ResourceUID.text_to_id(value)
		value = ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else ""
	return value.begins_with(OWN_DIR + "/")


static func remove_autoload() -> void:
	if not autoload_is_ours():
		return
	ProjectSettings.clear("autoload/" + AUTOLOAD_NAME)
	ProjectSettings.save()


static func _migrate_text(text: String) -> Dictionary:
	var count := 0
	var found := _lookup.search_all(text)
	count += found.size()
	text = _lookup.sub(text, NEW_NAME, true)
	found = _identifier.search_all(text)
	count += found.size()
	text = _identifier.sub(text, NEW_NAME, true)
	return {"text": text, "count": count}


static func _backup(path: String, text: String) -> bool:
	var target := BACKUP_DIR.path_join(path.trim_prefix("res://"))
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir())) != OK:
		return false
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


static func _scripts(dir_path: String) -> Array:
	var found := []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for sub in dir.get_directories():
		var child := dir_path.path_join(sub)
		if sub.begins_with(".") or child == OWN_DIR:
			continue
		found.append_array(_scripts(child))
	for name in dir.get_files():
		if name.get_extension() == "gd":
			found.push_back(dir_path.path_join(name))
	return found
