extends Node

## Autoload. Streams an unbounded 3D lattice of cube rooms around the
## player's cell (Vector3i: x, floor, z), for the active world only (w: a
## Worlds id). Every other world exists as data: a cell's doors, stairs,
## portal and hideout come from a hash of the world seed and its
## coordinates (exits_for, up_open, link_of, has_hideout...), so the
## scanner and the portals read any world without a single node, and a
## freed cell rebuilds identically. Rooms near the player are built at
## once, the rest over the next frames within BUILD_BUDGET_MS.
##
## The maze: on every floor the same binary tree as ever (no sealed
## pockets), shared by all worlds; floors are joined by spiral stairs
## where a world's `vertical` share says (up_open). Some cells are void
## (WorldDef.void_chance): no room, only railed bridges between their
## doors, so the cubes around read as boxes floating in the dark.
##
## Worlds are warmed up before they're needed: the active one fully at
## load, then the destinations of nearby portals and fissures, nearest
## first, a material or a room shape at a time (WARM_BUDGET_MS per frame).
## A portal one room away, or the world just entered, jumps the queue: with
## four worlds per stratum the queue runs long, and a cold crossing costs.
## Rarer shapes (stairs, void, open faces) are built when first met.
##
## Each sequence has an anchor (the exit) 8-12 rooms away, one stratum
## deeper than the last (see GameManager.anchor_stratum), with a maze path
## to it checked when it's placed. Beacons, one per BEACON_BLOCK x
## BEACON_BLOCK block of every floor in every other world, always lead one
## hop closer to the anchor's world (a portal or a fissure), so the way
## there is never more than a few rooms off. A completed sequence reseeds
## the whole world. A GameMode without anchors has neither (anchor_w = -1).

const ROOM_SCENE := preload("res://scenes/rooms/Room.tscn")
## Per room: a common portal (within the stratum, where it has a
## neighbouring slot) or, rarer, a fissure to the next stratum. Both times
## GameMode.link_scale.
const PORTAL_CHANCE := 1.0 / 12.0
const FISSURE_CHANCE := 1.0 / 20.0
const NO_LINK := Vector2i(-1, 0)
## Doors beyond the one every cell is guaranteed (see edge_open).
const EXTRA_DOOR_CHANCE := 0.3
const HIDEOUT_CHANCE := 1.0 / 6.0
const BEACON_BLOCK := 4
const ANCHOR_MIN := 8.0
const ANCHOR_MAX := 12.0
## A candidate anchor is kept only if the maze reaches it within this many
## rooms (searching a box around start and target, ANCHOR_MARGIN wider).
const ANCHOR_MAX_PATH := 40
const ANCHOR_MARGIN := 6
## Rooms within this (Chebyshev) distance are built the moment they're
## needed; farther ones wait in line, nearest first. 0: only the one you're
## standing in (after a portal, the rest arrive within a few frames, behind
## the crossing's tear effect; a cold world's 9 at once cost up to ~24 ms).
const BUILD_NOW := 0
const BUILD_BUDGET_MS := 3.0
const WARM_BUDGET_MS := 2.0

enum Salt { CARVE, EAST, SOUTH, PORTAL, PORTAL_DIR, STYLE, HIDEOUT, BEACON, ANCHOR, LIGHT, FISSURE_SLOT, UP, VOID, OPEN }

const STEPS: Array[Vector3i] = [Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(-1, 0, 0)]

## Radii are Chebyshev distances in cells, set by Settings (set_radii).
## Cells within gen_radius of the player (v_radius floors up and down)
## always exist.
var gen_radius := 3
var v_radius := 1
## Cells farther than this are freed (one more floor than v_radius).
var free_radius := 6
## Rooms around the player whose light casts real-time shadows. 0 = only
## the room you're in (one omni shadow instead of ~9); -1 = none.
var shadow_radius := 0

## The active world's rooms.
var rooms: Dictionary[Vector3i, Room] = {}
var active_w := 0
var world_seed := 0
var anchor_cell := Vector3i.ZERO
## -1: no anchor (and no beacons) this run.
var anchor_w := 0

var _parent: Node3D
var _player: Node3D
var _center := Vector3i.ZERO
var _pending: Array[Vector3i] = [] # cells waiting to be built, nearest first
var _warm_steps := {} # world id -> Array[Callable] still to run
var _warm_order: Array[int] = [] # worlds with steps left, next first
var _warm_queued := {} # world id -> true
var _guides := {} # Vector4i(x, y, z, w) -> Vector2 (see guide)

func init_world(parent: Node3D, player: Node3D, start_w: int) -> void:
	_clear_rooms()
	_parent = parent
	_player = player
	active_w = start_w
	# The world you start in, whole, now (level load); the rest trickles in.
	Room._grime_texture(start_w, true)
	_queue_warm(start_w)
	# Already warm from an earlier run (restart, back to the menu): no steps.
	for step: Callable in _warm_steps.get(start_w, []):
		step.call()
	_warm_steps.erase(start_w)
	_warm_order.erase(start_w)
	_reseed()

func _ready() -> void:
	GameManager.sequence_completed.connect(func(_done: int) -> void: regenerate())

## New sequence: a new world (and anchor) around the player, who is set
## down on their room's landing point in it.
func regenerate() -> void:
	_clear_rooms()
	_reseed()
	land(_player)

func _reseed() -> void:
	world_seed = randi()
	_guides.clear()
	_center = cell_of(_player.global_position)
	anchor_w = -1
	if GameManager.mode.anchors:
		place_anchor(_center, GameManager.anchor_stratum())
	_stream()

func _process(_delta: float) -> void:
	if not is_instance_valid(_player) or not _player.is_inside_tree() or not is_instance_valid(_parent):
		return
	var c := cell_of(_player.global_position)
	if c != _center:
		_center = c
		_stream()
	var t0 := Time.get_ticks_usec()
	while not _pending.is_empty() and (Time.get_ticks_usec() - t0) / 1000.0 < BUILD_BUDGET_MS:
		_build(_pending.pop_front())
	if not _pending.is_empty():
		return # one budget per frame: warm-ups wait for the rooms
	while not _warm_order.is_empty():
		var steps: Array = _warm_steps[_warm_order[0]]
		steps.pop_front().call()
		if steps.is_empty():
			_warm_steps.erase(_warm_order.pop_front())
		if (Time.get_ticks_usec() - t0) / 1000.0 >= WARM_BUDGET_MS:
			break

# Cached meshes, materials and textures are static: drop them while the
# rendering server is still up.
func _exit_tree() -> void:
	Room.clear_caches()

func _clear_rooms() -> void:
	for room in rooms.values():
		if is_instance_valid(room):
			room.queue_free()
	rooms.clear()
	_pending.clear()

## Through a portal: this world's rooms go, the new one's come in (the few
## around the player at once, the rest over the next frames).
func switch_layer(new_w: int) -> void:
	if new_w == active_w:
		return
	_clear_rooms()
	active_w = new_w
	_queue_warm(new_w, true)
	_stream()

## Applied live: a running world grows/shrinks to the new radii right away.
func set_radii(gen: int, free: int, shadow: int, vertical := 1) -> void:
	gen_radius = gen
	free_radius = free
	shadow_radius = shadow
	v_radius = vertical
	if is_instance_valid(_parent):
		_stream()

## Depth fog is fully opaque just before the streamed frontier (the far wall
## of the last generated ring is at gen_radius + 0.5 rooms), so a long
## straight corridor never shows the ungenerated void behind it.
func fog_end() -> float:
	return (gen_radius + 0.4) * Room.ROOM_SIZE

## The active world's room at pos (null in any other world: those have no rooms).
func room_at(pos: Vector3, w: int) -> Room:
	return rooms.get(cell_of(pos)) if w == active_w else null

## The cell a point is in. A body counts as on the floor of the cube its
## feet are over, a pit sunk into the cube below included (3 m of slack),
## until its feet near the next floor (a spiral's top lap).
static func cell_of(pos: Vector3) -> Vector3i:
	return Vector3i(roundi(pos.x / Room.ROOM_SIZE), floori((pos.y + 3.0) / Room.CELL_H), roundi(pos.z / Room.ROOM_SIZE))

## A cell's origin: the middle of its floor.
static func origin(c: Vector3i) -> Vector3:
	return Vector3(c.x * Room.ROOM_SIZE, c.y * Room.CELL_H, c.z * Room.ROOM_SIZE)

# --- streaming -----------------------------------------------------------------

func _stream() -> void:
	var far: Array[Vector3i] = []
	for c in rooms:
		if _dist(c) > free_radius or absi(c.y - _center.y) > v_radius + 1:
			far.append(c)
	for c in far:
		# queue_free: some of these may be mid-frame.
		rooms[c].queue_free()
		rooms.erase(c)
	_pending.clear()
	for dy in range(-v_radius, v_radius + 1):
		for dx in range(-gen_radius, gen_radius + 1):
			for dz in range(-gen_radius, gen_radius + 1):
				var c := _center + Vector3i(dx, dy, dz)
				if not rooms.has(c):
					_pending.append(c)
	_pending.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return _order(a) < _order(b))
	while not _pending.is_empty() and _order(_pending[0]) <= BUILD_NOW:
		_build(_pending.pop_front())
	# Warm up whatever the portals and fissures around here lead to.
	var near: Array[Vector2i] = [] # (distance, world)
	for dx in range(-gen_radius - 1, gen_radius + 2):
		for dz in range(-gen_radius - 1, gen_radius + 2):
			var t := link_of(_center + Vector3i(dx, 0, dz), active_w).x
			if t >= 0:
				near.append(Vector2i(maxi(absi(dx), absi(dz)), t))
	near.sort()
	for n in near:
		_queue_warm(n.y, n.x <= 1)
	_update_rooms()

## Horizontal (Chebyshev) distance from the player's cell.
func _dist(c: Vector3i) -> int:
	return maxi(absi(c.x - _center.x), absi(c.z - _center.z))

## Build order: this floor first, near before far.
func _order(c: Vector3i) -> int:
	return _dist(c) + 3 * absi(c.y - _center.y)

func _build(c: Vector3i) -> void:
	var room := ROOM_SCENE.instantiate() as Room
	room.cell = c
	room.exits = exits_for(c)
	room.w = active_w
	room.variant = int(_rand(c, active_w, Salt.STYLE) * Room.VARIANTS)
	room.up = up_open(c, active_w)
	room.down = down_open(c, active_w)
	room.void_cell = is_void(c, active_w)
	room.open = open_faces(c, active_w)
	room.has_anchor = active_w == anchor_w and c == anchor_cell
	room.hideout = has_hideout(c, active_w)
	room.lit = is_lit(c, active_w)
	var link := link_of(c, active_w)
	room.link_target = link.x
	room.link_fissure = link.y == 1
	room.position = origin(c)
	rooms[c] = room
	_parent.add_child(room)
	room.set_shadow(_dist(c) <= shadow_radius and c.y == _center.y)
	room.set_fog_end(fog_end())

func _update_rooms() -> void:
	var fog := fog_end()
	for c in rooms:
		rooms[c].set_shadow(_dist(c) <= shadow_radius and c.y == _center.y)
		rooms[c].set_fog_end(fog)

func _queue_warm(w: int, urgent := false) -> void:
	if not _warm_queued.has(w):
		_warm_queued[w] = true
		_warm_steps[w] = Room.warm_steps(w)
		_warm_order.append(w)
	if urgent and _warm_order.has(w):
		_warm_order.erase(w)
		_warm_order.push_front(w)

# --- deterministic layout -------------------------------------------------------

func _rand(c: Vector3i, w: int, salt: Salt) -> float:
	return float(hash([world_seed, c.x, c.y, c.z, w, salt]) & 0xFFFF) / 65536.0

## Door on the east (or south) side of cell c. Every cell carves one of its
## east/south doors (binary-tree maze, per floor), so following those
## always leads out of any finite region: no sealed pockets on any floor,
## even in a map that is never complete. Extra doors add loops. Same for
## every world.
func edge_open(c: Vector3i, east: bool) -> bool:
	var carved_east := _rand(c, 0, Salt.CARVE) < 0.5
	if carved_east == east:
		return true
	return _rand(c, 0, Salt.EAST if east else Salt.SOUTH) < EXTRA_DOOR_CHANCE

## [north, south, east, west], matching Room.Exit.
func exits_for(c: Vector3i) -> Array[bool]:
	return [edge_open(c + STEPS[0], false), edge_open(c, false), edge_open(c, true), edge_open(c + STEPS[3], true)]

## Spiral stairs from cell c up to the one above, in world w
## (WorldDef.vertical). Never out of a void cell into a void cell's sky
## with nothing to land on: both ends always have the stairs' entry.
func up_open(c: Vector3i, w: int) -> bool:
	return _rand(c, w, Salt.UP) < Worlds.def(w).vertical

func down_open(c: Vector3i, w: int) -> bool:
	return up_open(c + Vector3i.DOWN, w)

## A cell with no room: bridges in the air (WorldDef.void_chance). Never
## the anchor's.
func is_void(c: Vector3i, w: int) -> bool:
	if w == anchor_w and c == anchor_cell:
		return false
	return _rand(c, w, Salt.VOID) < Worlds.def(w).void_chance

## Which of a room's faces [N, S, E, W, ceiling] are open to the void: only
## toward a void cell, never a wall with a door or a ceiling with stairs,
## and then by the world's open_chance.
func open_faces(c: Vector3i, w: int) -> Array[bool]:
	var out: Array[bool] = [false, false, false, false, false]
	if is_void(c, w):
		return out
	var chance := Worlds.def(w).open_chance
	var exits := exits_for(c)
	for i in 4:
		out[i] = not exits[i] and is_void(c + STEPS[i], w) and _rand(c, w + 16 * i, Salt.OPEN) < chance
	out[4] = not up_open(c, w) and is_void(c + Vector3i.UP, w) and _rand(c, w + 64, Salt.OPEN) < chance
	return out

## Where anyone arriving in cell c of world w (through a portal, a
## fissure, a new sequence) is set down, feet on the floor: beside its own
## portal on the pad if it has one, else on the walkway, off the centre
## (the anchor stands there). Outside any portal's reach either way.
func landing(c: Vector3i, w: int) -> Vector3:
	var link := link_of(c, w)
	var local := Vector3(0, 0, 1.2)
	if link.x >= 0:
		local = Vector3.ONE * 2.4 * (1.0 if link.x > w else -1.0)
		local.y = 0.0
	return origin(c) + local

## Moves a body (its origin 0.95 above its feet) to its cell's landing point.
func land(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	body.global_position = landing(cell_of(body.global_position), active_w) + Vector3(0, 0.95, 0)
	if body is CharacterBody3D:
		body.velocity = Vector3.ZERO

## Where cell c's portal leads in world w: Vector2i(target world, 1 if it's
## a fissure), NO_LINK for none.
func link_of(c: Vector3i, w: int) -> Vector2i:
	if anchor_w >= 0 and w != anchor_w and is_beacon(c):
		var t := Worlds.step_toward(w, anchor_w)
		return Vector2i(t, int(Worlds.stratum(t) != Worlds.stratum(w)))
	var r := _rand(c, w, Salt.PORTAL)
	var roll := _rand(c, w, Salt.PORTAL_DIR)
	var deep := Worlds.def(w).deep_fissures
	var fissure := FISSURE_CHANCE * GameManager.mode.link_scale * (1.0 + deep) / 2.0
	var portal := PORTAL_CHANCE * GameManager.mode.link_scale
	var dir := 1 if roll < 0.5 else -1
	var t := -1
	if r < fissure:
		dir = 1 if roll < deep / (1.0 + deep) else -1
		var to := Worlds.in_stratum(Worlds.stratum(w) + dir)
		if to.is_empty():
			to = Worlds.in_stratum(Worlds.stratum(w) - dir)
		if to.is_empty():
			return NO_LINK
		return Vector2i(to[int(_rand(c, w, Salt.FISSURE_SLOT) * to.size())], 1)
	if r < fissure + portal:
		t = Worlds.portal_target(w, dir)
		if t < 0:
			t = Worlds.portal_target(w, -dir)
	return Vector2i(t, 0) if t >= 0 else NO_LINK

## Where a room's guide line points (WorldDef.guide_lines), in room x/z:
## its portal corner if it has one, else the door toward the nearest one
## on its floor (maze BFS, GUIDE_RADIUS rooms out). ZERO: none in reach.
const GUIDE_RADIUS := 10
func guide(cell: Vector3i, w: int) -> Vector2:
	var key := Vector4i(cell.x, cell.y, cell.z, w)
	if _guides.has(key):
		return _guides[key]
	var out := Vector2.ZERO
	var link := link_of(cell, w)
	if link.x >= 0:
		out = Vector2.ONE * (Room.ROOM_SIZE / 2.0 - Room.PORTAL_INSET) * (1.0 if link.x > w else -1.0)
	else:
		var first := {} # cell -> the step out of `cell` it's reached through
		var queue: Array[Vector3i] = []
		var open := exits_for(cell)
		for i in 4:
			if open[i]:
				first[cell + STEPS[i]] = STEPS[i]
				queue.append(cell + STEPS[i])
		while not queue.is_empty():
			var c: Vector3i = queue.pop_front()
			if link_of(c, w).x >= 0:
				var s: Vector3i = first[c]
				out = Vector2(s.x, s.z) * (Room.ROOM_SIZE / 2.0)
				break
			if maxi(absi(c.x - cell.x), absi(c.z - cell.z)) >= GUIDE_RADIUS:
				continue
			open = exits_for(c)
			for i in 4:
				var n: Vector3i = c + STEPS[i]
				if open[i] and n != cell and not first.has(n):
					first[n] = first[c]
					queue.append(n)
	_guides[key] = out
	return out

## One cell per BEACON_BLOCK-square block of each floor, picked by hash.
func is_beacon(c: Vector3i) -> bool:
	var block := Vector2i(floori(float(c.x) / BEACON_BLOCK), floori(float(c.z) / BEACON_BLOCK))
	var pick := hash([world_seed, block, c.y, Salt.BEACON])
	return Vector2i(c.x, c.z) == block * BEACON_BLOCK + Vector2i(pick % BEACON_BLOCK, (pick / BEACON_BLOCK) % BEACON_BLOCK)

## Never in the anchor's room, nor in a void cell.
func has_hideout(c: Vector3i, w: int) -> bool:
	if (w == anchor_w and c == anchor_cell) or is_void(c, w):
		return false
	return _rand(c, w, Salt.HIDEOUT) < HIDEOUT_CHANCE

## Whether cell c has its light in world w (WorldDef.light_chance).
func is_lit(c: Vector3i, w: int) -> bool:
	var chance := Worlds.def(w).light_chance
	return chance >= 1.0 or _rand(c, w, Salt.LIGHT) < chance

## Anchor 8-12 rooms from `from`, in a world of `stratum_index`, with a
## maze path to it in that world (candidates are tried in hash order until
## one has). Its world: preferably one not visited this run and on another
## slot than the player's (so getting there takes more than a straight drop).
func place_anchor(from: Vector3i, stratum_index: int) -> void:
	var choices := Worlds.in_stratum(stratum_index)
	var other_slot := choices.filter(func(w: int) -> bool: return Worlds.slot(w) != Worlds.slot(active_w))
	var fresh := other_slot.filter(func(w: int) -> bool: return not w in GameManager.visited)
	for pool: Array in [fresh, other_slot]:
		if not pool.is_empty():
			choices.assign(pool)
			break
	anchor_w = choices[int(_rand(from, 0, Salt.ANCHOR) * choices.size())]
	anchor_cell = from
	for k in 64:
		var a := _rand(from, k, Salt.ANCHOR) * TAU
		var d := lerpf(ANCHOR_MIN, ANCHOR_MAX, _rand(from, k + 1000, Salt.ANCHOR))
		var target := from + Vector3i(roundi(cos(a) * d), 0, roundi(sin(a) * d))
		if path_length(from, target, anchor_w) >= 0:
			anchor_cell = target
			break

## Rooms walked from a to b in world w, through doors and up or down its
## stairs, or -1 if it takes more than ANCHOR_MAX_PATH or leaves the
## search box.
func path_length(a: Vector3i, b: Vector3i, w: int) -> int:
	var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z)) - Vector3i(ANCHOR_MARGIN, 3, ANCHOR_MARGIN)
	var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z)) + Vector3i(ANCHOR_MARGIN, 3, ANCHOR_MARGIN)
	var dist := {a: 0}
	var queue: Array[Vector3i] = [a]
	while not queue.is_empty():
		var c: Vector3i = queue.pop_front()
		if c == b:
			return dist[c]
		if dist[c] >= ANCHOR_MAX_PATH:
			continue
		for n in neighbours(c, w):
			if not dist.has(n) and n.x >= lo.x and n.y >= lo.y and n.z >= lo.z and n.x <= hi.x and n.y <= hi.y and n.z <= hi.z:
				dist[n] = dist[c] + 1
				queue.append(n)
	return -1

## The cells one door or one flight of stairs from c in world w.
func neighbours(c: Vector3i, w: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var open := exits_for(c)
	for i in 4:
		if open[i]:
			out.append(c + STEPS[i])
	if up_open(c, w):
		out.append(c + Vector3i.UP)
	if down_open(c, w):
		out.append(c + Vector3i.DOWN)
	return out
