extends Node3D
## Physical venues and furniture. LifeSim owns needs, careers, money and schedules.
## Records intentionally contain no Node references and are safe to serialize.

const CityWorld := preload("res://scripts/city_world.gd")
const ENV := "res://assets/environment/"
const ACTION_NAMES := {
	"visit":"Подойти", "wash":"Помыться", "toilet":"Справить нужду", "eat":"Поесть",
	"cook":"Приготовить еду", "rest":"Отдохнуть", "sleep":"Спать", "read":"Почитать",
	"play":"Развлечься", "train":"Потренироваться", "pray":"Тихо посидеть", "work":"Работать",
	"study":"Учиться", "shop":"Посмотреть товары", "social":"Пообщаться", "buy_home":"Купить дом",
}
const PROP_NAMES := {
	"bed":"Кровать", "bath":"Купальная бочка", "washbasin":"Умывальник", "latrine":"Отхожее место",
	"hearth":"Кухонный очаг", "dining":"Обеденный стол", "table":"Стол", "bench":"Скамья",
	"bookshelf":"Книжный шкаф", "training":"Тренировочное чучело", "pantry":"Кладовая",
	"loom":"Ткацкий станок", "kiln":"Обжиговая печь", "well":"Колодец", "game_table":"Игровой стол",
}

var _world: Node3D
var _built := false
var _venues: Dictionary = {}
var _workplaces: Dictionary = {}
var _records: Dictionary = {}
var _states: Dictionary = {}
var _nodes: Dictionary = {}
var _materials: Dictionary = {}
var _models: Dictionary = {}
var _roofs: Array[Node3D] = []
var _full_walls: Array[Node3D] = []
var _cutaway := true
var _roof_clock := 0.0
var _floor_materials: Dictionary = {}

func configure(world: Node3D) -> void:
	_world = world
	if is_node_ready():
		_build()

func _ready() -> void:
	if _world:
		_build()

func _process(delta: float) -> void:
	_roof_clock -= delta
	if _roof_clock <= 0.0 and _built:
		_roof_clock = .25
		_update_roofs()

func _build() -> void:
	if _built or not is_instance_valid(_world):
		return
	_built = true
	_build_streets()
	for spec: Dictionary in CityWorld.venue_specs():
		_build_venue(spec)
	_build_fortifications()
	_plant_city_trees()
	_connect_outposts()
	_refresh_approaches()
	set_cutaway(_cutaway)
	print("City ready: ", _venues.size(), " venues; ", _workplaces.size(), " distinct professional workstations; ", _records.size(), " clickable objects.")

func get_venues() -> Dictionary:
	return _venues.duplicate(true)

func get_workplaces() -> Dictionary:
	return _workplaces.duplicate(true)

func get_objects() -> Dictionary:
	return _records.duplicate(true)

func get_object(id: String) -> Dictionary:
	return _records.get(id, {}).duplicate(true)

func owns(id: String) -> bool:
	return _records.has(id)

func actions(id: String, person: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _records.has(id):
		return result
	var record: Dictionary = _records[id]
	var verbs: Array = record.get("verbs", ["visit"])
	var reservation := str(_states.get(id, {}).get("reserved_by", ""))
	var actor_id := str(person.get("id", person.get("actor_id", "")))
	for verb: String in verbs:
		var reason := ""
		if not reservation.is_empty() and reservation != actor_id and verb != "visit":
			reason = "Это место сейчас занято."
		var target_id := id
		if record.get("kind", "") == "venue" and verb != "visit":
			target_id = _find_prop(str(record.venue_id), verb)
			if target_id.is_empty():
				target_id = id
		result.append({"id":"life:" + verb,"label":str(ACTION_NAMES.get(verb, verb)),"enabled":reason.is_empty(),"reason":reason,"target_id":target_id,"venue_id":str(record.get("venue_id",id)),"profession":str(record.get("profession",""))})
	return result

func _find_prop(venue_id: String, verb: String) -> String:
	for id: String in _records:
		var r: Dictionary = _records[id]
		if str(r.get("venue_id", "")) == venue_id and str(r.get("kind", "")) != "venue" and verb in r.get("verbs", []):
			return id
	return ""

func reserve(id: String, actor_id: String) -> bool:
	if not _states.has(id) or actor_id.is_empty():
		return false
	var owner := str(_states[id].get("reserved_by", ""))
	if not owner.is_empty() and owner != actor_id:
		return false
	_states[id]["reserved_by"] = actor_id
	return true

func release(id: String, actor_id: String = "") -> void:
	if _states.has(id) and (actor_id.is_empty() or str(_states[id].reserved_by) == actor_id):
		_states[id]["reserved_by"] = ""

func get_object_state(id: String) -> Dictionary:
	return _states.get(id, {}).duplicate(true)

func set_object_state(id: String, patch: Dictionary) -> void:
	if not _states.has(id):
		return
	for key: String in ["reserved_by", "owner", "condition", "cleanliness", "fuel", "water"]:
		if patch.has(key):
			if key in ["reserved_by","owner"] and patch[key] is String:
				_states[id][key] = str(patch[key]).left(128)
			elif key not in ["reserved_by","owner"] and (patch[key] is int or patch[key] is float) and is_finite(float(patch[key])):
				_states[id][key] = clampf(float(patch[key]),0,100)

func snapshot() -> Dictionary:
	return {"version":1,"objects":_states.duplicate(true),"cutaway":_cutaway}

func restore(state: Dictionary) -> void:
	if not valid_snapshot(state):
		return
	for id: String in _states:
		_states[id] = _default_state()
	var values: Variant = state.get("objects", {})
	if values is Dictionary:
		for id: String in values:
			if values[id] is Dictionary:
				set_object_state(id, values[id])
	set_cutaway(bool(state.get("cutaway", true)))

func valid_snapshot(state: Variant) -> bool:
	if not state is Dictionary or not state.get("objects",{}) is Dictionary or not state.get("cutaway",true) is bool:
		return false
	for id: Variant in state.get("objects",{}):
		if not id is String or not state.objects[id] is Dictionary:
			return false
		var record: Dictionary = state.objects[id]
		for key: String in ["reserved_by","owner"]:
			if record.has(key) and (not record[key] is String or str(record[key]).length()>128):
				return false
		for key: String in ["condition","cleanliness","fuel","water"]:
			if record.has(key) and (not (record[key] is int or record[key] is float) or not is_finite(float(record[key])) or float(record[key])<0 or float(record[key])>100):
				return false
	return true

func _default_state() -> Dictionary:
	return {"reserved_by":"","owner":"","condition":100.0,"cleanliness":100.0,"fuel":100.0,"water":100.0}

func set_cutaway(enabled: bool) -> void:
	_cutaway = enabled
	_update_roofs()

func _update_roofs() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var focus := Vector3.ZERO
	var close_view := false
	if camera and _world:
		var ray := -camera.global_basis.z
		focus = camera.global_position
		if ray.y < -.05:
			for i in range(4):
				var ground := float(_world.sample_height(focus.x,focus.z))
				focus = camera.global_position + ray*((ground-camera.global_position.y)/ray.y)
			close_view = camera.global_position.y-focus.y < 105.0
	for i in _roofs.size():
		var roof: Node3D = _roofs[i]
		var center: Vector3 = roof.get_meta("center",roof.global_position)
		var nearby := camera == null or (close_view and Vector2(center.x,center.z).distance_to(Vector2(focus.x,focus.z)) < 42.0)
		var show := not (_cutaway and nearby)
		roof.visible = show
		if i < _full_walls.size():
			_full_walls[i].visible = show

func _build_venue(spec: Dictionary) -> void:
	var id := str(spec.id)
	var kind := str(spec.kind)
	var p: Vector2 = spec.p
	var size: Vector2 = spec.size
	var node := Node3D.new()
	node.name = id
	add_child(node)
	node.position = _ground(p)
	var professions: Array[String] = []
	for profession: String in CityWorld.PROFESSION_VENUES:
		if CityWorld.PROFESSION_VENUES[profession] == id:
			professions.append(profession)
	var is_open := kind in ["square","market","farm","graveyard","mine","quarry","logging_camp","fishery","plot"]
	var floor_color := Color("#9b8a6f") if is_open else Color("#a58a60")
	if kind in ["temple","academy","clinic","bathhouse"]:
		floor_color = Color("#a0a49a")
	if kind!="plot": _ground_patch(p, size, floor_color, 0.06, id + "_floor")
	else:
		for side in [-1.0,1.0]:
			_ground_patch(p+Vector2(side*size.x*.5,0),Vector2(.4,size.y),Color("#d1b876"),.06,id+"_border_x"+str(side))
			_ground_patch(p+Vector2(0,side*size.y*.5),Vector2(size.x,.4),Color("#d1b876"),.06,id+"_border_z"+str(side))
	if not is_open:
		_build_shell(node, p, size, kind, id)
	var venue_position := _ground(p + Vector2(0, size.y * 0.15))
	var entry := _ground(p + Vector2(0, size.y * 0.5 + 3))
	var venue: Dictionary = {"id":id,"kind":kind,"name":str(spec.name),"position":_array(venue_position),"approach":_array(entry),"capacity":int(spec.capacity),"safe":bool(spec.safe),"district":str(spec.district),"professions":professions,"workstations":[],"size":[size.x,size.y],"center":_array(_ground(p))}
	for key: String in ["price", "buyable", "lot"]:
		if spec.has(key):
			venue[key] = spec[key]
	_venues[id] = venue
	var sign_p := p + Vector2(-size.x * 0.42, size.y * 0.5 + 1.3)
	var sign := Node3D.new()
	sign.name = "VenueSign"
	add_child(sign)
	sign.position = _ground(sign_p)
	_box(sign, Vector3(0,1.1,0),Vector3(0.13,2.2,0.13),"timber")
	_box(sign, Vector3(0,1.85,0),Vector3(2.5,0.68,0.13),"dark_wood")
	_label(sign,str(spec.name),Vector3(0,2.6,0),160.0,0.022)
	_register(id,sign,"venue",kind,id,entry,["visit"],0.6,false)
	_records[id]["name"] = str(spec.name)
	_world.objects[id]["name"] = str(spec.name)
	_world.objects[id]["description"] = str(spec.name) + " · " + str(spec.district) + ". Вход открыт, помещения находятся в том же мире."
	if kind=="plot":
		_world.objects[id]["description"]="Межевые линии обозначают землю под застройку. Сначала получите статус и разрешение в ратуше, затем купите этот участок. Постройки нужно возвести самостоятельно."
		return
	var work_ids: Array[String] = []
	for i in professions.size():
		var profession: String = professions[i]
		var col := i % 4
		var row := floori(float(i) / 4.0)
		var count_in_row := mini(4, professions.size()-row*4)
		var x := (float(col) - float(count_in_row - 1) * 0.5) * 7.8
		var z := -size.y * 0.30 + row * 8.0
		var work_p := p + Vector2(x,z)
		var work_id := "life_job_" + profession
		var prop := str(CityWorld.PROFESSION_PROPS[profession])
		var object := _place_prop(work_id,prop,id,work_p,["work"],profession)
		object["name"] = str(CityWorld.PROFESSION_NAMES[profession]) + " · рабочее место"
		_records[work_id]["name"] = object.name
		_world.objects[work_id]["name"] = object.name
		_workplaces[profession] = {"id":work_id,"venue_id":id,"profession":profession,"prop":prop,"position":object.position,"approach":object.approach}
		work_ids.append(work_id)
	_venues[id]["workstations"] = work_ids
	_furnish_venue(spec)
	var verbs: Array[String] = ["visit"]
	var action_targets: Dictionary = {}
	for object_id: String in _records:
		var r: Dictionary = _records[object_id]
		if str(r.get("venue_id","")) == id and str(r.get("kind","")) != "venue":
			for verb: String in r.get("verbs",[]):
				if verb not in verbs:
					verbs.append(verb)
				if not action_targets.has(verb):
					action_targets[verb] = []
				action_targets[verb].append(object_id)
	_venues[id]["action_targets"] = action_targets
	var need_targets: Dictionary = {}
	var need_verbs := {"energy":"sleep","hunger":"eat","hygiene":"wash","bladder":"toilet","social":"social","fun":"read","comfort":"rest"}
	for need: String in need_verbs:
		need_targets[need] = action_targets.get(need_verbs[need],[]).duplicate()
	if need_targets.fun.is_empty():
		need_targets.fun = action_targets.get("play",[]).duplicate()
	_venues[id]["need_targets"] = need_targets
	_records[id]["verbs"] = verbs
	if bool(spec.get("buyable", false)):
		_records[id]["verbs"].append("buy_home")
	_lantern(p + Vector2(size.x * 0.45,size.y*0.5), id)

func _furnish_venue(spec: Dictionary) -> void:
	var id := str(spec.id)
	var kind := str(spec.kind)
	var p: Vector2 = spec.p
	var size: Vector2 = spec.size
	match kind:
		"home":
			_furniture(id,"bed_a","bed",p+Vector2(-size.x*.31,-size.y*.25),["sleep","rest"])
			_furniture(id,"bed_b","bed",p+Vector2(size.x*.31,-size.y*.25),["sleep","rest"])
			_furniture(id,"bed_c","bed",p+Vector2(-3,-size.y*.25),["sleep","rest"])
			_furniture(id,"bed_d","bed",p+Vector2(3,-size.y*.25),["sleep","rest"])
			_furniture(id,"hearth","hearth",p+Vector2(-size.x*.32,size.y*.19),["cook"])
			_furniture(id,"dining","dining",p+Vector2(size.x*.3,size.y*.18),["eat","social"])
			_furniture(id,"wash","washbasin",p+Vector2(-size.x*.5-3,size.y*.23),["wash"])
			_furniture(id,"books","bookshelf",p+Vector2(-10,size.y*.36),["read"])
			_furniture(id,"latrine","latrine",p+Vector2(size.x*.5+3,size.y*.23),["toilet"])
			_furniture(id,"pantry","pantry",p+Vector2(size.x*.5+3,-4),["eat"])
			_turn_prop(id+"_pantry",PI*.5)
		"bathhouse":
			for i in range(4):
				_furniture(id,"bath_%d"%i,"bath",p+Vector2((i%2*2-1)*9,-7+floori(i/2.0)*12),["wash","rest"])
			_furniture(id,"latrine","latrine",p+Vector2(size.x*.5+3,0),["toilet"])
			_furniture(id,"wash","washbasin",p+Vector2(0,-size.y*.32),["wash"])
		"tavern":
			_furniture(id,"dining","dining",p+Vector2(-10,5),["eat","social"])
			_furniture(id,"games","game_table",p+Vector2(10,5),["play","social"])
			_furniture(id,"bed","bed",p+Vector2(size.x*.36,-6),["sleep","rest"])
			_furniture(id,"latrine","latrine",p+Vector2(size.x*.5+3,3),["toilet"])
		"market":
			for i in range(4):
				_furniture(id,"stall_%d"%i,"stall",p+Vector2((i%2*2-1)*11,-7+floori(i/2.0)*13),["shop"])
		"square":
			_furniture(id,"well","well",p+Vector2(-size.x*.3,0),["wash"])
			_furniture(id,"bench","bench",p+Vector2(size.x*.33,4),["rest","social"])
			_furniture(id,"games","game_table",p+Vector2(size.x*.3,-8),["play"])
		"kitchen","bakery":
			_furniture(id,"meal","dining",p+Vector2(8,5),["eat"])
			_furniture(id,"hearth","hearth",p+Vector2(-9,4),["cook"])
			_furniture(id,"pantry","pantry",p+Vector2(-size.x*.36,-5),["eat"])
		"school","library","academy","scriptorium":
			_furniture(id,"study","writing_desk",p+Vector2(-11,6),["study","read"])
			_furniture(id,"books","bookshelf",p+Vector2(11,5),["read","study"])
		"temple":
			_furniture(id,"bench","bench",p+Vector2(-9,5),["pray","rest"])
			_furniture(id,"books","bookshelf",p+Vector2(9,5),["read"])
		"watch","travel_guild","guild":
			_furniture(id,"training","training",p+Vector2(10,6),["train"])
			_furniture(id,"bench","bench",p+Vector2(-10,6),["rest"])
		"clinic":
			_furniture(id,"bed_a","bed",p+Vector2(-10,5),["sleep","rest"])
			_furniture(id,"bed_b","bed",p+Vector2(10,5),["sleep","rest"])
			_furniture(id,"wash","washbasin",p+Vector2(size.x*.5+2,2),["wash"])
		"stable":
			_furniture(id,"trough","trough",p+Vector2(10,-8),["work"])
			_furniture(id,"hay","cargo",p+Vector2(-10,5),["work"])
			_stable_horse(p+Vector2(-9,-7),0.35)
			_stable_horse(p+Vector2(8,5),-0.6)
		"farm":
			for i in range(4):
				_furniture(id,"crop_%d"%i,"crop",p+Vector2(-18+i*11,10),["work"])
			_furniture(id,"well","well",p+Vector2(25,0),["wash"])
		"graveyard":
			for i in range(12):
				var at := p+Vector2((i%4-1.5)*8,(floori(i/4.0)-1)*8)
				var grave := Node3D.new()
				add_child(grave)
				grave.position = _ground(at)
				_box(grave,Vector3(0,.07,.6),Vector3(1.5,.14,2.8),"stone")
				_box(grave,Vector3(0,.8,-.7),Vector3(1.1,1.6,.26),"stone_light")
			_furniture(id,"bench","bench",p+Vector2(0,size.y*.5+2),["pray","rest"])
		"pottery":
			_furniture(id,"kiln","kiln",p+Vector2(9,4),["work"])
		"forge":
			_furniture(id,"furnace","smelter",p+Vector2(10,4),["work"])
		"theatre":
			_furniture(id,"audience","bench",p+Vector2(-12,7),["play","rest"])
			_furniture(id,"games","game_table",p+Vector2(12,7),["play"])
		"mill":
			_build_windmill(p+Vector2(size.x*.45,-size.y*.25))
		_:
			_furniture(id,"bench","bench",p+Vector2(size.x*.33,size.y*.22),["rest"])

func _furniture(venue_id: String, suffix: String, kind: String, p: Vector2, verbs: Array) -> void:
	_place_prop(venue_id+"_"+suffix,kind,venue_id,p,verbs)

func _turn_prop(id: String, angle: float) -> void:
	var node: Node3D = _nodes[id]
	node.rotation.y = angle
	var radius := float(_world.objects[id].surface_radius)
	var p := Vector2(node.global_position.x,node.global_position.z)+Vector2(sin(angle),cos(angle))*(radius+1.8)
	var approach := _ground(p)
	_world.objects[id]["approach"] = approach
	_records[id]["approach"] = _array(approach)

func _place_prop(id: String, kind: String, venue_id: String, p: Vector2, verbs: Array, profession: String = "") -> Dictionary:
	var node := create_prop(kind, self)
	node.name = id
	node.position = _ground(p)
	var radius := 1.1
	if kind in ["dining","table","game_table","map_table","bed","bath","cargo","stall"]:
		radius = 1.5
	if kind in ["crop","dance_floor"]:
		radius = 0.0
	var approach := _ground(p+Vector2(0,radius+1.8))
	_register(id,node,"workplace" if not profession.is_empty() else "furniture",kind,venue_id,approach,verbs,radius,radius>0)
	_records[id]["profession"] = profession
	return _records[id]

func _register(id: String, node: Node3D, category: String, prop: String, venue_id: String, approach: Vector3, verbs: Array, radius: float, obstacle: bool) -> void:
	_nodes[id] = node
	var record := {"id":id,"kind":category,"prop":prop,"venue_id":venue_id,"position":_array(node.global_position),"approach":_array(approach),"verbs":verbs.duplicate(),"name":str(PROP_NAMES.get(prop, prop))}
	_records[id] = record
	_states[id] = _default_state()
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("object_id",id)
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = maxf(radius,0.9)
	shape.height = 2.5 if category == "venue" else 1.8
	collision.shape = shape
	collision.position.y = shape.height*.5
	body.add_child(collision)
	node.add_child(body)
	_world.objects[id] = {"id":id,"type":"life_"+category,"name":record.name,"description":"Доступно: "+", ".join(verbs),"position":node.global_position,"approach":approach,"surface_radius":maxf(radius,.7),"node":node,"city_id":id,"venue_id":venue_id,"prop":prop}
	if obstacle:
		_world.obstacles.append({"position":node.global_position,"radius":radius,"city_id":id})

func _ground(p: Vector2, offset: float = 0.0) -> Vector3:
	return Vector3(p.x,float(_world.sample_height(p.x,p.y))+offset,p.y)

func _array(p: Vector3) -> Array:
	return [p.x,p.y,p.z]

func _refresh_approaches() -> void:
	for id: String in _records:
		var record: Dictionary = _records[id]
		if str(record.kind) == "venue":
			continue
		var at: Vector3 = _world.objects[id].position
		var preferred: Vector3 = _world.objects[id].approach
		var best := preferred
		var found := _clear_standing(Vector2(preferred.x,preferred.z))
		if not found:
			for ring in range(1,5):
				for i in range(16):
					var p := Vector2(at.x,at.z)+Vector2(sin(float(i)*TAU/16),cos(float(i)*TAU/16))*(2.3+ring*.8)
					if _clear_standing(p):
						best = _ground(p)
						found = true
						break
				if found:
					break
		_world.objects[id]["approach"] = best
		_records[id]["approach"] = _array(best)
		var profession := str(record.get("profession",""))
		if _workplaces.has(profession):
			_workplaces[profession]["approach"] = _array(best)

func _clear_standing(p: Vector2) -> bool:
	if float(_world.sample_height(p.x,p.y)) < 0.5:
		return false
	var gradient := Vector2(float(_world.sample_height(p.x+3,p.y))-float(_world.sample_height(p.x-3,p.y)),float(_world.sample_height(p.x,p.y+3))-float(_world.sample_height(p.x,p.y-3)))/6.0
	if gradient.length() > 0.80:
		return false
	for o: Dictionary in _world.obstacles:
		var at: Vector3 = o.position
		if Vector2(at.x,at.z).distance_squared_to(p) < pow(float(o.radius)+.85,2):
			return false
	return true

func _build_shell(parent: Node3D, p: Vector2, size: Vector2, kind: String, id: String) -> void:
	var half := size*.5
	var stone_building := kind in ["temple","academy","town_hall","watch","library","bathhouse","clinic"]
	var plaster := "plaster_cool" if stone_building else "plaster"
	var height := 4.8 if stone_building else 3.7
	# Rear wall is full-height. Low side walls give a readable cutaway at any azimuth.
	_wall_line(parent,p,Vector2(-half.x,-half.y),Vector2(half.x,-half.y),height,plaster,id)
	_wall_line(parent,p,Vector2(-half.x,-half.y),Vector2(-half.x,half.y),1.05,plaster,id)
	_wall_line(parent,p,Vector2(half.x,-half.y),Vector2(half.x,half.y),1.05,plaster,id)
	_wall_line(parent,p,Vector2(-half.x,half.y),Vector2(-6.5,half.y),1.05,plaster,id)
	_wall_line(parent,p,Vector2(6.5,half.y),Vector2(half.x,half.y),1.05,plaster,id)
	var upper := Node3D.new()
	parent.add_child(upper)
	_full_walls.append(upper)
	var roof := Node3D.new()
	parent.add_child(roof)
	roof.set_meta("center",parent.position)
	_roofs.append(roof)
	var max_ground := 0.0
	for corner: Vector2 in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),Vector2(-half.x,half.y),Vector2(half.x,half.y)]:
		max_ground = maxf(max_ground,float(_world.sample_height(p.x+corner.x,p.y+corner.y))-parent.position.y)
	var eave := height+max_ground
	_roof_mesh(roof,size+Vector2(1.3,1.3),eave,size.x*.29,"slate" if stone_building else "tile")
	_upper_wall_surface(upper,p,Vector2(-half.x,-half.y),Vector2(-half.x,half.y),1.0,eave,plaster)
	_upper_wall_surface(upper,p,Vector2(half.x,-half.y),Vector2(half.x,half.y),1.0,eave,plaster)
	_upper_wall_surface(upper,p,Vector2(-half.x,-half.y),Vector2(half.x,-half.y),height-.05,eave,plaster)
	_upper_wall_surface(upper,p,Vector2(-half.x,half.y),Vector2(-6.5,half.y),1.0,eave,plaster)
	_upper_wall_surface(upper,p,Vector2(6.5,half.y),Vector2(half.x,half.y),1.0,eave,plaster)
	_upper_wall_surface(upper,p,Vector2(-6.5,half.y),Vector2(6.5,half.y),2.8,eave,plaster)
	# Exposed timber ties give the rendered exteriors a medieval timber-frame profile.
	for x: float in [-half.x,-6.5,6.5,half.x]:
		var local_y := float(_world.sample_height(p.x+x,p.y+half.y))-parent.position.y
		_box(upper,Vector3(x,(eave+local_y)*.5,half.y+.10),Vector3(.22,eave-local_y,.22),"dark_wood")
	_box(upper,Vector3(0,eave-.1,half.y+.10),Vector3(size.x,.2,.22),"dark_wood")
	# Roof edge remains visible in cutaway mode and makes buildings distinct from fenced lots.
	for side: float in [-1,1]:
		var x := side*half.x
		for z: float in [-half.y,half.y]:
			var local := _ground(p+Vector2(x,z))-parent.position
			_box(parent,local+Vector3(0,height*.5,0),Vector3(.28,height,.28),"dark_wood")
	if stone_building:
		for x: float in [-half.x+2.0,half.x-2.0]:
			var y := float(_world.sample_height(p.x+x,p.y-half.y))-parent.position.y
			_box(parent,Vector3(x,y+height*.63,-half.y+.22),Vector3(1.4,2,.10),"window_blue")
	else:
		for x: float in [-half.x+3,0,half.x-3]:
			var y := float(_world.sample_height(p.x+x,p.y-half.y))-parent.position.y
			_box(parent,Vector3(x,y+height*.6,-half.y+.25),Vector3(1.5,1.5,.12),"window_blue")
	var chimney_at := _ground(p+Vector2(-half.x+2,-half.y+2))-parent.position
	_box(parent,chimney_at+Vector3(0,height*.6,0),Vector3(1.1,height*1.2,1.1),"stone")
	for mesh: MeshInstance3D in parent.find_children("*","MeshInstance3D",true,false):
		mesh.visibility_range_end = 1000.0

func _upper_wall_surface(parent: Node3D, origin: Vector2, a: Vector2, b: Vector2, low: float, high: float, material: String) -> void:
	var count := maxi(1,ceili(a.distance_to(b)/3.0))
	var ground_y := float(_world.sample_height(origin.x,origin.y))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in count:
		var p := a.lerp(b,float(i)/count)
		var q := a.lerp(b,float(i+1)/count)
		var lo_p := minf(high,_ground(origin+p).y-ground_y+low)
		var lo_q := minf(high,_ground(origin+q).y-ground_y+low)
		var a3 := Vector3(p.x,lo_p,p.y)
		var b3 := Vector3(q.x,lo_q,q.y)
		var c3 := Vector3(p.x,high,p.y)
		var d3 := Vector3(q.x,high,q.y)
		for vertex: Vector3 in [a3,b3,c3,b3,d3,c3]:
			st.add_vertex(vertex)
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var mat := _mat(material).duplicate() as StandardMaterial3D
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	parent.add_child(mesh)

func _wall_line(parent: Node3D, origin: Vector2, a: Vector2, b: Vector2, height: float, material: String, owner_id: String) -> void:
	var length := a.distance_to(b)
	if length < .1:
		return
	var count := maxi(1,ceili(length/2.8))
	var direction := (b-a).normalized()
	for i in count:
		var local := a.lerp(b,(i+.5)/count)
		var at := _ground(origin+local)
		var piece := _box(parent,at-parent.position+Vector3(0,height*.5,0),Vector3(length/count+.04,height,.35),material)
		piece.rotation.y = -atan2(direction.y,direction.x)
		if height > 3.0:
			var cap := _box(parent,at-parent.position+Vector3(0,height-.04,0),Vector3(length/count+.06,.18,.46),"dark_wood")
			cap.rotation.y = piece.rotation.y
		_box(parent,at-parent.position+Vector3(0,.25,0),Vector3(.55,.5,.55),"stone")
		_world.obstacles.append({"position":at,"radius":.48,"city_id":owner_id})

func _build_streets() -> void:
	for x: float in [3235,3288,3375,3465,3555,3645,3725,3785]:
		_ground_patch(Vector2(x,3680),Vector2(8,560),Color("#aaa18c"),.045,"NorthSouthStreet")
	for z: float in [3403,3453,3520,3590,3660,3740,3825,3910,3950]:
		_ground_patch(Vector2(3510,z),Vector2(558,8),Color("#aaa18c"),.047,"EastWestStreet")
	_ground_patch(Vector2(3510,3680),Vector2(10,580),Color("#b4aa94"),.055,"MainStreet")
	_ground_patch(CityWorld.SECOND_CENTER,Vector2(116,9),Color("#ab9776"),.05,"SouthMarketRoad")
	_ground_patch(CityWorld.SECOND_CENTER,Vector2(9,140),Color("#ab9776"),.05,"SouthVillageRoad")

func _connect_outposts() -> void:
	# These visible links join existing routes; terrain/navigation still validate every step.
	_ribbon([Vector2(3510,3970),Vector2(3510,4070),Vector2(3595,4200)],6.0)
	_ribbon([Vector2(3510,3970),Vector2(3630,3990),Vector2(3710,4045)],5.5)
	_ribbon([Vector2(3360,4515),Vector2(3360,4430),Vector2(3312,4333)],5.5)
	_ribbon([Vector2(3220,3680),Vector2(3130,3680),Vector2(3050,3630)],5.0)
	_ribbon([Vector2(3050,3630),Vector2(2970,3670),Vector2(2890,3670)],4.0)
	_ribbon([Vector2(4562,3740),Vector2(4585,3740),Vector2(4585,3700)],4.0)
	_ribbon([Vector2(4510,3820),Vector2(4490,3850),Vector2(4460,3880)],4.0)

func _build_fortifications() -> void:
	var rect: Rect2 = CityWorld.CITY_RECT
	for side in range(4):
		var a: Vector2
		var b: Vector2
		match side:
			0: a=rect.position; b=Vector2(rect.end.x,rect.position.y)
			1: a=Vector2(rect.end.x,rect.position.y); b=rect.end
			2: a=rect.end; b=Vector2(rect.position.x,rect.end.y)
			_: a=Vector2(rect.position.x,rect.end.y); b=rect.position
		var length := a.distance_to(b)
		var count := ceili(length/5.0)
		for i in count:
			var p := a.lerp(b,(i+.5)/count)
			var middle := a.lerp(b,.5)
			if p.distance_to(middle) < 13:
				continue
			var node := Node3D.new()
			add_child(node)
			node.position = _ground(p)
			var horizontal := side%2 == 0
			_box(node,Vector3(0,1.65,0),Vector3(5.05,3.3,1.1) if horizontal else Vector3(1.1,3.3,5.05),"stone")
			for k in range(3):
				_box(node,Vector3((k-1)*1.8 if horizontal else 0,3.65,0 if horizontal else (k-1)*1.8),Vector3(1.0,.7,1.2) if horizontal else Vector3(1.2,.7,1.0),"stone_light")
			_world.obstacles.append({"position":node.position,"radius":1.3,"city_id":"city_wall"})
		var gate_center := a.lerp(b,.5)
		for sign: float in [-1,1]:
			var tower_p := gate_center + (b-a).normalized()*sign*15
			_build_tower(tower_p)
		var gate := Node3D.new()
		add_child(gate)
		gate.position = _ground(gate_center)
		_label(gate,"Арденхольм" if side!=2 else "Южные ворота · Арденхольм",Vector3(0,7,0),220,.027)
		_lantern(gate_center+Vector2(9,4),"gate")
	for corner: Vector2 in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
		_build_tower(corner)

func _build_tower(p: Vector2) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = _ground(p)
	_cylinder(node,Vector3(0,3.7,0),3.0,7.4,"stone",3.2)
	_cylinder(node,Vector3(0,7.5,0),3.4,.5,"stone_light")
	for i in range(8):
		var a := i*TAU/8.0
		_box(node,Vector3(sin(a)*2.9,8,cos(a)*2.9),Vector3(.8,.9,.8),"stone_light")
	_world.obstacles.append({"position":node.position,"radius":3.2,"city_id":"city_tower"})

func _plant_city_trees() -> void:
	var index := 0
	for x: float in [3288,3375,3465,3555,3645,3725]:
		for z: float in [3520,3590,3740,3825,3910]:
			var p := Vector2(x+8,z+8)
			var occupied := false
			for spec: Dictionary in CityWorld.venue_specs():
				var lot := Rect2(spec.p-spec.size*.5,spec.size).grow(4)
				if lot.has_point(p):
					occupied = true
					break
			if occupied:
				continue
			var base := Node3D.new()
			add_child(base)
			base.position = _ground(p)
			_model("nature-kit/tree_oak" if index%3 else "nature-kit/tree_detailed",base,Vector3.ZERO,Vector3.ONE*4.5,index*.71)
			_world.obstacles.append({"position":base.position,"radius":.55,"city_id":"city_tree"})
			index += 1

func _build_windmill(p: Vector2) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = _ground(p)
	_cylinder(node,Vector3(0,4.0,0),2.8,8,"plaster",2.0)
	_cylinder(node,Vector3(0,9,0),3.3,2.0,"tile",0.0)
	for angle: float in [0,PI*.5,PI,PI*1.5]:
		var sail := Node3D.new()
		node.add_child(sail)
		sail.position = Vector3(0,6.5,2.7)
		sail.rotation.z = angle+PI*.25
		_box(sail,Vector3(0,3.3,0),Vector3(.18,6.6,.2),"timber")
		_box(sail,Vector3(.7,3.9,0),Vector3(1.4,4.2,.12),"canvas")
	_world.obstacles.append({"position":node.position,"radius":3.0,"city_id":"life_mill"})

func _stable_horse(p: Vector2, angle: float) -> void:
	var packed := load("res://assets/animals/horse.glb") as PackedScene
	if not packed:
		return
	var horse := packed.instantiate() as Node3D
	add_child(horse)
	horse.position = _ground(p,.01)
	horse.rotation.y = angle
	horse.scale = Vector3.ONE*.4
	for animation: AnimationPlayer in horse.find_children("*","AnimationPlayer",true,false):
		for clip: StringName in animation.get_animation_list():
			if str(clip).get_slice("/",str(clip).get_slice_count("/")-1) in ["Idle","Eating"]:
				animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				animation.play(clip)
				break
	_world.obstacles.append({"position":horse.position,"radius":1.0,"city_id":"life_stable"})

func _lantern(p: Vector2, owner_id: String) -> void:
	var node := Node3D.new()
	node.name = "Lantern_"+owner_id
	add_child(node)
	node.position = _ground(p)
	_box(node,Vector3(0,1.7,0),Vector3(.16,3.4,.16),"dark_wood")
	_box(node,Vector3(.35,3.25,0),Vector3(.85,.14,.14),"dark_wood")
	_box(node,Vector3(.65,2.9,0),Vector3(.35,.55,.35),"lantern")
	var light := OmniLight3D.new()
	node.add_child(light)
	light.position = Vector3(.65,2.9,0)
	light.light_color = Color("#ffd18b")
	light.light_energy = 1.5
	light.omni_range = 14.0
	light.distance_fade_enabled = true
	light.distance_fade_begin = 90.0
	light.distance_fade_length = 30.0
	light.add_to_group("night_lights")
	light.visible = false

func _ground_patch(center: Vector2, size: Vector2, color: Color, offset: float, label: String) -> void:
	# Clip the original terrain triangles instead of resampling bilinearly: a finer
	# independent grid can still cross the terrain and produce visible stripes.
	var step := 16000.0/3072.0
	var terrain_origin := Vector2(2000,3166.666666666667)
	var rect := Rect2(center-size*.5,size)
	var first := Vector2i(((rect.position-terrain_origin)/step).floor())
	var last := Vector2i(((rect.end-terrain_origin)/step).floor())
	var origin := _ground(center)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var a := terrain_origin+Vector2(x,z)*step
			var b := a+Vector2(step,0)
			var c := a+Vector2(0,step)
			var d := a+Vector2(step,step)
			for triangle: Array in [[a,b,c],[b,d,c]]:
				var polygon: Array[Vector2] = []
				polygon.assign(triangle)
				polygon = _clip_polygon(polygon,0,rect.position.x,true)
				polygon = _clip_polygon(polygon,0,rect.end.x,false)
				polygon = _clip_polygon(polygon,1,rect.position.y,true)
				polygon = _clip_polygon(polygon,1,rect.end.y,false)
				for i in range(1,polygon.size()-1):
					for p: Vector2 in [polygon[0],polygon[i],polygon[i+1]]:
						surface.set_color(color)
						surface.set_uv(p)
						surface.add_vertex(Vector3(p.x,_surface_height(p)+offset,p.y)-origin)
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = surface.commit()
	instance.position = origin
	instance.material_override = _floor_material(label.ends_with("_floor") and color == Color("#a58a60"))
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _clip_polygon(input: Array[Vector2], axis: int, bound: float, greater: bool) -> Array[Vector2]:
	var output: Array[Vector2] = []
	if input.is_empty():
		return output
	var previous: Vector2 = input[-1]
	var pv := previous.x if axis==0 else previous.y
	var previous_inside := pv >= bound if greater else pv <= bound
	for current: Vector2 in input:
		var cv := current.x if axis==0 else current.y
		var current_inside := cv >= bound if greater else cv <= bound
		if current_inside != previous_inside:
			var t := (bound-pv)/(cv-pv)
			output.append(previous.lerp(current,t))
		if current_inside:
			output.append(current)
		previous = current
		pv = cv
		previous_inside = current_inside
	return output

func _surface_height(p: Vector2) -> float:
	var step := 16000.0/3072.0
	var local := (p-Vector2(2000,3166.666666666667))/step
	var x := clampi(floori(local.x),0,607)
	var z := clampi(floori(local.y),0,383)
	var tx := clampf(local.x-x,0,1)
	var tz := clampf(local.y-z,0,1)
	var heights: PackedFloat32Array = _world.heights
	var a := heights[z*609+x]
	var b := heights[z*609+x+1]
	var c := heights[(z+1)*609+x]
	var d := heights[(z+1)*609+x+1]
	if tx+tz <= 1.0:
		return a+(b-a)*tx+(c-a)*tz
	return d+(b-d)*(1-tz)+(c-d)*(1-tx)

func _floor_material(wooden: bool) -> ShaderMaterial:
	var key := "wood" if wooden else "stone"
	if _floor_materials.has(key):
		return _floor_materials[key]
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_back;
uniform bool wooden = false;
void fragment() {
    vec2 grid = UV * (wooden ? vec2(0.42, 2.2) : vec2(1.25, 1.8));
    grid.x += mod(floor(grid.y),2.0)*0.5;
    vec2 cell = floor(grid);
    vec2 f = fract(grid);
    float line = smoothstep(0.012,0.045,min(min(f.x,1.0-f.x),min(f.y,1.0-f.y)));
    float noise = fract(sin(dot(cell,vec2(12.9898,78.233)))*43758.5453);
    vec3 base = COLOR.rgb * (0.76 + noise*0.16);
    float detail = 1.0-smoothstep(0.10,0.65,max(fwidth(grid.x),fwidth(grid.y)));
    ALBEDO = mix(COLOR.rgb*0.82,mix(base*0.64,base,line),detail);
    ROUGHNESS = 0.96;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("wooden",wooden)
	_floor_materials[key] = material
	return material

func _ribbon(points: Array[Vector2], width: float) -> void:
	for i in range(points.size()-1):
		var a := points[i]
		var b := points[i+1]
		var count := maxi(1,ceili(a.distance_to(b)/3.0))
		var forward := (b-a).normalized()
		var right := Vector2(-forward.y,forward.x)*width*.5
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in count:
			var p := a.lerp(b,float(j)/count)
			var q := a.lerp(b,float(j+1)/count)
			for v: Vector2 in [p-right,q-right,p+right,q-right,q+right,p+right]:
				st.set_normal(Vector3.UP)
				st.add_vertex(_ground(v,.08))
		var instance := MeshInstance3D.new()
		instance.mesh = st.commit()
		instance.material_override = _mat("road")
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)

func _roof_mesh(parent: Node3D, size: Vector2, base: float, ridge: float, material: String) -> void:
	var x:=size.x*.5
	var z:=size.y*.5
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a:=Vector3(-x,base,-z)
	var b:=Vector3(x,base,-z)
	var c:=Vector3(-x,base,z)
	var d:=Vector3(x,base,z)
	var e:=Vector3(0,base+ridge,-z)
	var f:=Vector3(0,base+ridge,z)
	for vertex: Vector3 in [a,e,c,e,f,c,e,b,f,b,d,f,a,b,e,c,f,d]:
		st.add_vertex(vertex)
	st.generate_normals()
	var instance:=MeshInstance3D.new()
	instance.mesh=st.commit()
	instance.material_override=_mat(material)
	parent.add_child(instance)

func _label(parent: Node3D, title: String, at: Vector3, distance: float = 110.0, pixel: float = .014) -> void:
	var label := Label3D.new()
	label.text = title
	label.position = at
	label.font_size = 28
	label.pixel_size = pixel
	label.modulate = Color("#fff0cf")
	label.outline_modulate = Color("#26251e")
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.visibility_range_end = distance
	parent.add_child(label)

func _mat(key: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var palette := {"timber":"#805a37","dark_wood":"#503923","plaster":"#dbc69e","plaster_cool":"#c6c5ad","stone":"#7d8274","stone_light":"#afb19e","tile":"#976451","slate":"#617a78","window_blue":"#527b87","iron":"#5d696b","steel":"#a4b0b0","copper":"#b2814d","canvas":"#e1d1ad","cloth_blue":"#4e7189","cloth_red":"#9b554c","cloth_green":"#6f8953","water":"#5a9fa3","soil":"#715738","green":"#69894b","herb":"#789662","food":"#c6954f","clay":"#be8b63","paper":"#e5d9b5","ink":"#363b36","purple":"#7c668c","road":"#9c8c73","floor":"#ffffff","lantern":"#ffd88f","fire":"#e68d43"}
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(str(palette.get(key,"#b19b76")))
	mat.roughness = .88
	if key in ["iron","steel","copper"]:
		mat.metallic = .45
		mat.roughness = .42
	if key in ["lantern","fire"]:
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = .65
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED if key in ["canvas","paper"] else BaseMaterial3D.CULL_BACK
	_materials[key] = mat
	return mat

func _box(parent: Node3D, at: Vector3, size: Vector3, material: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = _mat(material)
	instance.visibility_range_end = 280.0 if size.y < 3 else 700.0
	parent.add_child(instance)
	return instance

func _cylinder(parent: Node3D, at: Vector3, radius: float, height: float, material: String, top: float = -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0 else top
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = _mat(material)
	instance.visibility_range_end = 280.0 if height < 4 else 700.0
	parent.add_child(instance)
	return instance

func _model(asset: String, parent: Node3D, at: Vector3, factor: Vector3, angle: float = 0.0) -> Node3D:
	if not _models.has(asset):
		var file := ENV+asset+".glb"
		if not ResourceLoader.exists(file):
			return null
		_models[asset] = load(file)
	var model := (_models[asset] as PackedScene).instantiate() as Node3D
	parent.add_child(model)
	model.position = at
	model.scale = factor
	model.rotation.y = angle
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		mesh.visibility_range_end = 180.0
	return model

func create_prop(kind: String, parent: Node3D) -> Node3D:
	var node := Node3D.new()
	node.name = kind.validate_node_name()
	parent.add_child(node)
	match kind:
		"bed","medical_table":
			_box(node,Vector3(0,.38,0),Vector3(1.45,.22,2.35),"dark_wood")
			_box(node,Vector3(0,.61,0),Vector3(1.3,.24,2.18),"canvas")
			_box(node,Vector3(0,.77,-.80),Vector3(.95,.15,.46),"canvas")
			_box(node,Vector3(0,.79,.35),Vector3(1.30,.14,1.37),"cloth_blue" if kind=="bed" else "cloth_green")
			for x: float in [-.62,.62]:
				for z: float in [-1.0,1.0]:
					_box(node,Vector3(x,.43,z),Vector3(.12,.85,.12),"timber")
			_box(node,Vector3(0,.85,-1.12),Vector3(1.48,1.1,.13),"timber")
		"bath","washbasin":
			var radius := 1.05 if kind=="bath" else .48
			var height := .85 if kind=="bath" else 1.0
			_cylinder(node,Vector3(0,height*.48,0),radius,height,"timber",radius*1.06)
			_cylinder(node,Vector3(0,height+.012,0),radius*.91,.035,"water")
			for y: float in [.18,height-.12]:
				_cylinder(node,Vector3(0,y,0),radius*1.075,.075,"iron")
			_box(node,Vector3(radius+.2,.3,0),Vector3(.4,.6,.5),"timber")
		"latrine":
			_box(node,Vector3(0,.38,0),Vector3(1.3,.76,1.3),"timber")
			_cylinder(node,Vector3(0,.77,0),.27,.025,"dark_wood")
			_box(node,Vector3(0,1.5,-.76),Vector3(1.7,3,.16),"timber")
			_box(node,Vector3(-.85,1.2,0),Vector3(.15,2.4,1.7),"timber")
			_box(node,Vector3(.85,1.2,0),Vector3(.15,2.4,1.7),"timber")
			_box(node,Vector3(0,2.65,0),Vector3(1.9,.15,2.0),"tile")
		"hearth","oven","kiln","smelter":
			_box(node,Vector3(0,.35,0),Vector3(2.0,.7,1.5),"stone")
			for x: float in [-.8,.8]:
				_box(node,Vector3(x,1,0),Vector3(.45,1.2,1.4),"stone_light")
			_box(node,Vector3(0,1.58,0),Vector3(2.1,.35,1.6),"stone")
			_box(node,Vector3(0,.95,.52),Vector3(1.1,.65,.12),"dark_wood")
			_box(node,Vector3(0,.80,.62),Vector3(.7,.32,.08),"fire")
			_box(node,Vector3(0,2.4,-.4),Vector3(.8,1.5,.8),"stone")
			if kind=="hearth":
				_cylinder(node,Vector3(0,1.93,0),.38,.45,"iron",.45)
		"table","dining","game_table","map_table","writing_desk","ledger_desk","jewelbench","herb_table","research_table","relic_table","specimen_table","ward_table","workbench","stonebench":
			_table(node,Vector2(2.6,1.35))
			match kind:
				"dining":
					for x: float in [-.75,.75]:
						_cylinder(node,Vector3(x,1.06,0),.25,.06,"clay")
						_cylinder(node,Vector3(x,1.14,.08),.14,.14,"food",.04)
						_stool(node,Vector3(x,0,1.1))
				"game_table":
					_box(node,Vector3(0,1.05,0),Vector3(.8,.025,.8),"canvas")
					for i in range(8):
						_cylinder(node,Vector3((i%4-1.5)*.19,1.12,(floori(i/4.0)*2-1)*.28),.06,.12,"dark_wood" if i<4 else "stone_light")
				"map_table","writing_desk","ledger_desk":
					_box(node,Vector3(0,1.045,0),Vector3(1.7,.025,.9),"paper")
					for i in range(3):
						_box(node,Vector3(-.4+i*.37,1.065,0),Vector3(.025,.01,.6),"ink")
					_cylinder(node,Vector3(1,1.12,-.3),.08,.18,"ink")
				"herb_table":
					for i in range(5):
						_cylinder(node,Vector3(-.9+i*.43,1.16,0),.12,.24,"herb",.04)
				"workbench":
					_box(node,Vector3(0,1.11,0),Vector3(1.6,.17,.30),"timber")
					_box(node,Vector3(.8,1.23,.4),Vector3(.34,.37,.25),"iron")
				"stonebench":
					_box(node,Vector3(0,1.30,0),Vector3(1.2,.5,.7),"stone_light")
				"research_table","ward_table","specimen_table","relic_table","jewelbench":
					for i in range(3):
						_cylinder(node,Vector3(-.65+i*.65,1.27,0),.17,.4,"copper" if kind=="jewelbench" else "purple",.035)
		"bench","story_chair":
			_box(node,Vector3(0,.58,0),Vector3(2.5,.17,.62),"timber")
			_box(node,Vector3(0,1.05,-.32),Vector3(2.5,.7,.12),"timber")
			for x: float in [-.9,.9]:
				_box(node,Vector3(x,.27,0),Vector3(.15,.55,.5),"dark_wood")
		"bookshelf","pantry":
			for x: float in [-.9,.9]:
				_box(node,Vector3(x,1.2,0),Vector3(.13,2.4,.55),"timber")
			for y: float in [.15,.83,1.5,2.3]:
				_box(node,Vector3(0,y,0),Vector3(1.9,.1,.55),"timber")
			for row in range(3):
				for col in range(5):
					if kind=="bookshelf":
						_box(node,Vector3(-.66+col*.31,.43+row*.68,0),Vector3(.18,.45,.4),["cloth_red","cloth_blue","cloth_green"][col%3])
					else:
						_cylinder(node,Vector3(-.66+col*.31,.35+row*.68,0),.12,.30,"clay",.08)
		"training","archery":
			_box(node,Vector3(0,1,0),Vector3(.15,2.0,.15),"timber")
			if kind=="archery":
				var target := _cylinder(node,Vector3(0,1.45,0),.65,.12,"canvas")
				target.rotation.x=PI*.5
				var bull := _cylinder(node,Vector3(0,1.45,.075),.22,.025,"cloth_red")
				bull.rotation.x=PI*.5
			else:
				_box(node,Vector3(0,1.3,0),Vector3(.55,.75,.32),"canvas")
				_box(node,Vector3(0,1.5,0),Vector3(1.5,.15,.16),"timber")
				_cylinder(node,Vector3(0,1.98,0),.23,.35,"canvas",.18)
		"loom":
			for x: float in [-.9,.9]:
				_box(node,Vector3(x,1.15,0),Vector3(.18,2.3,.18),"timber")
			for y: float in [.2,2.2]:
				_box(node,Vector3(0,y,0),Vector3(2,.18,.18),"timber")
			for i in range(14):
				_box(node,Vector3(-.75+i*.115,1.2,0),Vector3(.025,1.85,.025),"canvas")
			_box(node,Vector3(0,.7,.03),Vector3(1.5,.9,.045),"cloth_blue")
			_box(node,Vector3(0,1.4,.2),Vector3(1.8,.12,.12),"timber")
		"tanning_rack":
			for x: float in [-1.0,1.0]:
				_box(node,Vector3(x,1.2,0),Vector3(.15,2.4,.15),"timber")
			for y: float in [.15,2.3]:
				_box(node,Vector3(0,y,0),Vector3(2.1,.15,.15),"timber")
			_box(node,Vector3(0,1.25,0),Vector3(1.55,1.75,.08),"clay")
		"pottery_wheel":
			_cylinder(node,Vector3(0,.22,0),.70,.18,"timber")
			_cylinder(node,Vector3(0,.64,0),.11,.80,"timber")
			_cylinder(node,Vector3(0,1.03,0),.50,.12,"timber")
			_cylinder(node,Vector3(0,1.28,0),.27,.40,"clay",.18)
		"anvil":
			_cylinder(node,Vector3(0,.38,0),.43,.76,"timber")
			_box(node,Vector3(0,.95,0),Vector3(.52,.40,.55),"iron")
			_box(node,Vector3(0,1.19,0),Vector3(1.1,.16,.58),"steel")
			var horn:=_cylinder(node,Vector3(.7,1.18,0),.20,.65,"steel",.025)
			horn.rotation.z=PI*.5
		"stall","counter":
			_table(node,Vector2(2.6,1.3))
			for x: float in [-1.35,1.35]:
				_box(node,Vector3(x,1.3,-.6),Vector3(.13,2.6,.13),"timber")
			_box(node,Vector3(0,2.55,0),Vector3(3.0,.12,1.9),"cloth_green")
			for i in range(5):
				_cylinder(node,Vector3(-.9+i*.45,1.15,0),.18,.28,"food",.06)
		"brewvat","cauldron":
			_cylinder(node,Vector3(0,.75,0),.82,1.5,"timber" if kind=="brewvat" else "iron",.72)
			_cylinder(node,Vector3(0,1.51,0),.65,.03,"water" if kind=="brewvat" else "herb")
			for y: float in [.25,1.25]:
				_cylinder(node,Vector3(0,y,0),.84,.09,"iron")
		"trough":
			_box(node,Vector3(0,.45,0),Vector3(2.4,.9,.85),"timber")
			_box(node,Vector3(0,.91,0),Vector3(2.1,.03,.59),"water")
		"post_board":
			for x: float in [-.85,.85]:
				_box(node,Vector3(x,1.2,0),Vector3(.15,2.4,.15),"timber")
			_box(node,Vector3(0,1.7,0),Vector3(2.0,1.4,.15),"dark_wood")
			for i in range(3):
				_box(node,Vector3(-.65+i*.65,1.7,.09),Vector3(.48,.9,.025),"paper")
		"cargo":
			for i in range(3):
				_box(node,Vector3((i%2-.5)*1.2,.5+floori(i/2.0),0),Vector3(1.1,1,1),"timber")
		"weapon_rack","broom_rack","fishing_rack":
			for x: float in [-1,1]:
				_box(node,Vector3(x,1,0),Vector3(.12,2,.12),"timber")
			_box(node,Vector3(0,1.5,0),Vector3(2.2,.16,.15),"timber")
			for i in range(4):
				_box(node,Vector3(-.75+i*.5,1.15,.15),Vector3(.08,2.0,.08),"timber")
				_box(node,Vector3(-.75+i*.5,2.1,.15),Vector3(.28,.36,.06),"steel" if kind=="weapon_rack" else "canvas")
		"telescope":
			for i in range(3):
				var leg:=_box(node,Vector3(sin(i*TAU/3)*.3,.65,cos(i*TAU/3)*.3),Vector3(.09,1.4,.09),"timber")
				leg.rotation.z=.18
			var tube:=_cylinder(node,Vector3(0,1.5,0),.17,1.4,"copper")
			tube.rotation.x=PI*.4
		"lute":
			_cylinder(node,Vector3(0,.62,0),.42,.20,"timber").rotation.x=PI*.5
			_box(node,Vector3(0,1.25,0),Vector3(.12,1,.12),"dark_wood")
			for i in range(4):
				_box(node,Vector3((i-1.5)*.025,1.0,.12),Vector3(.008,1.4,.008),"canvas")
		"music_stand","lectern":
			_box(node,Vector3(0,.78,0),Vector3(.18,1.56,.18),"timber")
			var top:=_box(node,Vector3(0,1.5,0),Vector3(.95,.1,.65),"timber")
			top.rotation.x=.3
			_box(node,Vector3(0,1.58,0),Vector3(.74,.03,.5),"paper")
		"dance_floor":
			_box(node,Vector3(0,.045,0),Vector3(3,.09,3),"timber")
		"stage_props":
			_box(node,Vector3(0,.35,0),Vector3(1.4,.7,.8),"timber")
			for x: float in [-.4,.4]:
				_cylinder(node,Vector3(x,.88,0),.22,.3,"canvas",.15)
		"easel":
			for x: float in [-.5,.5]:
				_box(node,Vector3(x,1,0),Vector3(.10,2,.10),"timber")
			_box(node,Vector3(0,1.45,0),Vector3(1.15,1.25,.08),"canvas")
			_box(node,Vector3(0,1.45,.055),Vector3(.8,.9,.025),"cloth_green")
		"ore":
			_model("nature-kit/rock_largeC",node,Vector3(0,.1,0),Vector3.ONE*2.3)
			for i in range(4):
				_cylinder(node,Vector3(-.45+i*.3,.7,0),.14,.5,"steel",.035)
		"sawhorse":
			for x: float in [-.75,.75]:
				_box(node,Vector3(x,.6,0),Vector3(.15,1.2,.8),"timber")
			_box(node,Vector3(0,1.2,0),Vector3(2.7,.38,.40),"timber")
			_box(node,Vector3(0,1.45,.18),Vector3(1.8,.15,.035),"steel")
		"millstone":
			_cylinder(node,Vector3(0,.35,0),.95,.70,"stone")
			_cylinder(node,Vector3(0,.82,0),.92,.24,"stone_light")
			_box(node,Vector3(.4,1.05,0),Vector3(1.2,.1,.1),"timber")
		"crop","planter":
			_box(node,Vector3(0,.04,0),Vector3(2.6,.08,2.3),"soil")
			for i in range(6):
				_model("nature-kit/crops_wheatStageB" if kind=="crop" else "nature-kit/flower_purpleA",node,Vector3((i%3-1)*.75,.08,(floori(i/3.0)-.5)*.9),Vector3.ONE*1.5)
		"well":
			_cylinder(node,Vector3(0,.6,0),1.0,1.2,"stone")
			_cylinder(node,Vector3(0,1.21,0),.75,.03,"water")
			for x: float in [-1.1,1.1]:
				_box(node,Vector3(x,1.4,0),Vector3(.16,2.8,.16),"timber")
			_box(node,Vector3(0,2.7,0),Vector3(2.7,.16,2.0),"tile")
		_:
			_table(node,Vector2(2.0,1.2))
	return node

func _table(parent: Node3D, size: Vector2) -> void:
	_box(parent,Vector3(0,.98,0),Vector3(size.x,.15,size.y),"timber")
	for x: float in [-size.x*.4,size.x*.4]:
		for z: float in [-size.y*.35,size.y*.35]:
			_box(parent,Vector3(x,.46,z),Vector3(.14,.92,.14),"dark_wood")

func _stool(parent: Node3D, at: Vector3) -> void:
	_cylinder(parent,at+Vector3(0,.5,0),.32,.16,"timber")
	for i in range(3):
		_box(parent,at+Vector3(sin(i*TAU/3)*.22,.25,cos(i*TAU/3)*.22),Vector3(.08,.5,.08),"dark_wood")
