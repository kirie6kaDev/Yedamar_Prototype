extends SceneTree
## Headless automated playtest for Noctis Live / Yedamar.
## Run:  godot --headless --fixed-fps 30 --path . -s res://tests/playtest.gd -- --out=/abs/dir [--phases=a,b] [--days=N]
## Writes <out>/playtest.json and <out>/playtest.log. Never touches the player's saves outside user://saves of this project.

const REACH := 1.4
var game
var out_dir := "user://playtest"
var phases: Array = []
var long_days := 2.0
var report: Dictionary = {"phases": {}, "toasts": [], "issues": []}
var toasts: Array = []
var log_lines: PackedStringArray = []
var frame_usec: Array = []
var t_start := 0

func _initialize() -> void:
	t_start = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--phases="): phases = arg.trim_prefix("--phases=").split(",")
		elif arg.begins_with("--days="): long_days = float(arg.trim_prefix("--days="))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_wipe_saves()
	var t0 := Time.get_ticks_msec()
	game = load("res://main.tscn").instantiate()
	root.add_child.call_deferred(game)
	_boot.call_deferred(t0)

func _boot(t0: int) -> void:
	for i in 600:
		if game.is_node_ready() and game.hud != null: break
		await process_frame
	report.boot_ms = Time.get_ticks_msec() - t0
	game.hud._toast_box.child_entered_tree.connect(_on_toast)
	_run()

func _wipe_saves() -> void:
	var dir := DirAccess.open("user://saves")
	if dir == null: return
	for f in dir.get_files(): dir.remove(f)

func _on_toast(node: Node) -> void:
	_read_toast.call_deferred(node)

func _read_toast(node: Node) -> void:
	if not is_instance_valid(node): return
	for l in node.find_children("*", "Label", true, false):
		toasts.append(str(l.text)); log_lines.append("  [toast] " + str(l.text))
	for l in node.find_children("*", "RichTextLabel", true, false):
		toasts.append(str(l.text)); log_lines.append("  [toast] " + str(l.text))

func L(msg: String) -> void:
	log_lines.append(msg)
	print(msg)

func issue(area: String, text: String, data: Variant = null) -> void:
	report.issues.append({"area": area, "text": text, "data": data})
	L("  !! [" + area + "] " + text + ("" if data == null else " " + str(data)))

func want(name: String) -> bool:
	return phases.is_empty() or phases.has(name)

func frames(n: int) -> void:
	for i in n:
		var t := Time.get_ticks_usec()
		await process_frame
		frame_usec.append(Time.get_ticks_usec() - t)

func until(cond: Callable, max_frames: int) -> int:
	for i in max_frames:
		if cond.call(): return i
		var t := Time.get_ticks_usec()
		await process_frame
		frame_usec.append(Time.get_ticks_usec() - t)
	return -1

func stats(samples: Array) -> Dictionary:
	if samples.is_empty(): return {}
	var s := samples.duplicate(); s.sort()
	var total := 0.0
	for v in s: total += v
	return {"n": s.size(), "avg_ms": snappedf(total / s.size() / 1000.0, 0.01), "p50_ms": snappedf(s[s.size() / 2] / 1000.0, 0.01), "p95_ms": snappedf(s[int(s.size() * 0.95)] / 1000.0, 0.01), "p99_ms": snappedf(s[int(s.size() * 0.99)] / 1000.0, 0.01), "max_ms": snappedf(s[-1] / 1000.0, 0.01), "over_33ms": s.filter(func(v): return v > 33333).size(), "over_100ms": s.filter(func(v): return v > 100000).size()}

func nav_stats_reset() -> void:
	var n = game.navigation
	if "stats_calls" in n:
		n.stats_calls = 0; n.stats_usec = 0; n.stats_max_usec = 0; n.stats_failed = 0

func nav_stats() -> Dictionary:
	var n = game.navigation
	if not "stats_calls" in n: return {}
	return {"calls": n.stats_calls, "failed": n.stats_failed, "total_ms": snappedf(n.stats_usec / 1000.0, 0.1), "max_ms": snappedf(n.stats_max_usec / 1000.0, 0.1)}

func brother(): return game.brother

func dist(a: Vector3, b: Vector3) -> float: return Vector2(a.x - b.x, a.z - b.z).length()

func select(role: String) -> void:
	game._select_character(role)

func give(role: String, items: Dictionary) -> void:
	var inv: Dictionary = game._inventory(role)
	for k in items: inv[k] = int(inv.get(k, 0)) + int(items[k])

func queue_of(role: String) -> Array: return game.orders.get(role, [])

func idle(role: String) -> bool: return queue_of(role).is_empty()

## Life autonomy refills an empty queue, so "queue empty" is not a reliable
## completion signal: track the exact order dictionary instead.
func last_order(role: String, action: String, id: String = "") -> Variant:
	var q: Array = queue_of(role)
	for i in range(q.size() - 1, -1, -1):
		if str(q[i].get("action", "")) == action and (id.is_empty() or str(q[i].get("id", "")) == id): return q[i]
	return null

func gone(role: String, ref: Variant) -> bool:
	if ref == null: return true
	for o in queue_of(role):
		if is_same(o, ref): return false
	return true

func diag(role: String) -> Dictionary:
	var a = game._hero(role)
	var q := []
	for o in queue_of(role): q.append("%s:%s:%s%s" % [o.get("action"), o.get("id", ""), o.get("phase", ""), ":auto" if o.get("automatic", false) else ""])
	return {"queue": q, "moving": a.is_moving(), "pos": [snappedf(a.position.x, 0.1), snappedf(a.position.z, 0.1)], "in_combat": game.in_combat, "role_in_combat": game._role_in_combat(role), "caravan_busy": game._caravan_busy(role), "caravan_mode": str(game.caravan.mode), "ranch_busy": game._ranch_busy(role), "sleeping": game.state.characters[role].get("sleeping", false), "dialogue": not game.current_dialogue.is_empty(), "paused": paused, "time": game.caravan.get_clock_text(), "zombies": game.settlement.zombies.size(), "hp": a.health}

func dismiss_dialogue() -> void:
	for i in 12:
		if game.current_dialogue.is_empty() and game.dialogue_queue.is_empty(): return
		game._next_dialogue()

## Run an object action via the real context path and wait for the queue to drain.
var fast_travel := true

func do_action(role: String, action: String, id: String, max_frames: int = 3000) -> Dictionary:
	select(role)
	var t0 := toasts.size()
	var far := 0.0
	if fast_travel and game.world.objects.has(id):
		var goal: Vector3 = game.world.objects[id].get("approach", game.world.objects[id].position)
		far = dist(game._hero(role).position, goal)
		if far > 120.0:
			# the world is km-scale; on-foot travel is measured separately (walk_sample)
			var dir: Vector3 = (game._hero(role).position - goal); dir.y = 0
			teleport(role, goal + dir.normalized() * 20.0)
			await frames(2)
	var start: Vector3 = game._hero(role).position
	var f0 := Engine.get_frames_drawn()
	game._on_action(action, id)
	var ref = last_order(role, action, id)
	var used := await until(func(): return gone(role, ref), max_frames)
	if used < 0:
		L("    TIMEOUT diag " + JSON.stringify(diag(role)))
		game._clear_orders()
	dismiss_dialogue()
	var target: Vector3 = game.world.objects[id].get("approach", game.world.objects[id].position) if game.world.objects.has(id) else start
	return {"action": action, "id": id, "frames": used, "timeout": used < 0, "end_dist": snappedf(dist(game._hero(role).position, target), 0.01), "walked": snappedf(dist(start, game._hero(role).position), 0.1), "fast_travel_m": snappedf(far, 1) if far > 120.0 else 0.0, "toasts": toasts.slice(t0)}

func walk_to(role: String, point: Vector3, max_frames: int = 3000) -> Dictionary:
	select(role)
	var t0 := toasts.size()
	var ref := {"action": "move", "position": point, "phase": "waiting"}
	game._enqueue(role, ref)
	var used := await until(func(): return gone(role, ref), max_frames)
	return {"frames": used, "timeout": used < 0, "end_dist": snappedf(dist(game._hero(role).position, point), 0.01), "toasts": toasts.slice(t0)}

func teleport(role: String, p: Vector3) -> void:
	var a = game._hero(role)
	a.stop_moving()
	a.global_position = p

func _run() -> void:
	await frames(5)
	L("BOOT ms=%d objects=%d roles=%s" % [report.boot_ms, game.world.objects.size(), str(game._roles())])
	var types := {}
	for id in game.world.objects:
		var t := str(game.world.objects[id].type)
		types[t] = int(types.get(t, 0)) + 1
	report.object_types = types
	dismiss_dialogue()
	var phase_list := [["profile", _phase_profile], ["idle_perf", _phase_idle_perf], ["nav_static", _phase_nav_static], ["campaign", _phase_campaign], ["crafting", _phase_crafting], ["queue_edges", _phase_queue_edges], ["actions", _phase_actions], ["life", _phase_life], ["ui", _phase_ui], ["save_load", _phase_save_load], ["walk_sample", _phase_walk_sample], ["long_run", _phase_long_run]]
	for entry in phase_list:
		if not want(entry[0]): continue
		L("=== PHASE " + entry[0])
		frame_usec.clear(); nav_stats_reset()
		var t := Time.get_ticks_msec()
		var res = await entry[1].call()
		if res == null: res = {}
		res["wall_ms"] = Time.get_ticks_msec() - t
		res["frame_stats"] = stats(frame_usec)
		res["nav"] = nav_stats()
		report.phases[entry[0]] = res
		L("  -> " + JSON.stringify({"wall_ms": res.wall_ms, "frames": res.frame_stats, "nav": res.nav}))
		_flush()
	report.toasts = toasts
	report.total_ms = Time.get_ticks_msec() - t_start
	_flush()
	L("DONE total_ms=%d issues=%d" % [report.total_ms, report.issues.size()])
	_flush()
	quit(0)

func _flush() -> void:
	var f := FileAccess.open(out_dir.path_join("playtest.json"), FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(report, "  ", false)); f.close()
	var g := FileAccess.open(out_dir.path_join("playtest.log"), FileAccess.WRITE)
	if g: g.store_string("\n".join(log_lines)); g.close()

# ---------------------------------------------------------------- phases
func _phase_idle_perf() -> Dictionary:
	Engine.time_scale = 1.0
	await frames(300)
	return {"note": "300 frames at 1x, headless (no GPU): CPU-side frame cost only"}

## Per-subsystem cost: call each tick/update directly and time it (approximate profiler).
func _phase_profile() -> Dictionary:
	var g = game
	var probes := {
		"main._update_ui": func(): g._update_ui(),
		"main._needs": func(): g._needs(0.033),
		"main._update_hover": func(): g._update_hover(),
		"main._follow": func(): g._follow(),
		"main._plan_workdays": func(): g._plan_workdays(),
		"main._advance": func(): g._advance(),
		"main._snapshot": func(): g._snapshot(),
		"main._save_slot(realtime)": func(): g._save_slot("realtime", false),
		"saves.list_slots": func(): g.saves.list_slots(),
		"life.tick(0.033)": func(): g.life.tick(0.033),
		"life.sim.advance(0.5)": func(): g.life.sim.advance(0.5),
		"life._update_population": func(): g.life._update_population(),
		"life._autonomy": func(): g.life._autonomy(),
		"life.update_ui": func(): g.life.update_ui(),
		"v5.tick(0.033)": func(): g.v5.tick(0.033),
		"v5.domestic.tick": func(): g.v5.domestic.tick(0.033),
		"v5.civic.advance": func(): g.v5.civic.advance(0.033),
		"settlement.tick": func(): g.settlement.tick(0.033),
		"ranch.tick": func(): g.ranch.tick(0.033),
		"city._update_roofs": func(): g.city._update_roofs(),
		"craft_context": func(): g._craft_context(g.active.position) if g.has_method("_craft_context") else null,
	}
	var res := {}
	for name in probes:
		var times := []
		for i in 15:
			var t := Time.get_ticks_usec()
			probes[name].call()
			times.append(Time.get_ticks_usec() - t)
		times.sort()
		res[name] = {"median_ms": snappedf(times[7] / 1000.0, 0.01), "max_ms": snappedf(times[-1] / 1000.0, 0.01)}
		L("  profile %-28s median=%6.2f ms max=%6.2f ms" % [name, times[7] / 1000.0, times[-1] / 1000.0])
	return res

## Static reachability: path from the farm start to every interactable's approach point,
## then replay the path with the actor's own step rule to find segments the actor would refuse.
func _phase_nav_static() -> Dictionary:
	var nav = game.navigation
	var from: Vector3 = game._ground(game.FARM_START)
	var rows := []
	var unreachable := []
	var blocked := []
	var far_end := []
	var by_type := {}
	for id in game.world.objects:
		var o: Dictionary = game.world.objects[id]
		var t := str(o.type)
		if t in ["life_person", "enemy"]: continue
		var target: Vector3 = o.get("approach", o.position)
		var t0 := Time.get_ticks_usec()
		var path: PackedVector3Array = nav.path(from, target)
		var us := Time.get_ticks_usec() - t0
		var bt: Dictionary = by_type.get_or_add(t, {"n": 0, "unreachable": 0, "blocked": 0, "far_end": 0})
		bt.n += 1
		if path.is_empty():
			unreachable.append(id); bt.unreachable += 1
			continue
		var end_d := dist(path[-1], target)
		if end_d > REACH:
			far_end.append({"id": id, "type": t, "end_dist": snappedf(end_d, 0.01)}); bt.far_end += 1
		# replay with 0.2 m steps exactly like actor._physics_process (walkability of next step)
		var pos := from
		var refused := false
		for p in path:
			var seg := Vector2(p.x - pos.x, p.z - pos.z)
			var n := maxi(1, ceili(seg.length() / 0.2))
			for i in range(1, n + 1):
				var q := Vector2(pos.x, pos.z) + seg * (float(i) / n)
				if not nav.is_walkable(q):
					refused = true; break
			if refused: break
			pos = p
		if refused:
			blocked.append({"id": id, "type": t, "at": [snappedf(pos.x, 0.1), snappedf(pos.z, 0.1)]}); bt.blocked += 1
		rows.append(us)
	var s := rows.duplicate(); s.sort()
	var res := {"checked": rows.size() + unreachable.size(), "unreachable": unreachable.size(), "unreachable_ids": unreachable.slice(0, 40), "path_blocked_by_step_rule": blocked.size(), "blocked_sample": blocked.slice(0, 40), "end_beyond_reach": far_end.size(), "far_end_sample": far_end.slice(0, 40), "by_type": by_type}
	if not s.is_empty(): res["path_ms"] = {"avg": snappedf(s.reduce(func(a, b): return a + b, 0) / s.size() / 1000.0, 0.01), "p95": snappedf(s[int(s.size() * .95)] / 1000.0, 0.01), "max": snappedf(s[-1] / 1000.0, 0.01)}
	if unreachable.size() > 0: issue("nav", "%d interactables have no path from the farm" % unreachable.size())
	if blocked.size() > 0: issue("nav", "%d computed paths cross cells the actor refuses to step on (string-pulling shortcut through props)" % blocked.size())
	if far_end.size() > 0: issue("nav", "%d paths end farther than REACH=1.4 from the approach point" % far_end.size())
	return res

## End-to-end story scenario, played through real walking and real actions (resources are gathered when present nearby, otherwise granted and noted).
func _phase_campaign() -> Dictionary:
	Engine.time_scale = 6.0
	var steps := []
	var role := "brother"
	select(role)
	game.state.characters.sister.follow = true
	var rec := func(name: String, r: Dictionary):
		r["step"] = name; r["objective_after"] = game._objective()
		steps.append(r)
		L("  step %s -> frames=%s timeout=%s end_dist=%s toasts=%s" % [name, str(r.get("frames")), str(r.get("timeout")), str(r.get("end_dist")), str(r.get("toasts", []))])
	rec.call("talk farmer", await do_action(role, "talk", "farmer"))
	# gather 3 stones + 2 branches + extra branches/herbs for later quests
	var got := {"stone": 0, "branch": 0}
	for kind in ["stone", "stone", "branch", "branch", "branch"]:
		var id: String = game._nearest_type(kind, brother().position, 400)
		if id.is_empty():
			issue("campaign", "no %s found within 400 m of hero" % kind); continue
		var r := await do_action(role, "gather", id)
		rec.call("gather " + kind + " " + id, r)
	var inv: Dictionary = game._inventory(role)
	if int(inv.get("stone", 0)) < 3 or int(inv.get("branch", 0)) < 2:
		issue("campaign", "not enough stone/branch after gathering", inv.duplicate())
		give(role, {"stone": 3, "branch": 2})
	game._craft("stone_pickaxe")
	var cref = last_order(role, "craft:stone_pickaxe")
	var used := await until(func(): return gone(role, cref), 3000)
	rec.call("craft stone_pickaxe (hand)", {"frames": used, "timeout": used < 0, "pickaxe": int(inv.get("pickaxe", 0)), "toasts": toasts.slice(-3)})
	rec.call("talk herbalist", await do_action(role, "talk", "herbalist"))
	var cauldron: String = game._nearest_type("cauldron", brother().position, 5000)
	if cauldron.is_empty(): issue("campaign", "no cauldron in world")
	else:
		var r := await do_action(role, "brew", cauldron)
		rec.call("brew->open crafting at cauldron", r)
		game._craft("healing_potion", cauldron)
		var pref = last_order(role, "craft:healing_potion")
		used = await until(func(): return gone(role, pref), 3000)
		rec.call("craft healing_potion", {"frames": used, "timeout": used < 0, "potion": int(inv.get("healing_potion", 0)), "toasts": toasts.slice(-3)})
	rec.call("talk courier", await do_action(role, "talk", "courier"))
	if int(inv.get("branch", 0)) < 3:
		for i in 3:
			var id: String = game._nearest_type("branch", brother().position, 400)
			if not id.is_empty(): await do_action(role, "gather", id)
	if int(inv.get("branch", 0)) < 3: give(role, {"branch": 3}); issue("campaign", "had to grant branches for woodcutter")
	rec.call("talk woodcutter", await do_action(role, "talk", "woodcutter"))
	rec.call("talk guard", await do_action(role, "talk", "guard"))
	if int(inv.get("herb", 0)) < 2:
		var hid: String = game._nearest_type("herb", brother().position, 600)
		if not hid.is_empty(): await do_action(role, "gather", hid)
	if int(inv.get("herb", 0)) < 2: give(role, {"herb": 2}); issue("campaign", "had to grant herbs for forest_helper")
	rec.call("talk forest_helper", await do_action(role, "talk", "forest_helper"))
	# equip a sword for combat
	give(role, {"sword": 1}); game._use_item("sword")
	for eid in ["forest_1", "forest_2"]:
		var r := await do_action(role, "attack", eid, 600)
		var fought := await until(func(): return game.state.defeated.has(eid) or game.brother.health <= 0 or not game.in_combat and r.frames >= 0 and game.state.defeated.has(eid), 4000)
		await until(func(): return not game.in_combat, 2000)
		rec.call("fight " + eid, {"frames": fought, "defeated": game.state.defeated.has(eid), "hp": game.brother.health, "toasts": toasts.slice(-3)})
	rec.call("talk road_warden", await do_action(role, "talk", "road_warden"))
	if int(inv.get("wood", 0)) < 2: give(role, {"wood": 2}); issue("campaign", "had to grant wood for cartwright (branches give 1 wood each)")
	rec.call("talk cartwright", await do_action(role, "talk", "cartwright"))
	if int(inv.get("ration", 0)) < 1: give(role, {"ration": 1})
	rec.call("talk mine_traveler", await do_action(role, "talk", "mine_traveler"))
	rec.call("talk miner", await do_action(role, "talk", "miner"))
	for i in 3:
		var ore: String = game._nearest_type("ore", brother().position, 600)
		if ore.is_empty(): issue("campaign", "no ore left near the mine"); break
		rec.call("mine " + ore, await do_action(role, "mine", ore, 4000))
		if int(game.state.gathered_ore) >= 3: break
	give(role, {"healing_potion": 3})
	game.brother.health = game.brother.max_health
	for eid in ["mine_1", "boss"]:
		if game.state.defeated.has(eid): continue
		var r := await do_action(role, "attack", eid, 900)
		var fought := 0
		for k in 8000:
			if game.state.defeated.has(eid) or not game.in_combat and k > 60: break
			if game.brother.health < 40 and int(inv.get("healing_potion", 0)) > 0: game._use_item("healing_potion")
			await process_frame
			fought = k
		await until(func(): return not game.in_combat, 2000)
		rec.call("fight " + eid, {"frames": fought, "defeated": game.state.defeated.has(eid), "hp": game.brother.health, "toasts": toasts.slice(-4)})
	rec.call("talk farmer (finish)", await do_action(role, "talk", "farmer"))
	var done: bool = game.state.flags.get("completed", false)
	if not done: issue("campaign", "story did not reach completed", {"objective": game._objective(), "stage": game.state.stage})
	Engine.time_scale = 1.0
	return {"completed": done, "stage": game.state.stage, "steps": steps, "flags": game.state.flags.duplicate()}

func _phase_crafting() -> Dictionary:
	Engine.time_scale = 6.0
	var role := "brother"
	select(role)
	game.state.flags.alchemy_learned = true
	var results := {}
	var Campaign = game.Campaign
	for rid in Campaign.RECIPES:
		var r: Dictionary = Campaign.RECIPES[rid]
		var inv: Dictionary = game._inventory(role)
		give(role, r.cost)
		if not str(r.get("needs_tool", "")).is_empty(): give(role, {str(r.needs_tool): 1})
		var before := int(inv.get(r.item, 0))
		var start: Vector3 = brother().position
		var station := str(r.station)
		var target: String = game.industry.find_station(rid, start) if not station.is_empty() else ""
		var t0 := toasts.size()
		if station.is_empty() or target.is_empty():
			game._craft(rid)
		elif game.hud.has_method("show_crafting_at"):
			# contextual crafting (fixed branch): choose the recipe at the station itself
			game._on_action("craft:" + rid, target)
		else:
			game._craft(rid)
		var oref = last_order(role, "craft:" + rid)
		var used := await until(func(): return gone(role, oref), 4000)
		var after := int(inv.get(r.item, 0))
		var row := {"station": station, "station_id": target, "station_dist_m": snappedf(dist(start, game.world.objects[target].position), 1) if not target.is_empty() else 0, "frames": used, "ok": after > before, "toasts": toasts.slice(t0)}
		results[rid] = row
		if after <= before: issue("crafting", "recipe %s did not produce %s" % [rid, r.item], row)
	# context rule: a station recipe requested far from any station
	teleport(role, game._ground(game.FARM_START))
	game.hud.dismiss_all()
	var tq := toasts.size()
	game._craft("smelt_iron")
	await frames(3)
	var far_request := {"queued": not idle(role), "toasts": toasts.slice(tq)}
	game._clear_orders()
	var hand := []
	for rid in Campaign.RECIPES: if str(Campaign.RECIPES[rid].station).is_empty(): hand.append(rid)
	Engine.time_scale = 1.0
	return {"recipes": results, "hand_recipes": hand, "station_recipe_far_from_station": far_request, "note": "baseline: C window lists every recipe and _craft auto-walks to the nearest station anywhere on the map; fixed: station recipes only at the station"}

func _phase_queue_edges() -> Dictionary:
	Engine.time_scale = 4.0
	var role := "brother"
	select(role)
	game._clear_orders()
	var res := {}
	var p: Vector3 = brother().position
	# 1) spam: 20 move orders
	for i in 20: game._order_move(p + Vector3(randf_range(-20, 20), 0, randf_range(-20, 20)))
	res.spam_queue_len = queue_of(role).size()
	game._clear_orders()
	# 2) click ground while busy: does a new move replace or append?
	var far: Vector3 = game._ground(Vector2(p.x + 60, p.z))
	game._order_move(far)
	await frames(10)
	game._order_move(game._ground(Vector2(p.x - 10, p.z)))
	res.click_while_walking_queue_len = queue_of(role).size()
	res.click_while_walking_first_target = str(queue_of(role)[0].get("position")) if not queue_of(role).is_empty() else ""
	game._clear_orders()
	# 3) cancel mid-action
	var w: String = game._nearest_type("well", brother().position, 2000)
	if not w.is_empty():
		select(role); game._on_action("drink", w)
		await until(func(): return idle(role) or str(queue_of(role)[0].phase) == "working", 2000)
		res.cancel_phase = str(queue_of(role)[0].phase) if not idle(role) else "already-finished"
		game._cancel_order(0)
		await frames(5)
		res.cancel_after_moving = brother().is_moving()
		res.cancel_after_queue = queue_of(role).size()
	# 4) unreachable: water / out of bounds
	var water := Vector3(game.world.bounds.position.x + 5, 0, game.world.bounds.position.y + 5)
	var t0 := toasts.size()
	game._enqueue(role, {"action": "move", "position": water, "phase": "waiting"})
	game._enqueue(role, {"action": "move", "position": brother().position + Vector3(3, 0, 0), "phase": "waiting"})
	await frames(30)
	res.unreachable_then_valid_queue = queue_of(role).size()
	res.unreachable_toasts = toasts.slice(t0)
	await until(func(): return idle(role), 600)
	game._clear_orders()
	# 5) double-pop check: unreachable *object* action followed by a valid move
	var fake_id := "__test_unreachable"
	game.world.objects[fake_id] = {"id": fake_id, "type": "well", "name": "test", "description": "", "position": water, "approach": water, "node": Node3D.new()}
	game._enqueue(role, {"action": "drink", "id": fake_id, "phase": "waiting", "remaining": 0.0})
	game._enqueue(role, {"action": "move", "position": brother().position + Vector3(4, 0, 0), "phase": "waiting"})
	await frames(3)
	res.double_pop_remaining = queue_of(role).size()
	res.double_pop_lost_next_order = queue_of(role).is_empty()
	if queue_of(role).is_empty(): issue("queue", "failed path to object also removed the NEXT queued order (double pop)")
	game.world.objects[fake_id].node.free()
	game.world.objects.erase(fake_id)
	game._clear_orders()
	# 6) life action with unreachable venue followed by valid move (life.run_order path)
	res.life_double_pop = await _life_double_pop(role)
	# 7) sleep then walk away (bed exit)
	var bed: String = game._nearest_type("bed", brother().position, 3000)
	if not bed.is_empty():
		game.caravan.day_time = 1300.0
		var r := await do_action(role, "sleep", bed, 9000)
		res.sleep = r
		var after_sleep := await walk_to(role, game._ground(Vector2(brother().position.x + 12, brother().position.z + 12)), 900)
		res.walk_after_sleep = after_sleep
		if after_sleep.end_dist > 2.0: issue("queue", "hero could not walk away after sleeping in bed " + bed, after_sleep)
	Engine.time_scale = 1.0
	return res

func _life_double_pop(role: String) -> Dictionary:
	var water := Vector3(game.world.bounds.position.x + 5, 0, game.world.bounds.position.y + 5)
	var q: Array = queue_of(role)
	q.append({"action": "life:relax", "payload": {"actor_id": role}, "position": water, "id": "", "duration": 5.0, "remaining": 0.0, "phase": "waiting", "automatic": false, "label": "test"})
	q.append({"action": "move", "position": brother().position + Vector3(5, 0, 0), "phase": "waiting"})
	await frames(3)
	var r := {"queue_after": q.size(), "first": str(q[0].action) if not q.is_empty() else ""}
	game._clear_orders()
	return r

func _phase_actions() -> Dictionary:
	Engine.time_scale = 6.0
	var role := "sister"
	select(role)
	var res := {}
	for pair in [["drink", "well"], ["fill", "well"], ["rest", "campfire"], ["search", "crate"], ["hide", "bush"], ["feed", "animal"], ["gather", "berry"], ["gather", "herb"], ["gather", "mint"], ["gather", "lavender"], ["gather", "hay"], ["gather", "carrot"]]:
		var id: String = game._nearest_type(pair[1], game._hero(role).position, 3000)
		if id.is_empty(): res[pair[0] + ":" + pair[1]] = "no object"; continue
		var r := await do_action(role, pair[0], id, 3000)
		res[pair[0] + ":" + pair[1]] = r
		if r.timeout: issue("actions", "%s on %s timed out" % [pair[0], id], r)
		game._hero(role).set_hidden_in_cover(false)
	# items
	var used := {}
	give(role, {"bread": 1, "bandage": 1, "water": 1, "stamina_potion": 1, "ration": 1, "berry": 1, "apple": 1, "fish": 1})
	game._hero(role).health = 30
	for it in ["bread", "bandage", "water", "stamina_potion", "ration", "berry", "apple", "fish", "plank"]:
		var t0 := toasts.size(); game._use_item(it); used[it] = toasts.slice(t0)
	res.use_items = used
	Engine.time_scale = 1.0
	return res

func _phase_life() -> Dictionary:
	Engine.time_scale = 6.0
	var role := "brother"
	select(role)
	var life = game.life
	var sim = life.sim
	var res := {}
	res.residents = sim.residents.size()
	res.professions = sim.professions.size()
	res.coins_start = int(sim.households.house_player.coins)
	# context action catalogue over city objects
	var verbs := {}
	var sampled := 0
	for id in game.world.objects:
		var t := str(game.world.objects[id].type)
		if not t.begins_with("life_") and t != "domestic": continue
		var acts: Array = life.context_actions(id, role)
		for a in acts: verbs[str(a.get("id", ""))] = int(verbs.get(str(a.get("id", "")), 0)) + 1
		sampled += 1
	res.context_objects = sampled
	res.context_verbs = verbs
	# professions: can we take any job with zero skill?
	var taken := []
	var keys: Array = sim.professions.keys()
	for i in mini(6, keys.size()):
		var prof: String = keys[i * maxi(1, keys.size() / 6)]
		var spec: Dictionary = sim.command_spec(role, "apply_job", {"profession_id": prof})
		taken.append({"profession": prof, "allowed": spec.get("ok", false), "reason": spec.get("reason", "")})
	res.apply_job_any = taken
	if taken.all(func(x): return x.allowed): issue("professions", "every sampled profession can be taken with zero skill/requirements (findings only)")
	# real life actions via request(): eat/relax/work/buy
	var outcome := {}
	for act in [["relax", {}], ["eat", {}], ["wash", {}], ["toilet", {}], ["read", {}], ["cook", {}], ["buy", {"item_id": "bread", "quantity": 1}], ["sell", {"item_id": "stone", "quantity": 1}], ["sell", {"item_id": "iron_sword", "quantity": 1}]]:
		var t0 := toasts.size()
		give(role, {"stone": 1, "iron_sword": 1})
		life.request(act[0], act[1].merged({"actor_id": role}))
		var u := await until(func(): return idle(role), 2500)
		outcome[act[0] + str(act[1].get("item_id", ""))] = {"frames": u, "toasts": toasts.slice(t0), "coins": int(sim.households.house_player.coins)}
	res.life_actions = outcome
	# job: apply then work
	var prof0: String = str(keys[0])
	life.request("apply_job", {"actor_id": role, "profession_id": prof0})
	await until(func(): return idle(role), 2500)
	var wt0 := toasts.size()
	life.request("work", {"actor_id": role, "profession_id": prof0})
	var wu := await until(func(): return idle(role), 5000)
	res.work = {"profession": prof0, "frames": wu, "toasts": toasts.slice(wt0), "coins": int(sim.households.house_player.coins)}
	res.coins_end = int(sim.households.house_player.coins)
	Engine.time_scale = 1.0
	return res

func _phase_ui() -> Dictionary:
	var hud = game.hud
	var res := {}
	var calls := [["inventory", func(): hud.show_inventory()], ["crafting", func(): hud.show_crafting()], ["journal", func(): hud.show_journal("test")], ["work", func(): hud.show_work()], ["skills", func(): hud.show_skills()], ["construction", func(): hud.show_construction()], ["cart", func(): hud.show_cart_storage()], ["map", func(): game._show_map()], ["pause", func(): game._pause()]]
	for tab in ["wellbeing", "people", "careers", "market", "properties", "household", "calendar", "status", "pursuits"]:
		calls.append(["life:" + tab, func(): hud.show_life(tab)])
	for c in calls:
		var t := Time.get_ticks_usec()
		c[1].call()
		await frames(3)
		res[c[0]] = {"open_ms": snappedf((Time.get_ticks_usec() - t) / 1000.0, 0.1), "modal": hud.is_modal_open()}
		if c[0] == "pause": game._resume()
		hud.dismiss_all()
		await frames(2)
	# controls count as a rough complexity metric
	res.control_nodes = hud.find_children("*", "Control", true, false).size()
	res.buttons = hud.find_children("*", "Button", true, false).size()
	return res

func _phase_save_load() -> Dictionary:
	var res := {}
	game._clear_orders()
	var t := Time.get_ticks_usec()
	game._save_slot("manual_1")
	res.save_ms = snappedf((Time.get_ticks_usec() - t) / 1000.0, 0.1)
	t = Time.get_ticks_usec()
	game._save_slot("realtime", false)
	res.realtime_save_ms = snappedf((Time.get_ticks_usec() - t) / 1000.0, 0.1)
	var path := ProjectSettings.globalize_path("user://saves/manual_1.json")
	res.save_bytes = FileAccess.get_file_as_bytes("user://saves/manual_1.json").size()
	t = Time.get_ticks_usec()
	game.slot_cache = game.saves.list_slots()
	res.list_slots_ms = snappedf((Time.get_ticks_usec() - t) / 1000.0, 0.1)
	var inv_before: Dictionary = game._inventory("brother").duplicate(true)
	var pos_before: Vector3 = brother().position
	give("brother", {"stone": 50})
	teleport("brother", pos_before + Vector3(10, 0, 0))
	t = Time.get_ticks_usec()
	game._load_slot("manual_1")
	res.load_ms = snappedf((Time.get_ticks_usec() - t) / 1000.0, 0.1)
	await frames(5)
	var diff := {}
	var retyped := []
	var now_inv: Dictionary = game._inventory("brother")
	for k in now_inv.keys() + inv_before.keys():
		if int(now_inv.get(k, 0)) != int(inv_before.get(k, 0)): diff[k] = [inv_before.get(k, 0), now_inv.get(k, 0)]
		elif now_inv.has(k) and inv_before.has(k) and typeof(now_inv[k]) != typeof(inv_before[k]) and not retyped.has(k): retyped.append(k)
	res.inventory_diff = diff
	# value-equal is what matters; hash() also differs on key order / int-vs-float after JSON
	res.inventory_restored = diff.is_empty()
	res.inventory_hash_equal = now_inv.hash() == inv_before.hash()
	res.inventory_retyped_keys = retyped
	res.position_restored = dist(brother().position, pos_before) < 0.5
	if not res.inventory_restored or not res.position_restored: issue("save", "save/load roundtrip mismatch", res)
	return res

## Walk to one object of every type (chained, like a player), real movement at 8x.
func _phase_walk_sample() -> Dictionary:
	Engine.time_scale = 8.0
	var role := "brother"
	select(role)
	game._clear_orders()
	var seen := {}
	var rows := []
	var fails := 0
	var ids: Array = game.world.objects.keys()
	ids.shuffle()
	for id in ids:
		var o: Dictionary = game.world.objects[id]
		var t := str(o.type)
		if t in ["life_person", "enemy"] or int(seen.get(t, 0)) >= 2: continue
		seen[t] = int(seen.get(t, 0)) + 1
		var target: Vector3 = o.get("approach", o.position)
		var d0 := dist(brother().position, target)
		if d0 > 900: teleport(role, game._ground(Vector2(target.x + 40, target.z + 40)) if game.navigation.is_walkable(Vector2(target.x + 40, target.z + 40)) else brother().position)
		var r := await walk_to(role, target, 2500)
		r["id"] = id; r["type"] = t
		rows.append(r)
		if r.end_dist > REACH: fails += 1
	Engine.time_scale = 1.0
	if fails > 0: issue("nav", "%d of %d sampled objects not reached within REACH by real walking" % [fails, rows.size()])
	return {"walks": rows, "not_reached": fails}

## Several in-game days at high time scale: frame cost, stuck agents, autonomy.
func _phase_long_run() -> Dictionary:
	# start in town so the near-LOD citizen actors actually exist around the hero
	game._clear_orders()
	if game.world.objects.has("life_job_blacksmith"):
		var c: Vector3 = game.world.objects["life_job_blacksmith"].get("approach", game.world.objects["life_job_blacksmith"].position)
		teleport("brother", c)
		teleport("sister", c + Vector3(1.5, 0, 0))
	await frames(10)
	# life_bridge re-applies its own `speed` when the family wakes up (max 3x in UI), so set both
	var old_speed: float = game.life.speed
	game.life.speed = 10.0
	Engine.time_scale = 10.0
	var minutes := long_days * 1440.0
	var frames_needed := int(minutes / (10.0 / 30.0))
	var samples := []
	var last := {}
	var stuck := {}
	var t0 := toasts.size()
	var day0 := int(game.caravan.day_number)
	for k in frames_needed:
		var t := Time.get_ticks_usec()
		await process_frame
		frame_usec.append(Time.get_ticks_usec() - t)
		if k % 300 == 0:
			var moving := 0
			for id in game.life.citizens:
				var a = game.life.citizens[id]
				if not is_instance_valid(a): continue
				var p: Vector3 = a.position
				if a.is_moving(): moving += 1
				if last.has(id) and dist(last[id], p) < 0.05 and game.life.motion_targets.has(id) and not a.is_moving():
					var tgt: Dictionary = game.life.sim.next_target(str(id))
					if not tgt.is_empty() and str(tgt.get("phase", "walking")) != "working" and dist(p, game.life._vec(tgt.position)) > 2.0:
						stuck[id] = int(stuck.get(id, 0)) + 1
				last[id] = p
			samples.append({"frame": k, "game_time": game.caravan.get_clock_text(), "citizens": game.life.citizens.size(), "moving": moving, "nav_calls": game.navigation.stats_calls if "stats_calls" in game.navigation else -1, "in_combat": game.in_combat, "zombies": game.settlement.zombies.size(), "hp": snappedf(game.brother.health, 0.1), "time_scale": Engine.time_scale})
	var blocked_total := 0
	for rid in game.life.sim.residents:
		blocked_total += game.life.sim.residents[rid].get("blocked", {}).size()
	var chronic := []
	for id in stuck: if stuck[id] >= 3: chronic.append({"id": id, "samples_stuck": stuck[id]})
	if not chronic.is_empty(): issue("nav", "%d citizens repeatedly idle far from their walking target (stuck)" % chronic.size(), chronic.slice(0, 10))
	Engine.time_scale = 1.0
	game.life.speed = old_speed
	return {"days_requested": long_days, "frames": frames_needed, "day_start": day0, "day_end": int(game.caravan.day_number), "samples": samples, "stuck": chronic, "resident_blocked_venues": blocked_total, "toast_count": toasts.size() - t0, "brother_needs": {"hunger": game.state.characters.brother.hunger, "thirst": game.state.characters.brother.thirst, "sleep": game.state.characters.brother.sleep, "health": game.brother.health}}
