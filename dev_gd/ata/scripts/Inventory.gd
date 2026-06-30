class_name Inventory

const COLS := 4
const ROWS := 5

var grid   : Array = []   # [ROWS][COLS] → placed-entry dict or null
var placed : Array = []   # list of placed-entry dicts

var _next_id : int = 0

func _init() -> void:
	for _r in range(ROWS):
		var row : Array = []
		for _c in range(COLS):
			row.append(null)
		grid.append(row)

# Returns true if the item was placed, false if no space
func try_add(item_type: Dictionary) -> bool:
	var w : int = item_type["w"]
	var h : int = item_type["h"]
	for r in range(ROWS - h + 1):
		for c in range(COLS - w + 1):
			var fits := true
			for dr in range(h):
				for dc in range(w):
					if grid[r + dr][c + dc] != null:
						fits = false
						break
				if not fits:
					break
			if fits:
				var entry := { "_id": _next_id, "type": item_type, "row": r, "col": c }
				_next_id += 1
				for dr in range(h):
					for dc in range(w):
						grid[r + dr][c + dc] = entry
				placed.append(entry)
				return true
	return false

# Removes the item occupying (row, col) and returns its entry (or {} if empty)
func drop_at(row: int, col: int) -> Dictionary:
	var entry = grid[row][col]
	if entry == null:
		return {}
	var target_id : int = entry["_id"]
	var h : int = entry["type"]["h"]
	var w : int = entry["type"]["w"]
	for dr in range(h):
		for dc in range(w):
			grid[entry["row"] + dr][entry["col"] + dc] = null
	for i in range(placed.size()):
		if placed[i]["_id"] == target_id:
			placed.remove_at(i)
			break
	return entry

func total_value() -> int:
	var v := 0
	for e in placed:
		v += int(e["type"]["value"])
	return v
