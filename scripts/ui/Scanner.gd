extends Control

## Phase scanner — tactical telemetry terminal. White phosphor on a dead-CRT
## substrate. Hazard red is reserved for the entity; terminal green is used
## for exactly one thing: the "safe to cross" verdict. Layers are told apart
## by label and line weight, not hue. Square corners only.

const BG := Color("0a0a0a")
const FG := Color("eaeaea")
const DIM := Color(0.918, 0.918, 0.918, 0.3)
const FAINT := Color(0.918, 0.918, 0.918, 0.1)
const RED := Color("ff2a2a")
const GREEN := Color("4af626")

const DEVICE := Vector2(720, 420)
const HEADER_H := 30.0
const FOOTER_H := 78.0
const SIDE_W := 170.0
const CELL := 34.0
const SCAN_RADIUS := 1
const OPEN_TIME := 0.22
const SWEEP_PERIOD := 2.4

var _open := false
var _open_t := 0.0
var _t := 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("scanner"):
		_open = not _open
		AudioManager.play_sfx(&"scanner_open" if _open else &"scanner_close")

func _process(delta: float) -> void:
	_t += delta
	_open_t = move_toward(_open_t, 1.0 if _open else 0.0, delta / OPEN_TIME)
	queue_redraw()

func _draw() -> void:
	_draw_compact()
	if _open_t > 0.0:
		_draw_device()

# --- closed state -----------------------------------------------------------

func _draw_compact() -> void:
	var w := DimensionState.player_w
	var p := Vector2(24, size.y - 44)
	_text(p, "W%+d // %s" % [w, DimensionState.LAYERS[w].name], FG, 13)
	_text(p + Vector2(0, 18), "[TAB] ESCÁNER DE FASE", DIM, 11)
	if _entity_hunting_here():
		var blink := 1.0 if fmod(_t, 0.5) < 0.25 else 0.25
		_text(p + Vector2(0, -20), "■ ENTIDAD EN TU FASE", Color(RED, blink), 11)

# --- open device ------------------------------------------------------------

func _draw_device() -> void:
	# CRT power-on: a bright line that unfolds vertically.
	var e := ease(_open_t, 0.4)
	var origin := ((size - DEVICE) / 2.0).floor()
	if e < 0.08:
		var y := origin.y + DEVICE.y / 2.0
		draw_line(Vector2(origin.x, y), Vector2(origin.x + DEVICE.x, y), FG, 2.0)
		return
	var jitter := 0.0
	if _entity_hunting_here() and randf() < 0.12:
		jitter = randf_range(-6.0, 6.0)
	draw_set_transform(origin + Vector2(jitter, DEVICE.y / 2.0 * (1.0 - e)), 0.0, Vector2(1.0, e))

	draw_rect(Rect2(Vector2.ZERO, DEVICE), BG)
	_draw_header()
	_draw_side()
	_draw_panels()
	_draw_footer()
	_draw_sweep()
	_draw_degradation()
	draw_rect(Rect2(Vector2.ZERO, DEVICE), FG, false, 2.0)
	draw_set_transform(Vector2.ZERO)

func _draw_header() -> void:
	_text(Vector2(14, 20), "[ PRAGMASIS // ESCÁNER DE FASE ]", FG, 12)
	_text(Vector2(DEVICE.x - 250, 20), "REV 0.4   UNIT / W-SCAN-03", DIM, 11, 236, HORIZONTAL_ALIGNMENT_RIGHT)
	draw_line(Vector2(0, HEADER_H), Vector2(DEVICE.x, HEADER_H), FG, 1.0)
	draw_line(Vector2(0, DEVICE.y - FOOTER_H), Vector2(DEVICE.x, DEVICE.y - FOOTER_H), FG, 1.0)
	draw_line(Vector2(SIDE_W, HEADER_H), Vector2(SIDE_W, DEVICE.y - FOOTER_H), FG, 1.0)

func _draw_side() -> void:
	var w := DimensionState.player_w
	# Macro numeral: the only big type on the device.
	draw_string(Fonts.heavy, Vector2(14, HEADER_H + 84), "W%+d" % w, HORIZONTAL_ALIGNMENT_LEFT, -1, 72, FG)
	_text(Vector2(16, HEADER_H + 110), DimensionState.LAYERS[w].name, FG, 14)
	var cell := _player_cell()
	var rows := [
		"CELDA   X%+d Z%+d" % [cell.x, cell.y],
		"CAPAS   %d / %d" % [w - DimensionState.W_MIN + 1, DimensionState.W_SPAN + 1],
		"SEÑAL   %s" % _noise_string(6),
	]
	for i in rows.size():
		_text(Vector2(16, HEADER_H + 140 + i * 18), rows[i], DIM, 11)
	# Threat meter: this world's intrinsic hostility, 5 blocks = x2.0.
	var threat: float = DimensionState.LAYERS[w].threat
	var blocks := clampi(roundi(threat * 2.5), 1, 5)
	_text(Vector2(16, HEADER_H + 200), "AMENAZA x%.1f" % threat, RED if threat > 1.0 else FG, 11)
	for i in 5:
		var r := Rect2(16 + i * 14, HEADER_H + 208, 10, 8)
		if i < blocks:
			draw_rect(r, RED if threat > 1.0 else FG)
		else:
			draw_rect(r, DIM, false, 1.0)
	# Barcode: decorative, seeded so it doesn't shimmer.
	var x := 16.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331
	while x < SIDE_W - 16:
		var bw := float(rng.randi_range(1, 3))
		draw_rect(Rect2(x, DEVICE.y - FOOTER_H - 34, bw, 20), DIM)
		x += bw + rng.randi_range(1, 4)

func _draw_panels() -> void:
	var pw := DimensionState.player_w
	var n := 2 * SCAN_RADIUS + 1
	var panel := CELL * n
	var area := Rect2(SIDE_W, HEADER_H, DEVICE.x - SIDE_W, DEVICE.y - HEADER_H - FOOTER_H)
	var gap := (area.size.x - panel * 3.0) / 4.0
	var top := area.position.y + (area.size.y - panel) / 2.0 + 8.0

	for i in 3:
		var dw := i - 1
		var w := pw + dw
		var p0 := Vector2(area.position.x + gap + i * (panel + gap), top)
		var here := dw == 0
		var in_range := w >= DimensionState.W_MIN and w <= DimensionState.W_MAX
		var head := "[ W%+d / %s ]" % [w, DimensionState.LAYERS[w].name if in_range else "----"]
		_text(p0 + Vector2(0, -12), head, FG if here else DIM, 10)
		if not in_range:
			_draw_no_signal(Rect2(p0, Vector2.ONE * panel))
			continue
		_draw_layer_contents(p0, w, here)

## Window of cells around the player: real walls with door gaps, portal
## glyphs, crosshairs at interior corners.
func _draw_layer_contents(p0: Vector2, w: int, here: bool) -> void:
	var r := SCAN_RADIUS
	var n := 2 * r + 1
	var center := p0 + Vector2.ONE * CELL * (r + 0.5)
	var cell := _player_cell()
	var col := FG if here else DIM
	draw_rect(Rect2(p0, Vector2.ONE * CELL * n), FAINT, false, 1.0)

	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var room: Room = RoomGenerator.rooms.get(Vector4i(cell.x + dx, 0, cell.y + dz, w))
			if room == null:
				continue
			var c := center + Vector2(dx, dz) * CELL
			var h := CELL / 2.0
			_draw_wall(c + Vector2(-h, -h), c + Vector2(h, -h), room.exits[Room.Exit.NORTH], col)
			_draw_wall(c + Vector2(-h, h), c + Vector2(h, h), room.exits[Room.Exit.SOUTH], col)
			_draw_wall(c + Vector2(h, -h), c + Vector2(h, h), room.exits[Room.Exit.EAST], col)
			_draw_wall(c + Vector2(-h, -h), c + Vector2(-h, h), room.exits[Room.Exit.WEST], col)
			var glyphs := ("▲" if room.phase_positive else "") + ("▼" if room.phase_negative else "")
			if glyphs != "":
				_text(c + Vector2(-h + 4, -h + 12), glyphs, col, 9)
	for a in range(1, n):
		for b in range(1, n):
			var k := p0 + Vector2(a, b) * CELL
			draw_line(k - Vector2(3, 0), k + Vector2(3, 0), FAINT, 1.0)
			draw_line(k - Vector2(0, 3), k + Vector2(0, 3), FAINT, 1.0)

	# Panel coordinates are relative to the player's cell centre.
	var origin := center - Vector2(cell) * CELL
	if here:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player and fmod(_t, 0.8) < 0.6:
			var pp := origin + _to_panel(player.global_position)
			draw_rect(Rect2(pp - Vector2(3, 3), Vector2(6, 6)), FG)

	var monster := _monster()
	if monster and monster.entity_w == w:
		if monster.is_hunting():
			var edge := Vector2.ONE * CELL * (r + 0.5)
			var mp := center + (origin + _to_panel(monster.global_position) - center).clamp(-edge, edge)
			var lit := _sweep_boost(mp.x)
			var s := 3.0 + 3.0 * monster.coherence()
			draw_rect(Rect2(mp - Vector2(s, s), Vector2(s, s) * 2.0), Color(RED, 0.5 + 0.5 * lit))
			var ping := fmod(_t * 1.2, 1.0)
			draw_arc(mp, 6.0 + ping * 22.0, 0.0, TAU, 24, Color(RED, (1.0 - ping) * 0.8), 1.0)
		else:
			_text(p0 + Vector2(0, CELL * (2 * r + 1) + 14), "/// ECO LATENTE", Color(RED, 0.5 + 0.5 * sin(_t * 3.0)), 9)

func _draw_no_signal(rect: Rect2) -> void:
	draw_rect(rect, FAINT, false, 1.0)
	# Warning stripes, clipped by hand to the square.
	var s := rect.size.x
	var k := -s
	while k < s:
		var a := Vector2(maxf(k, 0.0), maxf(-k, 0.0))
		var b := Vector2(minf(k + s, s), minf(s - k, s))
		draw_line(rect.position + a, rect.position + b, FAINT, 3.0)
		k += 12.0
	_text(rect.position + Vector2(0, s / 2.0 + 4), "SIN SEÑAL", DIM, 10, s, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_footer() -> void:
	var y := DEVICE.y - FOOTER_H + 22
	var monster := _monster()
	var pw := DimensionState.player_w
	if monster:
		var dw := monster.entity_w - pw
		var status := "ACTIVA" if monster.is_hunting() else "LATENTE"
		var line := "ENTIDAD   Δw %+d   COHERENCIA %.2f   ESTADO %s" % [dw, monster.coherence(), status]
		_text(Vector2(14, y), line, RED if _entity_hunting_here() else FG, 11)

	# Crossing verdict for the portals in *this* room.
	var room: Room = RoomGenerator.rooms.get(_room_coord())
	var x := 14.0
	for dir: int in [1, -1]:
		var has := room != null and (room.phase_positive if dir > 0 else room.phase_negative)
		var tag := "CRUCE %sW" % ("+" if dir > 0 else "−")
		_text(Vector2(x, y + 26), tag, FG, 11)
		if not has:
			_text(Vector2(x + 70, y + 26), "[ SIN PORTAL ]", DIM, 11)
		elif monster and monster.entity_w == pw + dir:
			_text(Vector2(x + 70, y + 26), "[ RIESGO ]", RED, 11)
		else:
			_text(Vector2(x + 70, y + 26), "[ SEGURO ]", GREEN, 11)
		x += 250.0

func _draw_sweep() -> void:
	var x0 := SIDE_W
	var x := x0 + fmod(_t / SWEEP_PERIOD, 1.0) * (DEVICE.x - SIDE_W)
	for i in 6:
		var xi := x - i * 5.0
		if xi > x0:
			draw_line(Vector2(xi, HEADER_H + 1), Vector2(xi, DEVICE.y - FOOTER_H - 1), Color(FG, 0.35 / (i + 1)), 1.0)

func _draw_degradation() -> void:
	var y := 0.0
	while y < DEVICE.y:
		draw_line(Vector2(0, y), Vector2(DEVICE.x, y), Color(0, 0, 0, 0.22), 1.0)
		y += 3.0
	for i in 140:
		draw_rect(Rect2(randf() * DEVICE.x, randf() * DEVICE.y, 1, 1), Color(FG, 0.12))

# --- helpers -----------------------------------------------------------------

func _text(pos: Vector2, s: String, col: Color, fs: int, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(Fonts.mono, pos, s.to_upper(), align, width, fs, col)

func _monster() -> Monster:
	return get_tree().get_first_node_in_group("monster") as Monster

func _entity_hunting_here() -> bool:
	var m := _monster()
	return m != null and m.is_hunting() and m.entity_w == DimensionState.player_w

func _player_cell() -> Vector2i:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return Vector2i.ZERO
	return RoomGenerator.cell_of(player.global_position)

## Wall segment; an open one keeps only its two ends, leaving the door gap.
func _draw_wall(a: Vector2, b: Vector2, open: bool, col: Color) -> void:
	if not open:
		draw_line(a, b, col, 2.0)
		return
	var stub := (b - a) * 0.3
	draw_line(a, a + stub, col, 2.0)
	draw_line(b - stub, b, col, 2.0)

func _room_coord() -> Vector4i:
	var c := _player_cell()
	return Vector4i(c.x, 0, c.y, DimensionState.player_w)

func _to_panel(world_pos: Vector3) -> Vector2:
	return Vector2(world_pos.x, world_pos.z) / Room.ROOM_SIZE * CELL

## 1.0 right as the sweep passes x (device space), fading behind it.
func _sweep_boost(x: float) -> float:
	var sx := SIDE_W + fmod(_t / SWEEP_PERIOD, 1.0) * (DEVICE.x - SIDE_W)
	var behind := sx - x
	if behind < 0.0:
		behind += DEVICE.x - SIDE_W
	return clampf(1.0 - behind / 120.0, 0.0, 1.0)

# Changes 5x/second: reads as live data without strobing.
func _noise_string(n: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_t * 5.0)
	var s := ""
	for i in n:
		s += "0123456789ABCDEF"[rng.randi() % 16]
	return s
