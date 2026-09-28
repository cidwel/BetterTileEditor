extends SceneTree
# Prints every tile of a demo scene, layer by layer in drawing order, for a preview render.
func _init():
	await process_frame
	var scene: Node = load(OS.get_environment("SCENE")).instantiate()
	root.add_child(scene)
	await process_frame
	# Tree order within each z index, as Godot draws them
	var found := scene.find_children("*", "TileMapLayer", true, false)
	var zs := {}
	for tm in found:
		zs[_z(tm)] = true
	var order := zs.keys()
	order.sort()
	var layers := []
	for z in order:
		layers.append_array(found.filter(func(tm): return _z(tm) == z))
	for tm: TileMapLayer in layers:
		for c in tm.get_used_cells():
			var src := tm.tile_set.get_source(tm.get_cell_source_id(c)) as TileSetAtlasSource
			if src == null: continue
			var r := src.get_tile_texture_region(tm.get_cell_atlas_coords(c))
			var off := Vector2i(tm.global_position) / 16
			var alt := tm.get_cell_alternative_tile(c)
			var hidden: bool = alt > 0 and (not src.has_alternative_tile(tm.get_cell_atlas_coords(c), alt)
				or src.get_tile_data(tm.get_cell_atlas_coords(c), alt).modulate.a < 0.1)
			if not hidden:
				print("C %d %d %d %d %d %d %s" % [c.x + off.x, c.y + off.y, r.position.x, r.position.y, r.size.x, r.size.y, src.texture.resource_path])
	quit()


func _z(item: CanvasItem) -> int:
	var z := item.z_index
	while item.z_as_relative and item.get_parent() is CanvasItem:
		item = item.get_parent()
		z += item.z_index
	return z
