class_name Inventory

var cols : int = 5
var rows : int = 5

var grid   : Array = []   # [rows][cols] → placed-entry dict or null
var placed : Array = []   # list of placed-entry dicts

var _next_id : int = 0

func _init(c: int = 5, r: int = 5) -> void:
	cols = c
	rows = r
	for _r in range(rows):
		var row : Array = []
		for _c in range(cols):
			row.append(null)
		grid.append(row)

# Returns true if the item was placed, false if no space
func try_add(item_type: Dictionary) -> bool:
	var w : int = item_type["w"]
	var h : int = item_type["h"]
	for r in range(rows - h + 1):
		for c in range(cols - w + 1):
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

# Place item with top-left at (base_r, base_c).
# Searches outward (Manhattan distance) for nearest valid position.
# Returns true if placed, false if the grid has no room.
func try_place_at(item_type: Dictionary, base_r: int, base_c: int) -> bool:
	var w : int = item_type["w"]
	var h : int = item_type["h"]
	# Clamp base to legal top-left range
	base_r = clampi(base_r, 0, rows - h)
	base_c = clampi(base_c, 0, cols - w)

	var max_dist := maxi(rows, cols)
	for dist in range(max_dist + 1):
		for dr in range(-dist, dist + 1):
			for dc in range(-dist, dist + 1):
				if absi(dr) != dist and absi(dc) != dist:
					continue   # only the ring at exact Manhattan distance
				var r := base_r + dr
				var c := base_c + dc
				if r < 0 or r + h > rows or c < 0 or c + w > cols:
					continue
				var fits := true
				for rr in range(h):
					for cc in range(w):
						if grid[r + rr][c + cc] != null:
							fits = false
							break
					if not fits: break
				if fits:
					var entry := { "_id": _next_id, "type": item_type, "row": r, "col": c }
					_next_id += 1
					for rr in range(h):
						for cc in range(w):
							grid[r + rr][c + cc] = entry
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
