extends Node
## Offscreen harness: the game renders into a 1280x720 SubViewport on the real
## GPU; the actual OS window is an unfocusable, transparent 8x8.
const OUT := "/tmp/claude-1000/-home-provingchill-Proyectos-pragmasis/cafd8f87-967c-4b7e-b114-922f7fa7513a/scratchpad/shots/"
var sv: SubViewport
var main: Node
var fx: ColorRect

func gpu_ms(n: int) -> float:
	for i in 10: await RenderingServer.frame_post_draw
	var sum := 0.0
	for i in n:
		await RenderingServer.frame_post_draw
		sum += RenderingServer.viewport_get_measured_render_time_gpu(sv.get_viewport_rid())
	return sum / n

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	sv.get_texture().get_image().save_png(OUT + name + ".png")

func _ready() -> void:
	get_window().mouse_passthrough = true
	print("ventana: %s en %s  unfocusable=%s transparent=%s" % [get_window().size, get_window().position, get_window().unfocusable, get_window().transparent])
	seed(1234)
	sv = SubViewport.new()
	sv.size = Vector2i(1280, 720)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	main = preload("res://scenes/Main.tscn").instantiate()
	var pl := main.get_node("Player")
	pl.set_script(null) # no mouse capture, no input
	pl.add_to_group("player")
	sv.add_child(main)
	RenderingServer.viewport_set_measure_render_time(sv.get_viewport_rid(), true)
	fx = main.get_node("ScreenFX/FX")
	get_tree().get_first_node_in_group("monster").set_process(false)
	await get_tree().create_timer(1.5).timeout
	pl.rotation.y = deg_to_rad(-45)
	var mode := OS.get_cmdline_user_args()
	if mode.has("fps"):
		await fps()
	elif mode.has("hitch4"):
		await hitch4(mode)
	elif mode.has("hitch3"):
		await hitch3(mode)
	elif mode.has("hitch2"):
		await hitch2(mode.has("prewarm"))
	elif mode.has("hitch"):
		await hitch()
	elif mode.has("compare"):
		await compare()
	elif mode.has("after_bench"):
		await bench_after()
	elif mode.has("bench"):
		await bench()
	elif mode.has("shots"):
		await shots(mode)
	get_tree().quit()

# --- variants swapped live on the same material ---------------------------------
var variants := {}

func with_calm(src: String, calm_body: String) -> Shader:
	var marker := "void fragment() {"
	var i := src.find(marker)
	var inner := src.substr(i + marker.length()).strip_edges()
	inner = inner.substr(0, inner.length() - 1) # drop fragment's closing brace
	var sh := Shader.new()
	sh.code = src.substr(0, i) + marker + "\n\tif (danger < 0.01 && shift < 0.01) {\n" + calm_body + "\n\t} else {\n" + inner + "\n\t}\n}\n"
	return sh

func bench() -> void:
	var orig: Shader = fx.material.shader
	variants["early_literal"] = with_calm(orig.code, "\t\tCOLOR = vec4(texture(screen_tex, SCREEN_UV).rgb, 1.0);")
	variants["early_conserva"] = with_calm(orig.code, """		vec3 c = texture(screen_tex, SCREEN_UV).rgb;
		float v = smoothstep(0.3, 0.85, length((SCREEN_UV - 0.5) * vec2(1.25, 1.0)));
		c *= 1.0 - v * 0.6;
		c += (hash(SCREEN_UV * 911.0 + fract(TIME) * 37.0) - 0.5) * 0.045;
		COLOR = vec4(c, 1.0);""")
	var results := {}
	for rounds in 3:
		for v in ["actual", "oculto", "early_literal", "early_conserva"]:
			fx.visible = v != "oculto"
			if variants.has(v):
				fx.material.shader = variants[v]
			else:
				fx.material.shader = orig
			var ms: float = await gpu_ms(150)
			if not results.has(v): results[v] = []
			results[v].append(ms)
	fx.material.shader = orig
	fx.visible = true
	for v in results:
		var arr: Array = results[v]
		print("%-16s GPU %.2f ms   (rondas: %s)" % [v, arr.reduce(func(a, b): return a + b) / arr.size(), ", ".join(arr.map(func(x): return "%.2f" % x))])

func bench_after() -> void:
	var sfx := main.get_node("ScreenFX")
	var calm := main.get_node("ScreenFX/Calm") as CanvasItem
	var res := {"calma (nuevo)": [], "pase completo forzado": []}
	for r in 3:
		sfx.set_process(true)
		await get_tree().process_frame
		res["calma (nuevo)"].append(await gpu_ms(150))
		print("   estado en calma: ", fx_state())
		sfx.set_process(false)
		fx.visible = true
		calm.visible = false
		res["pase completo forzado"].append(await gpu_ms(150))
	for k in res:
		var a: Array = res[k]
		print("%-22s GPU %.2f ms   (rondas: %s)" % [k, a.reduce(func(x, y): return x + y) / a.size(), ", ".join(a.map(func(x): return "%.2f" % x))])

## Same frame content, lights frozen: A = old path (full pass at danger=0,
## shift=0), B = new calm overlay. Averages 8 frames to wash out grain.
func avg_image(n: int) -> Image:
	var acc := PackedFloat32Array()
	var img: Image
	for i in n:
		await RenderingServer.frame_post_draw
		img = sv.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var d := img.get_data()
		if acc.is_empty():
			acc.resize(d.size())
		for k in d.size():
			acc[k] += d[k]
	var out := PackedByteArray()
	out.resize(acc.size())
	for k in acc.size():
		out[k] = int(acc[k] / n)
	return Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8, out)

func compare() -> void:
	for r in RoomGenerator.rooms.values():
		if r.is_inside_tree():
			r.set_process(false)
			r._light.light_energy = r._base_energy
			r._fixture_mat.emission_energy_multiplier = 4.0
	var sfx := main.get_node("ScreenFX")
	var calm := main.get_node("ScreenFX/Calm") as CanvasItem
	sfx.set_process(false)
	for w in [0, 1]:
		if w == 1:
			DimensionState._last_shift_ms = -99999
			DimensionState.request_phase_shift(1)
			await get_tree().create_timer(2.0).timeout
			for r in RoomGenerator.rooms.values():
				if r.is_inside_tree():
					r.set_process(false)
					r._light.light_energy = r._base_energy
					r._fixture_mat.emission_energy_multiplier = 4.0
		(fx.material as ShaderMaterial).set_shader_parameter("shift", 0.0)
		(fx.material as ShaderMaterial).set_shader_parameter("danger", 0.0)
		fx.visible = true
		calm.visible = false
		(await avg_image(8)).save_png(OUT + "cmp_w%d_A_anterior.png" % w)
		fx.visible = false
		calm.visible = true
		(await avg_image(8)).save_png(OUT + "cmp_w%d_B_nuevo.png" % w)
	print("comparación guardada")

func worst_after_shift(d: int) -> String:
	DimensionState._last_shift_ms = -99999
	var t_req := Time.get_ticks_usec()
	DimensionState.request_phase_shift(d)
	var worst := 0.0
	var last := t_req
	for i in 30:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
	await get_tree().create_timer(0.8).timeout
	return "%s peor frame %.0f ms" % [DimensionState.LAYERS[DimensionState.player_w].name, worst]

func hitch() -> void:
	await get_tree().create_timer(1.0).timeout
	print("1er ingreso  -> ", await worst_after_shift(1))
	print("vuelta       -> ", await worst_after_shift(-1))
	print("1er ingreso  -> ", await worst_after_shift(-1))
	print("vuelta       -> ", await worst_after_shift(1))
	print("2do ingreso  -> ", await worst_after_shift(1))
	print("vuelta       -> ", await worst_after_shift(-1))
	print("2do ingreso  -> ", await worst_after_shift(-1))

func hitch2(prewarm: bool) -> void:
	if prewarm:
		var t0 := Time.get_ticks_usec()
		for w in [-1, 0, 1]:
			for k in ["wall", "floor", "trim"]:
				var r := Room.new(); r.w = w; r._style = DimensionState.LAYERS[w]
				r._layer_material(k)
				r.free()
		print("precalentar materiales: %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
		await get_tree().create_timer(1.5).timeout
	await get_tree().create_timer(1.0).timeout
	var t0 := Time.get_ticks_usec()
	RoomGenerator.switch_layer(1)
	var t_switch := (Time.get_ticks_usec() - t0) / 1000.0
	var fr := []
	var last := Time.get_ticks_usec()
	for i in 5:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		fr.append("%.0f" % ((now - last) / 1000.0))
		last = now
	print("switch_layer(ÉTER) CPU %.1f ms | frames siguientes (ms): %s" % [t_switch, ", ".join(fr)])

func hitch3(mode: PackedStringArray) -> void:
	if mode.has("fxwarm"):
		var sfx := main.get_node("ScreenFX")
		sfx.set_process(false)
		fx.visible = true
		(main.get_node("ScreenFX/Calm") as CanvasItem).visible = false
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		sfx.set_process(true)
	if mode.has("matwarm"):
		for w in [-1, 0, 1]:
			for k in ["wall", "floor", "trim"]:
				var r := Room.new(); r.w = w; r._style = DimensionState.LAYERS[w]
				r._layer_material(k)
				r.free()
	await get_tree().create_timer(2.0).timeout
	print("1er ingreso  -> ", await worst_after_shift(1))
	print("1er ingreso  -> ", await worst_after_shift(-2))

func frames_after(label: String, f: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	f.call()
	var cpu := (Time.get_ticks_usec() - t0) / 1000.0
	var fr := []
	var last := Time.get_ticks_usec()
	for i in 60:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		fr.append("%.0f" % ((now - last) / 1000.0))
		last = now
	var big := []
	for i in fr.size():
		if float(fr[i]) > 100.0: big.append("f%d=%sms" % [i + 1, fr[i]])
	print("%-34s llamada %.1f ms | frames >100ms en 60: %s" % [label, cpu, ", ".join(big)])
	await get_tree().create_timer(1.0).timeout

func hitch4(mode: PackedStringArray) -> void:
	await get_tree().create_timer(2.0).timeout
	if mode.has("request"):
		DimensionState._last_shift_ms = -99999
		await frames_after("request_phase_shift(+1)", func(): DimensionState.request_phase_shift(1))
		DimensionState._last_shift_ms = -99999
		await frames_after("request_phase_shift(-1)", func(): DimensionState.request_phase_shift(-1))
		DimensionState._last_shift_ms = -99999
		await frames_after("request_phase_shift(-1) SEDIM.", func(): DimensionState.request_phase_shift(-1))
	elif mode.has("anatomy"):
		var log := []
		var t0 := Time.get_ticks_usec()
		var ms := func(): return "%.0f" % ((Time.get_ticks_usec() - t0) / 1000.0)
		var on_pre := func(): log.append("pre_draw@" + ms.call())
		var on_post := func(): log.append("post_draw@%s gpu=%.0fms" % [ms.call(), RenderingServer.viewport_get_measured_render_time_gpu(sv.get_viewport_rid())])
		var on_proc := func(): log.append("process@" + ms.call())
		RenderingServer.frame_pre_draw.connect(on_pre)
		RenderingServer.frame_post_draw.connect(on_post)
		get_tree().process_frame.connect(on_proc)
		if mode.has("direct"):
			RoomGenerator.switch_layer(1)
		else:
			RoomGenerator.switch_layer.call_deferred(1)
		log.append("llamada@" + ms.call())
		for i in 4: await RenderingServer.frame_post_draw
		RenderingServer.frame_pre_draw.disconnect(on_pre)
		RenderingServer.frame_post_draw.disconnect(on_post)
		get_tree().process_frame.disconnect(on_proc)
		print(("DIRECTO  " if mode.has("direct") else "DIFERIDO "), " | ".join(log))
	elif mode.has("deferred_only"):
		await frames_after("switch diferido puro", func(): RoomGenerator.switch_layer.call_deferred(1))
	elif mode.has("after_physics"):
		await get_tree().physics_frame
		await frames_after("switch directo tras physics_frame", func(): RoomGenerator.switch_layer(1))
	elif mode.has("pw_switch"):
		DimensionState.player_w = 1
		await frames_after("player_w=1 + switch (sin señal)", func(): RoomGenerator.switch_layer(1))
	elif mode.has("combo"):
		for c in DimensionState.layer_changed.get_connections():
			var tgt: Object = c.callable.get_object()
			if (mode.has("sin_atmos") and tgt.name == "Atmosphere") or (mode.has("sin_fx") and tgt.name == "ScreenFX") or mode.has("sin_ambos"):
				DimensionState.layer_changed.disconnect(c.callable)
				print("   desconectado: ", tgt.name)
		DimensionState.player_w = 1
		await frames_after("señal + switch diferido", func():
			RoomGenerator.switch_layer.call_deferred(1)
			DimensionState.layer_changed.emit(1))
	elif mode.has("signal_first"):
		# Only the signal (handlers react to ÉTER) without swapping rooms.
		DimensionState.player_w = 1
		await frames_after("solo señal layer_changed(1)", func(): DimensionState.layer_changed.emit(1))
		DimensionState.player_w = 0
		await frames_after("solo señal layer_changed(0)", func(): DimensionState.layer_changed.emit(0))
		await frames_after("solo switch_layer(1)", func(): RoomGenerator.switch_layer(1))
	else:
		await frames_after("solo switch_layer(1)", func(): RoomGenerator.switch_layer(1))
		await frames_after("solo switch_layer(0)", func(): RoomGenerator.switch_layer(0))
		DimensionState.player_w = 1
		await frames_after("solo señal layer_changed(1)", func(): DimensionState.layer_changed.emit(1))

func fps() -> void:
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	for run in [false, true]:
		pl.rotation.y = deg_to_rad(-90 if run else -45)
		await get_tree().create_timer(1.0).timeout
		var frames := 0
		var gpu := 0.0
		var worst := 0.0
		var t0 := Time.get_ticks_usec()
		var last := t0
		var dur := 8_000_000 if run else 6_000_000
		while Time.get_ticks_usec() - t0 < dur:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var dt := (now - last) / 1e6
			last = now
			if frames > 0: worst = maxf(worst, dt)
			frames += 1
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(sv.get_viewport_rid())
			if run: pl.global_position.x += 7.5 * dt
		var secs := (Time.get_ticks_usec() - t0) / 1e6
		print("%-9s FPS %.1f | GPU medio %.1f ms | peor frame %.0f ms | estado: %s" % ["corriendo" if run else "quieto", frames / secs, gpu / frames, worst * 1000.0, fx_state()])

func fx_state() -> String:
	var calm := main.get_node_or_null("ScreenFX/Calm") as CanvasItem
	return "FX=%s Calm=%s" % [fx.visible, calm.visible if calm else "n/a"]

func shots(mode: PackedStringArray) -> void:
	var tag := "after" if mode.has("after") else "before"
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	var monster := get_tree().get_first_node_in_group("monster") as Monster
	await get_tree().create_timer(0.5).timeout
	await shot("fx_%s_1calm" % tag)
	print("calma:    ", fx_state())
	# Real danger: entity hunting on your layer, 5 m in front.
	monster.set_process(true)
	monster.entity_w = DimensionState.player_w
	monster._activate()
	monster.set_physics_process(false)
	var fwd := -pl.global_basis.z
	monster.global_position = pl.global_position + fwd * 5.0 + Vector3(0, -0.1, 0)
	await get_tree().create_timer(1.2).timeout
	await shot("fx_%s_2danger" % tag)
	print("peligro:  ", fx_state())
	monster._deactivate()
	monster.set_process(false)
	await get_tree().create_timer(1.5).timeout
	print("post-peligro (vuelve a calma): ", fx_state())
	# Real phase shift.
	DimensionState.request_phase_shift(1)
	await get_tree().create_timer(0.08).timeout
	await shot("fx_%s_3shift" % tag)
	print("cruce:    ", fx_state())
	await get_tree().create_timer(1.2).timeout
	await shot("fx_%s_4calm_eter" % tag)
	print("post-cruce: ", fx_state())
