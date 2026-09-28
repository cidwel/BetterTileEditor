@tool
extends TileMapLayer


## Elevation level; -1 follows sibling order. An explicit level shifts subsequent levels.
@export_range(-1, 4) var cliffLevel: int = -1

## Wall height in rows; -1 follows the level. This does not change drawing order.
@export_range(-1, 16) var cliffRows: int = -1
