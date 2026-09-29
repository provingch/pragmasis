extends Control

## Phase scanner — tactical telemetry terminal. White phosphor on a dead-CRT
## substrate. Hazard red is reserved for the entity; terminal green means
## "the way out": the anchor and the "safe to cross" verdict. Layers are told
## apart by label and line weight, not hue. Square corners only.
##
## Closed, it's the HUD: layer, sequence clock, stamina, flashlight
## battery, hideout prompt, and the centre-screen announcements. Without
## anchors (GameMode.anchors) there's no clock and no way-out readout.
##
## In a world with scanner_mirror the maps (and the anchor's ΔX) come out
## flipped left/right. The tell: now and then the header flips too.

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
## Mirrored worlds: the header flips for HEADER_FLIP of every HEADER_FLIP_EVERY seconds.
const HEADER_FLIP := 0.3
const HEADER_FLIP_EVERY := 2.2

var _open := false
var _open_t := 0.0
var _t := 0.0
## The open device's transform (its power-on unfold), to draw panels under.
var _device_xf := Transform2D()

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
	var player := _player()
	if player and player.hidden:
		# Inside the closet: only the slit's band (eye level, straight
		# ahead) lets light in. Without shadows the room light would
		# otherwise wash its inner walls.
		draw_rect(Rect2(0, 0, size.x, size.y * 0.41), Color(0, 0, 0, 0.88))
		draw_rect(Rect2(0, size.y * 0.59, size.x, size.y * 0.41), Color(0, 0, 0, 0.88))
	var w := DimensionState.player_w
	var p := Vector2(24, size.y - 44)
	var blink := 1.0 if fmod(_t, 0.5) < 0.25 else 0.25
	_text(p, "E%d // %s" % [Worlds.stratum(w) + 1, Worlds.def(w).display_name], FG, 13)
	_text(p + Vector2(0, 18), "[TAB] ESCÁNER DE FASE", DIM, 11)
	if _entity_hunting_here():
		_text(p + Vector2(0, -20), "■ ENTIDAD EN TU FASE", Color(RED, blink), 11)
	elif _omen():
		_text(p + Vector2(0, -20), "▒ INTERFERENCIA", Color(FG, 0.4 + 0.6 * randf()), 11)
	_draw_clock(blink)
	if player:
		_draw_stamina(Vector2(24, size.y - 92), player)
		if player.has_flashlight():
			_draw_battery(Vector2(24, size.y - 110), player)
		_draw_prompt(player)
	if GameManager.banner_t > 0.0:
		_draw_banner()

func _draw_clock(blink: float) -> void:
	if not GameManager.running or not GameManager.mode.anchors:
		return
	var y := 30.0
	if GameManager.is_collapsed:
		_text(Vector2(0, y), "COLAPSO // LLEGÁ AL ANCLA", Color(RED, blink), 14, size.x, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var tl := ceili(GameManager.time_left)
	var low := GameManager.time_left < 30.0
	var col := Color(RED, blink) if low else FG
	_text(Vector2(0, y), "SECUENCIA %02d  //  %d:%02d" % [GameManager.sequence, tl / 60, tl % 60], col, 14, size.x, HORIZONTAL_ALIGNMENT_CENTER)

## Ten blocks, dim while full; red and labelled when exhausted.
func _draw_stamina(p: Vector2, player: Player) -> void:
	if player.stamina >= 1.0 and player.exhausted <= 0.0:
		return
	var col := RED if player.exhausted > 0.0 else FG
	_text(p, "AGOTADO" if player.exhausted > 0.0 else "ENERGÍA", col if player.exhausted > 0.0 else DIM, 10)
	var filled := ceili(player.stamina * 10.0)
	for i in 10:
		var r := Rect2(p.x + 70 + i * 9, p.y - 7, 7, 6)
		if i < filled:
			draw_rect(r, col)
		else:
			draw_rect(r, DIM, false, 1.0)

## Ten blocks, always shown where there's a flashlight; red when low.
func _draw_battery(p: Vector2, player: Player) -> void:
	var low := player.battery < Player.BATTERY_LOW
	var col := RED if low else FG
	_text(p, "LINTERNA [F]" if player.flashlight_on else "LINTERNA OFF", col if low else DIM, 10)
	var filled := ceili(player.battery * 10.0)
	for i in 10:
		var r := Rect2(p.x + 100 + i * 9, p.y - 7, 7, 6)
		if i < filled:
			draw_rect(r, col if player.flashlight_on else DIM)
		else:
			draw_rect(r, DIM, false, 1.0)

func _draw_prompt(player: Player) -> void:
	var y := size.y - 110
	if player.hidden:
		var left := maxi(ceili(Player.HIDE_MAX - player.hide_t), 0)
		var unstable := player.hide_t >= Player.HIDE_UNSTABLE
		_text(Vector2(0, y), "[E] SALIR  //  ESTABILIDAD %02d S" % left, RED if unstable else FG, 13, size.x, HORIZONTAL_ALIGNMENT_CENTER)
	elif player.hideout_in_reach():
		_text(Vector2(0, y), "[E] ESCONDERSE", FG, 13, size.x, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_banner() -> void:
	var a := clampf(GameManager.banner_t / 0.4, 0.0, 1.0) * clampf((GameManager.BANNER_TIME - GameManager.banner_t) / 0.15, 0.0, 1.0)
	var y := size.y * 0.38
	draw_rect(Rect2(0, y - 52, size.x, 76), Color(0, 0, 0, 0.7 * a))
	var col := RED if GameManager.is_collapsed else GREEN
	draw_string(Fonts.heavy, Vector2(0, y), GameManager.banner, HORIZONTAL_ALIGNMENT_CENTER, size.x, 44, Color(col, a))

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
	_device_xf = Transform2D(0.0, Vector2(1.0, e), 0.0, origin + Vector2(jitter, DEVICE.y / 2.0 * (1.0 - e)))
	draw_set_transform_matrix(_device_xf)

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
	var flip := _mirrored() and fmod(_t, HEADER_FLIP_EVERY) < HEADER_FLIP
	if flip:
		_mirror_about(DEVICE.x / 2.0)
	_text(Vector2(14, 20), "[ PRAGMASIS // ESCÁNER DE FASE ]", FG, 12)
	if flip:
		draw_set_transform_matrix(_device_xf)
	_text(Vector2(DEVICE.x - 250, 20), "REV 0.4   UNIT / W-SCAN-03", DIM, 11, 236, HORIZONTAL_ALIGNMENT_RIGHT)
	draw_line(Vector2(0, HEADER_H), Vector2(DEVICE.x, HEADER_H), FG, 1.0)
	draw_line(Vector2(0, DEVICE.y - FOOTER_H), Vector2(DEVICE.x, DEVICE.y - FOOTER_H), FG, 1.0)
	draw_line(Vector2(SIDE_W, HEADER_H), Vector2(SIDE_W, DEVICE.y - FOOTER_H), FG, 1.0)

func _draw_side() -> void:
	var w := DimensionState.player_w
	# Macro numeral: the only big type on the device.
	draw_string(Fonts.heavy, Vector2(14, HEADER_H + 84), "E%d" % (Worlds.stratum(w) + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 72, FG)
	_text(Vector2(16, HEADER_H + 110), Worlds.def(w).display_name, FG, 14)
	var cell := _player_cell()
	var rows := [
		"CELDA   X%+d Z%+d" % [cell.x, cell.y],
		"ESTRATO %d / %d" % [Worlds.stratum(w) + 1, Worlds.deepest_stratum() + 1],
		"SEÑAL   %s" % _noise_string(6),
	]
	for i in rows.size():
		_text(Vector2(16, HEADER_H + 132 + i * 16), rows[i], DIM, 11)
	# The way out: cells to go and the anchor's layer.
	var aw := RoomGenerator.anchor_w
	if aw >= 0:
		var to := RoomGenerator.anchor_cell - cell
		_text(Vector2(16, HEADER_H + 188), "ANCLA   ΔX%+d ΔZ%+d" % [-to.x if _mirrored() else to.x, to.y], GREEN, 11)
		var where := "EN TU FASE" if aw == w else "EN %s // E%d" % [Worlds.def(aw).display_name, Worlds.stratum(aw) + 1]
		_text(Vector2(16, HEADER_H + 204), where, GREEN if aw == w else FG, 10)
	# Threat meter: this world's intrinsic hostility, 5 blocks = x2.0.
	var threat := Worlds.def(w).threat
	var blocks := clampi(roundi(threat * 2.5), 1, 5)
	_text(Vector2(16, HEADER_H + 230), "AMENAZA x%.1f" % threat, RED if threat > 1.0 else FG, 11)
	for i in 5:
		var r := Rect2(16 + i * 14, HEADER_H + 238, 10, 8)
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
		# Shallower neighbour, here, deeper neighbour.
		var w := pw if i == 1 else Worlds.adjacent(pw, i - 1)
		var p0 := Vector2(area.position.x + gap + i * (panel + gap), top)
		var here := i == 1
		var in_range := w >= 0
		var head := "[ %s ]" % (Worlds.def(w).display_name if in_range else "----")
		_text(p0 + Vector2(0, -12), head, FG if here else DIM, 10)
		if not in_range:
			_draw_no_signal(Rect2(p0, Vector2.ONE * panel))
			continue
		if _mirrored():
			_mirror_about(p0.x + panel / 2.0)
		_draw_layer_contents(p0, w, here)
		draw_set_transform_matrix(_device_xf)

## Window of cells around the player: real walls with door gaps, portal
## glyphs, crosshairs at interior corners.
func _draw_layer_contents(p0: Vector2, w: int, here: bool) -> void:
	var r := SCAN_RADIUS
	var n := 2 * r + 1
	var center := p0 + Vector2.ONE * CELL * (r + 0.5)
	var cell := _player_cell()
	var col := FG if here else DIM
	draw_rect(Rect2(p0, Vector2.ONE * CELL * n), FAINT, false, 1.0)

	# From the world's data, not its rooms: any world, loaded or not.
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var x := cell.x + dx
			var z := cell.y + dz
			var exits := RoomGenerator.exits_for(x, z)
			var c := center + Vector2(dx, dz) * CELL
			var h := CELL / 2.0
			_draw_wall(c + Vector2(-h, -h), c + Vector2(h, -h), exits[Room.Exit.NORTH], col)
			_draw_wall(c + Vector2(-h, h), c + Vector2(h, h), exits[Room.Exit.SOUTH], col)
			_draw_wall(c + Vector2(h, -h), c + Vector2(h, h), exits[Room.Exit.EAST], col)
			_draw_wall(c + Vector2(-h, -h), c + Vector2(-h, h), exits[Room.Exit.WEST], col)
			var link := RoomGenerator.link_of(x, z, w)
			if link.y == 1: # fissure: a crack
				var k := c + Vector2(-h + 7, -h + 4)
				draw_polyline(PackedVector2Array([k, k + Vector2(3, 3), k + Vector2(-1, 6), k + Vector2(2, 10)]), col, 1.5)
			elif link.x >= 0:
				_text(c + Vector2(-h + 4, -h + 12), "▼" if link.x > w else "▲", col, 9)
			if RoomGenerator.has_hideout(x, z, w): # its corner: +x (right), -z (up)
				draw_rect(Rect2(c + Vector2(h - 9, -h + 3), Vector2(6, 6)), col, false, 1.0)
			if w == RoomGenerator.anchor_w and Vector2i(x, z) == RoomGenerator.anchor_cell:
				draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), GREEN)
	for a in range(1, n):
		for b in range(1, n):
			var k := p0 + Vector2(a, b) * CELL
			draw_line(k - Vector2(3, 0), k + Vector2(3, 0), FAINT, 1.0)
			draw_line(k - Vector2(0, 3), k + Vector2(0, 3), FAINT, 1.0)

	# Panel coordinates are relative to the player's cell centre.
	var origin := center - Vector2(cell) * CELL
	var to := Vector2(RoomGenerator.anchor_cell - cell)
	if here and RoomGenerator.anchor_w >= 0 and to.length() > 0.0:
		# Arrow toward the anchor, from the edge of the window.
		var dir := to.normalized()
		var tip := center + dir * CELL * (r + 0.5) * 0.92
		var back := tip - dir * 12.0
		draw_line(center + dir * 10.0, tip, Color(GREEN, 0.6), 1.0)
		draw_colored_polygon(PackedVector2Array([tip, back + dir.orthogonal() * 5.0, back - dir.orthogonal() * 5.0]), GREEN)
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
		var hops := Worlds.distance(monster.entity_w, pw)
		var status := "ACTIVA" if monster.is_hunting() else "LATENTE"
		var line := "ENTIDAD   A %d SALTOS   COHERENCIA %.2f   ESTADO %s" % [hops, monster.coherence(), status]
		_text(Vector2(14, y), line, RED if _entity_hunting_here() else FG, 11)

	# Crossing verdict for the portal in *this* room.
	var c := _player_cell()
	var link := RoomGenerator.link_of(c.x, c.y, pw)
	if link.x < 0:
		_text(Vector2(14, y + 26), "CRUCE   [ SIN PORTAL ]", DIM, 11)
		return
	var tag := "%s %s %s // E%d" % ["FISURA" if link.y == 1 else "CRUCE", "▼" if link.x > pw else "▲", Worlds.def(link.x).display_name, Worlds.stratum(link.x) + 1]
	_text(Vector2(14, y + 26), tag, FG, 11)
	var risky := monster and monster.entity_w == link.x
	_text(Vector2(360, y + 26), "[ RIESGO ]" if risky else "[ SEGURO ]", RED if risky else GREEN, 11)

func _draw_sweep() -> void:
	var x0 := SIDE_W
	var x := x0 + fmod(_t / SWEEP_PERIOD, 1.0) * (DEVICE.x - SIDE_W)
	for i in 6:
		var xi := x - i * 5.0
		if xi > x0:
			draw_line(Vector2(xi, HEADER_H + 1), Vector2(xi, DEVICE.y - FOOTER_H - 1), Color(FG, 0.35 / (i + 1)), 1.0)

func _draw_degradation() -> void:
	if _omen():
		# Something is folding in: bands of static.
		for i in 10:
			var band := Rect2(0, randf() * DEVICE.y, DEVICE.x, randf_range(1.0, 5.0))
			draw_rect(band, Color(FG, randf_range(0.05, 0.3)))
	var y := 0.0
	while y < DEVICE.y:
		draw_line(Vector2(0, y), Vector2(DEVICE.x, y), Color(0, 0, 0, 0.22), 1.0)
		y += 3.0
	for i in 140:
		draw_rect(Rect2(randf() * DEVICE.x, randf() * DEVICE.y, 1, 1), Color(FG, 0.12))

# --- helpers -----------------------------------------------------------------

func _text(pos: Vector2, s: String, col: Color, fs: int, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(Fonts.mono, pos, s.to_upper(), align, width, fs, col)

func _mirrored() -> bool:
	return Worlds.def(DimensionState.player_w).scanner_mirror

## Draws what follows flipped about the vertical line x (device space).
func _mirror_about(x: float) -> void:
	draw_set_transform_matrix(_device_xf * Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(2.0 * x, 0)))

func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

func _omen() -> bool:
	var m := _monster()
	return m != null and m.omen_left > 0.0

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
