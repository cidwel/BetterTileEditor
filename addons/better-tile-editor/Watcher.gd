@tool
extends RefCounted

signal trigger
var complete := false
var tileset : TileSet


func tidy() -> bool:
	if complete:
		return false

	complete = true
	return true


func activate():
	if tidy():
		trigger.emit()
