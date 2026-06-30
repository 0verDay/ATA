class_name MapGen

# ─── Constants ────────────────────────────────────────────────────────────────
const MAP_W          := 60
const MAP_H          := 60
const TILE           := 48
const FILL_DENSITY   := 0.45
const CA_ITERS       := 5
const SPAWN_CLEAR    := 6

# ─── Public entry point ───────────────────────────────────────────────────────
# Returns { tiles: Array[PackedByteArray], spawn: Vector2i, extraction: Vector2i }
static func generate() -> Dictionary:
	var tiles := _make_grid(0)

	# Border walls
	for x in range(MAP_W):
		tiles[0][x]         = 1
		tiles[MAP_H - 1][x] = 1
	for y in range(MAP_H):
		tiles[y][0]         = 1
		tiles[y][MAP_W - 1] = 1

	var cx := MAP_W / 2
	var cy := MAP_H / 2

	# 1) Random noise
	for y in range(1, MAP_H - 1):
		for x in range(1, MAP_W - 1):
			if randf() < FILL_DENSITY:
				tiles[y][x] = 1

	# 2) Cellular automata
	for _i in range(CA_ITERS):
		var nxt := _make_grid(0)
		for x in range(MAP_W):
			nxt[0][x]         = 1
			nxt[MAP_H - 1][x] = 1
		for y in range(MAP_H):
			nxt[y][0]         = 1
			nxt[y][MAP_W - 1] = 1
		for y in range(1, MAP_H - 1):
			for x in range(1, MAP_W - 1):
				var n := _wall_neighbors(tiles, x, y)
				if tiles[y][x] == 1:
					nxt[y][x] = 1 if n >= 4 else 0
				else:
					nxt[y][x] = 1 if n >= 5 else 0
		tiles = nxt

	# 3) Clear spawn zone
	for y in range(1, MAP_H - 1):
		for x in range(1, MAP_W - 1):
			if Vector2(x - cx, y - cy).length() < SPAWN_CLEAR:
				tiles[y][x] = 0

	# 4) Pick & clear extraction BEFORE flood-fill
	var ex : int
	var ey : int
	var edge := randi() % 4
	match edge:
		0: ex = 2 + randi() % (MAP_W - 4); ey = 1
		1: ex = MAP_W - 2;                 ey = 2 + randi() % (MAP_H - 4)
		2: ex = 2 + randi() % (MAP_W - 4); ey = MAP_H - 2
		3: ex = 1;                          ey = 2 + randi() % (MAP_H - 4)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx := ex + dx
			var ny := ey + dy
			if nx > 0 and nx < MAP_W - 1 and ny > 0 and ny < MAP_H - 1:
				tiles[ny][nx] = 0

	# 5) Flood-fill: seal unreachable floor tiles
	_flood_fill_keep_largest(tiles, cx, cy)

	# 6) Carve corridor if extraction was sealed
	if tiles[ey][ex] == 1:
		_carve_corridor(tiles, ex, ey, cx, cy)

	# 7) Spawn world items on random floor tiles
	const ITEM_COUNT := 20
	var items : Array = []
	var attempts := 0
	while items.size() < ITEM_COUNT and attempts < 3000:
		attempts += 1
		var tx : int = 2 + randi() % (MAP_W - 4)
		var ty : int = 2 + randi() % (MAP_H - 4)
		if tiles[ty][tx] != 0: continue
		if Vector2(tx - cx, ty - cy).length() < 6.0: continue
		items.append({
			"pos":       Vector2((tx + 0.5) * TILE, (ty + 0.5) * TILE),
			"type":      ItemDef.TYPES[randi() % ItemDef.TYPES.size()],
			"collected": false,
		})

	return {
		"tiles":      tiles,
		"spawn":      Vector2i(cx, cy),
		"extraction": Vector2i(ex, ey),
		"items":      items,
	}

# ─── Helpers ──────────────────────────────────────────────────────────────────
static func _make_grid(fill: int) -> Array:
	var g := []
	for _y in range(MAP_H):
		g.append(PackedByteArray())
		g[-1].resize(MAP_W)
		g[-1].fill(fill)
	return g

static func _wall_neighbors(tiles: Array, x: int, y: int) -> int:
	var n := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0: continue
			if tiles[y + dy][x + dx] == 1: n += 1
	return n

static func _flood_fill_keep_largest(tiles: Array, sx: int, sy: int) -> void:
	var visited := PackedByteArray()
	visited.resize(MAP_W * MAP_H)
	visited.fill(0)
	var stack := [Vector2i(sx, sy)]
	visited[sy * MAP_W + sx] = 1
	while stack.size() > 0:
		var p : Vector2i = stack.pop_back()
		for d : Vector2i in [Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1)]:
			var np : Vector2i = p + d
			if np.x < 0 or np.x >= MAP_W or np.y < 0 or np.y >= MAP_H: continue
			var idx : int = np.y * MAP_W + np.x
			if visited[idx] or tiles[np.y][np.x] == 1: continue
			visited[idx] = 1
			stack.append(np)
	for y in range(MAP_H):
		for x in range(MAP_W):
			if tiles[y][x] == 0 and visited[y * MAP_W + x] == 0:
				tiles[y][x] = 1

static func _carve_corridor(tiles: Array, ex: int, ey: int, cx: int, cy: int) -> void:
	var x := ex
	var y := ey
	while x > 0 and x < MAP_W - 1 and y > 0 and y < MAP_H - 1:
		tiles[y][x] = 0
		for d : Vector2i in [Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1)]:
			var nx : int = x + d.x
			var ny : int = y + d.y
			if nx < 0 or nx >= MAP_W or ny < 0 or ny >= MAP_H: continue
			if tiles[ny][nx] == 0 and _is_connected(tiles, cx, cy, nx, ny): return
		var ddx := cx - x
		var ddy := cy - y
		if abs(ddx) >= abs(ddy):
			x += 1 if ddx > 0 else -1
		else:
			y += 1 if ddy > 0 else -1

static func _is_connected(tiles: Array, sx: int, sy: int, tx: int, ty: int) -> bool:
	if tiles[ty][tx] != 0: return false
	var visited := PackedByteArray()
	visited.resize(MAP_W * MAP_H)
	visited.fill(0)
	var stack := [Vector2i(sx, sy)]
	visited[sy * MAP_W + sx] = 1
	while stack.size() > 0:
		var p : Vector2i = stack.pop_back()
		if p.x == tx and p.y == ty: return true
		for d : Vector2i in [Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1)]:
			var np : Vector2i = p + d
			if np.x < 0 or np.x >= MAP_W or np.y < 0 or np.y >= MAP_H: continue
			var idx : int = np.y * MAP_W + np.x
			if visited[idx] or tiles[np.y][np.x] == 1: continue
			visited[idx] = 1
			stack.append(np)
	return false

# ─── Tile collision (used by Raid scene) ──────────────────────────────────────
static func resolve_collision(pos: Vector2, radius: float, tiles: Array) -> Vector2:
	var x := pos.x
	var y := pos.y
	var min_tx : int = max(0, int((x - radius) / TILE))
	var max_tx : int = min(MAP_W - 1, int((x + radius) / TILE))
	var min_ty : int = max(0, int((y - radius) / TILE))
	var max_ty : int = min(MAP_H - 1, int((y + radius) / TILE))
	for ty in range(min_ty, max_ty + 1):
		for tx in range(min_tx, max_tx + 1):
			if tiles[ty][tx] != 1: continue
			var cx := clampf(x, tx * TILE, (tx + 1) * TILE)
			var cy := clampf(y, ty * TILE, (ty + 1) * TILE)
			var ddx := x - cx
			var ddy := y - cy
			var dist := sqrt(ddx * ddx + ddy * ddy)
			if dist < radius and dist > 0.0:
				x += ddx / dist * (radius - dist)
				y += ddy / dist * (radius - dist)
	return Vector2(x, y)
