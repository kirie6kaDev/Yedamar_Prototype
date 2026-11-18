extends Node3D

signal navigation_changed

const Campaign := preload("res://scripts/campaign.gd")
const ENV := "res://assets/environment/"
const STATIONS := ["campfire", "cauldron", "workbench", "sawmill", "smelter", "anvil"]
const TITLES := {"workbench":"Столярный верстак", "sawmill":"Рамная пилорама", "smelter":"Плавильная печь", "anvil":"Кузнечная наковальня", "cauldron":"Алхимический котёл", "stable":"Конюшня", "herbalist_hut":"Лесная хижина травницы", "logging_tree":"Дерево для рубки"}
const BLUEPRINTS := {
	"workbench": {"name":"Столярный верстак", "cost":{"wood":6,"stone":4}, "duration":45.0, "radius":1.5},
	"sawmill": {"name":"Рамная пилорама", "cost":{"plank":10,"iron_ingot":2,"log":4}, "duration":90.0, "radius":2.1},
	"smelter": {"name":"Плавильная печь", "cost":{"stone":12,"wood":5}, "duration":75.0, "radius":1.5},
	"anvil": {"name":"Кузнечная наковальня", "cost":{"stone":6,"iron_ingot":3}, "duration":60.0, "radius":1.2},
	"cauldron": {"name":"Алхимический котёл", "cost":{"stone":5,"iron_ingot":2,"wood":3}, "duration":60.0, "radius":1.2}
}

var _world: Node3D
var _records: Dictionary = {}
var _nodes: Dictionary = {}
var _built := false
var _pending_restore: Dictionary = {}
var _materials: Dictionary = {}
var _background_trees: Dictionary = {}


func configure(world: Node3D) -> void:
	_world = world
	if is_node_ready():
		_build()


func _ready() -> void:
	if _world:
		_build()


func _build() -> void:
	if _built:
		return
	_built = true
	_cache_background_trees()
	_fixed_station("workbench", "farm_workbench", Vector2(4020,4345))
	_fixed_station("sawmill", "forest_sawmill", Vector2(4550,3752))
	var forge_site := _find_site(Vector2(3529,3740), 6.0)
	_shelter("town_forge_shelter", forge_site, false)
	_fixed_station("smelter", "town_smelter", forge_site + Vector2(-2.4,1.5))
	_fixed_station("anvil", "town_anvil", forge_site + Vector2(2.2,0))
	var stable_site := _find_site(Vector2(4100,4380), 5.5)
	_building("stable", "farm_stable", stable_site, 5.0)
	var hut_site := _find_site(Vector2(4563,3753), 4.8)
	_building("herbalist_hut", "forest_herbalist_hut", hut_site, 4.3)
	_fixed_station("cauldron", "forest_cauldron", hut_site + Vector2(0,7))
	for i in range(20):
		var center := Vector2(3958,4345) if i < 8 else Vector2(4540,3715)
		var angle := float(i) * 2.399963
		var p := center + Vector2.from_angle(angle) * (7.0 + float(i % 4) * 5.0)
		p = _find_site(p, 1.0)
		_add_object("logging_tree", "logging_tree_%02d" % i, p, angle, false)
	_refresh_approaches()
	if not _pending_restore.is_empty():
		var state := _pending_restore
		_pending_restore = {}
		restore(state)


func blueprints() -> Dictionary:
	return BLUEPRINTS.duplicate(true)


func owns(id: String) -> bool:
	return _records.has(id) or (_world and _world.objects.has(id) and str(_world.objects[id].type) in STATIONS)


func find_station(recipe_id: String, position: Vector3) -> String:
	if not Campaign.RECIPES.has(recipe_id):
		return ""
	var kind := str(Campaign.RECIPES[recipe_id].station)
	if kind.is_empty():
		return ""
	var nearest := ""
	var best := INF
	for id: String in _world.objects:
		var entry: Dictionary = _world.objects[id]
		if str(entry.type) != kind or not is_instance_valid(entry.node) or not entry.node.visible:
			continue
		var d := position.distance_squared_to(entry.get("approach", entry.position))
		if d < best:
			best = d
			nearest = id
	return nearest


func actions(id: String, person: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not owns(id):
		return result
	var kind := str(_world.objects[id].type)
	var catalog_person := person.duplicate(false)
	catalog_person.erase("position")
	if kind == "logging_tree":
		var reason := validate("chop", id, catalog_person)
		result.append({"id":"chop", "label":"Срубить · ветки и брёвна", "enabled":reason.is_empty(), "reason":reason})
	else:
		for recipe_id: String in Campaign.RECIPES:
			var recipe: Dictionary = Campaign.RECIPES[recipe_id]
			if str(recipe.station) != kind:
				continue
			var action := "craft:" + recipe_id
			var reason := validate(action, id, catalog_person)
			result.append({"id":action, "label":str(recipe.name), "enabled":reason.is_empty(), "reason":reason})
	return result


func duration(action: String, _id: String = "") -> float:
	if action == "chop":
		return 40.0
	var recipe_id := action.trim_prefix("craft:")
	if action.begins_with("craft:") and Campaign.RECIPES.has(recipe_id):
		return float(Campaign.RECIPES[recipe_id].duration)
	return 0.0


func validate(action: String, id: String, person: Dictionary) -> String:
	var inventory: Dictionary = person.get("inventory", {})
	if action == "chop":
		if not _records.has(id) or str(_records[id].kind) != "logging_tree":
			return "Это дерево нельзя рубить."
		if bool(_records[id].get("felled", false)):
			return "Дерево уже срублено."
		if int(inventory.get("axe",0)) < 1:
			return "Нужен топор в личном рюкзаке."
		return _distance_error(id, person)
	if not action.begins_with("craft:"):
		return "Неизвестная работа."
	var recipe_id := action.trim_prefix("craft:")
	if not Campaign.RECIPES.has(recipe_id):
		return "Неизвестный рецепт."
	var recipe: Dictionary = Campaign.RECIPES[recipe_id]
	var station := str(recipe.station)
	if not station.is_empty():
		if not _world.objects.has(id) or str(_world.objects[id].type) != station:
			return "Нужен подходящий станок: " + str(TITLES.get(station, "костёр")) + "."
		if not is_instance_valid(_world.objects[id].node) or not _world.objects[id].node.visible:
			return "Этот станок недоступен."
		var distance_error := _distance_error(id, person)
		if not distance_error.is_empty():
			return distance_error
	if str(recipe.skill) == "alchemy" and not bool(person.get("alchemy_learned", false)):
		return "Сначала пройдите урок травницы."
	var tool := str(recipe.get("needs_tool", ""))
	if not tool.is_empty() and int(inventory.get(tool, 0)) < 1:
		return "Нужен инструмент в личном рюкзаке: " + str(Campaign.ITEMS.get(tool,tool)) + "."
	for item: String in recipe.cost:
		if int(inventory.get(item,0)) < int(recipe.cost[item]):
			return "Не хватает: " + str(Campaign.ITEMS.get(item,item)) + "."
	return ""


func _distance_error(id: String, person: Dictionary) -> String:
	if not person.has("position"):
		return ""
	if not person.position is Vector3:
		return "Не удалось определить положение персонажа."
	var p: Vector3 = person.position
	var target: Vector3 = _world.objects[id].get("approach", _world.objects[id].position)
	if Vector2(p.x,p.z).distance_to(Vector2(target.x,target.z)) > 2.7:
		return "Сначала подойдите к месту работы."
	return ""


func complete(action: String, id: String, person: Dictionary) -> Dictionary:
	var reason := validate(action, id, person)
	if not reason.is_empty():
		return {"ok":false, "message":reason, "skill":"", "xp":0, "item":"", "count":0}
	var inventory: Dictionary = person.inventory
	if action == "chop":
		_records[id].felled = true
		_set_tree_felled(id, true)
		inventory.log = int(inventory.get("log",0)) + 2
		inventory.branch = int(inventory.get("branch",0)) + 3
		navigation_changed.emit()
		return {"ok":true,"message":"Дерево срублено: 2 бревна и 3 ветки.","skill":"woodcutting","xp":30,"item":"log","count":2,"items":{"log":2,"branch":3}}
	var recipe_id := action.trim_prefix("craft:")
	var recipe: Dictionary = Campaign.RECIPES[recipe_id]
	# Revalidate before any mutation; no partial costs and no tool consumption.
	for item: String in recipe.cost:
		inventory[item] = int(inventory.get(item,0)) - int(recipe.cost[item])
	var product := str(recipe.item)
	var count := int(recipe.count)
	inventory[product] = int(inventory.get(product,0)) + count
	return {"ok":true,"message":"Готово: %s × %d." % [Campaign.ITEMS.get(product,product), count],"skill":str(recipe.skill),"xp":int(recipe.xp),"item":product,"count":count}


func can_place(kind: String, position: Vector3, ignore_id: String="") -> String:
	if not BLUEPRINTS.has(kind):
		return "Неизвестный чертёж."
	if not _world:
		return "Мир ещё не готов."
	return _site_error(Vector2(position.x,position.z),float(BLUEPRINTS[kind].radius),ignore_id)


func place_station(kind: String, id: String, position: Vector3, rotation: float = 0.0) -> Node3D:
	if id.is_empty() or _world.objects.has(id) or not can_place(kind,position).is_empty():
		return null
	var node := _add_object(kind, id, Vector2(position.x,position.z), rotation, true)
	_refresh_approaches()
	navigation_changed.emit()
	return node


func _fixed_station(kind: String, id: String, near: Vector2) -> void:
	var p := _find_site(near, float(BLUEPRINTS[kind].radius))
	_add_object(kind,id,p,0.0,false)


func _site_error(p: Vector2, radius: float, ignore_id: String="") -> String:
	if not _world.bounds.grow(-radius-2.0).has_point(p):
		return "Здесь проходит край доступной земли."
	var elevation := float(_world.sample_height(p.x,p.y))
	if elevation < 1.0:
		return "Строить в воде нельзя."
	if _world.has_method("_distance_to_paths") and float(_world._distance_to_paths(p)) < radius+2.5:
		return "Оставьте дорогу свободной."
	var cell := Vector2i(floori(p.x/64.0),floori(p.y/64.0))
	for z in range(cell.y-1,cell.y+2):
		for x in range(cell.x-1,cell.x+2):
			for tree: Vector2 in _background_trees.get(Vector2i(x,z),[]):
				if p.distance_to(tree)<radius+0.8:
					return "Здесь уже растёт дерево."
	for offset in [Vector2(radius,0),Vector2(-radius,0),Vector2(0,radius),Vector2(0,-radius)]:
		var q: Vector2 = p+offset
		if absf(float(_world.sample_height(q.x,q.y))-elevation) > maxf(0.8,radius*0.45):
			return "Для постройки нужна более ровная земля."
	for obstacle: Dictionary in _world.obstacles:
		if not ignore_id.is_empty() and str(obstacle.get("industry_id",""))==ignore_id: continue
		var center: Vector3 = obstacle.position
		if p.distance_to(Vector2(center.x,center.z)) < radius + float(obstacle.radius) + 0.5:
			return "Место занято деревом или постройкой."
	for entry: Dictionary in _world.objects.values():
		if not ignore_id.is_empty() and str(entry.get("id",""))==ignore_id: continue
		var center: Vector3 = entry.position
		if p.distance_to(Vector2(center.x,center.z)) < radius + float(entry.get("surface_radius",0.8)) + 0.6:
			return "Оставьте проход к предметам рядом."
	return ""


func _cache_background_trees() -> void:
	_background_trees.clear()
	for child: Node in _world.get_children():
		if child is Node3D and child.scene_file_path.contains("/tree_"):
			_cache_tree(Vector2(child.global_position.x,child.global_position.z))
	var batches: Variant = _world.get("_batches")
	if batches is Dictionary:
		for batch: Dictionary in batches.values():
			if not str(batch.get("asset","")).contains("/tree_"):
				continue
			for transform: Transform3D in batch.get("transforms",[]):
				var p: Vector3 = transform.origin+batch.origin
				_cache_tree(Vector2(p.x,p.z))


func _cache_tree(p: Vector2) -> void:
	var cell := Vector2i(floori(p.x/64.0),floori(p.y/64.0))
	if not _background_trees.has(cell):
		_background_trees[cell] = []
	_background_trees[cell].append(p)


func _find_site(near: Vector2, radius: float) -> Vector2:
	for ring in range(13):
		for i in range(16 if ring > 0 else 1):
			var p := near + Vector2.from_angle(float(i)*TAU/16.0)*float(ring)*3.5
			if _site_error(p,radius).is_empty():
				return p
	push_warning("Could not find a clear industry site near " + str(near))
	return near


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x,float(_world.sample_height(p.x,p.y)),p.y)


func _add_object(kind: String, id: String, p: Vector2, angle: float, placed: bool) -> Node3D:
	if _nodes.has(id):
		return _nodes[id]
	var node := Node3D.new()
	node.name = id.validate_node_name()
	add_child(node)
	node.position = _ground(p)
	node.rotation.y = angle
	_nodes[id] = node
	_records[id] = {"kind":kind,"position":[p.x,node.position.y,p.y],"rotation":angle,"placed":placed,"felled":false}
	var radius := float(BLUEPRINTS[kind].radius) if BLUEPRINTS.has(kind) else (0.65 if kind=="logging_tree" else 4.3)
	if kind == "logging_tree":
		_tree_visual(node, id)
	else:
		_station_visual(node,kind)
	_register(id,kind,node,radius,5.0 if kind=="logging_tree" else 2.6)
	return node


func _register(id: String, kind: String, node: Node3D, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.name = "ClickBody"
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("object_id",id)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape.shape = cylinder
	shape.position.y = height*0.5
	body.add_child(shape)
	node.add_child(body)
	var obstacle_radius := radius if kind != "logging_tree" else 0.45
	_world.obstacles.append({"position":node.global_position,"radius":obstacle_radius,"industry_id":id})
	var approach := node.to_global(Vector3(0,0,radius+1.25))
	for i in range(16):
		var candidate := node.global_position + Vector3(sin(i*TAU/16),0,cos(i*TAU/16))*(radius+1.25)
		if _standing_clear(Vector2(candidate.x,candidate.z)):
			approach = candidate
			break
	approach.y = float(_world.sample_height(approach.x,approach.z))
	_world.objects[id] = {"id":id,"type":kind,"name":str(TITLES.get(kind,kind)),"description":_description(kind),"position":node.global_position,"approach":approach,"surface_radius":radius,"node":node}


func _standing_clear(p: Vector2) -> bool:
	if not _world.bounds.grow(-2).has_point(p) or float(_world.sample_height(p.x,p.y))<0.5:
		return false
	var dx := (float(_world.sample_height(p.x+3,p.y))-float(_world.sample_height(p.x-3,p.y)))/6.0
	var dz := (float(_world.sample_height(p.x,p.y+3))-float(_world.sample_height(p.x,p.y-3)))/6.0
	if Vector2(dx,dz).length()>0.82:
		return false
	for obstacle: Dictionary in _world.obstacles:
		var center: Vector3 = obstacle.position
		if p.distance_to(Vector2(center.x,center.z)) < float(obstacle.radius)+0.85:
			return false
	return true


func _refresh_approaches() -> void:
	for id: String in _records:
		var entry: Dictionary = _world.objects[id]
		var center: Vector3 = entry.position
		var radius := float(entry.surface_radius)
		var found := false
		for extra: float in [1.25,1.55,1.85]:
			for i in range(32):
				var angle := i*TAU/32.0
				var point: Vector2 = Vector2(center.x,center.z)+Vector2(sin(angle),cos(angle))*(radius+extra)
				if _standing_clear(point):
					entry.approach = _ground(point)
					found=true
					break
			if found: break


func _description(kind: String) -> String:
	match kind:
		"logging_tree": return "Можно срубить топором за 40 секунд. Даёт два бревна и три ветки. Срубленное дерево не восстанавливается после загрузки."
		"workbench": return "На верстаке делают луки и стрелы. Для распиловки брёвен здесь нужна пила в личном рюкзаке."
		"sawmill": return "Стационарная рамная пила превращает одно бревно в четыре доски. Личная пила не требуется."
		"smelter": return "Руда и древесный уголь превращаются в железный слиток. Работа занимает 75 секунд."
		"anvil": return "Слитки проковывают в заготовки; из них делают мечи и доспехи. Оружейное и бронное дело развиваются отдельно."
		"cauldron": return "Дополнительное место для зелий после урока Эллы. Её прежний котёл у дороги тоже доступен."
		"stable": return "Сухой навес с кормушкой и поилкой для дорожной лошади. Зорьку кормят и поят через её собственное меню."
		"herbalist_hut": return "Лесной приют Эллы; у входа стоит дополнительный алхимический котёл. Саму травницу можно найти у фермы."
	return "Место ремесленной работы."


func _mat(color: String, metal: bool = false, glow: bool = false) -> StandardMaterial3D:
	var key := color+str(metal)+str(glow)
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = 0.55 if metal else 0.9
	m.metallic = 0.65 if metal else 0.0
	if glow:
		m.emission_enabled = true
		m.emission = Color(color)
		m.emission_energy_multiplier = 1.4
	_materials[key] = m
	return m


func _box(parent: Node3D, p: Vector3, size: Vector3, color: String, metal: bool = false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = _mat(color,metal)
	m.position = p
	parent.add_child(m)
	return m


func _cylinder(parent: Node3D,p: Vector3,radius: float,height: float,color: String,top: float=-1.0,glow: bool=false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top<0 else top
	mesh.height = height
	mesh.radial_segments = 12
	node.mesh = mesh
	node.material_override = _mat(color,false,glow)
	node.position = p
	parent.add_child(node)
	return node


func _model(parent: Node3D,path: String,p: Vector3,scale: Vector3,angle: float=0.0) -> Node3D:
	var scene := load(ENV+path+".glb") as PackedScene
	var node := scene.instantiate() as Node3D
	node.position = p
	node.scale = scale
	node.rotation.y = angle
	parent.add_child(node)
	return node


func _station_visual(node: Node3D,kind: String) -> void:
	match kind:
		"workbench", "sawmill":
			var width := 3.5 if kind=="sawmill" else 2.5
			_box(node,Vector3(0,1.0,0),Vector3(width,0.22,1.1),"#8b6340")
			for x in [-1.0,1.0]:
				for z in [-0.38,0.38]:
					_box(node,Vector3(x*(width*0.5-0.2),0.48,z),Vector3(0.18,0.95,0.18),"#57412c")
			if kind=="workbench":
				_box(node,Vector3(0.65,1.2,-0.2),Vector3(0.38,0.32,0.4),"#53605b",true)
				_box(node,Vector3(-0.5,1.16,0),Vector3(1.15,0.10,0.30),"#c19b64")
			else:
				for x in [-0.7,0.7]:
					_box(node,Vector3(x,1.65,0),Vector3(0.13,1.4,0.13),"#60442e")
				_box(node,Vector3(0,2.33,0),Vector3(1.6,0.16,0.15),"#60442e")
				_box(node,Vector3(0,1.65,0),Vector3(0.035,1.3,0.20),"#b0bdba",true)
				_model(node,"nature-kit/log",Vector3(0,1.19,0.1),Vector3(0.5,0.5,3.5),PI*0.5)
		"smelter":
			_cylinder(node,Vector3(0,0.75,0),1.05,1.5,"#646762",0.85)
			_cylinder(node,Vector3(0,1.8,0),0.65,1.0,"#69635b",0.5)
			_cylinder(node,Vector3(0,2.7,0),0.42,0.9,"#4b514e")
			_box(node,Vector3(0,0.64,0.92),Vector3(0.72,0.68,0.15),"#292925")
			var fire := _box(node,Vector3(0,0.53,1.02),Vector3(0.51,0.34,0.07),"#dc7130")
			fire.material_override = _mat("#dc7130",false,true)
			var lamp := OmniLight3D.new()
			lamp.light_color = Color("#ffa25b")
			lamp.light_energy = 0.9
			lamp.omni_range = 5.0
			lamp.position = Vector3(0,0.8,1.1)
			node.add_child(lamp)
		"anvil":
			_cylinder(node,Vector3(0,0.4,0),0.53,0.8,"#6c5138")
			_box(node,Vector3(0,0.91,0),Vector3(0.85,0.25,0.5),"#4e5856",true)
			_box(node,Vector3(0,1.15,0),Vector3(0.5,0.3,0.35),"#64716f",true)
			_box(node,Vector3(0,1.34,0),Vector3(1.1,0.14,0.48),"#8d9d98",true)
			var horn := _cylinder(node,Vector3(0.73,1.27,0),0.22,0.65,"#758883",0.02)
			horn.rotation.z = -PI*0.5
			_box(node,Vector3(-0.24,1.49,0),Vector3(0.28,0.18,0.18),"#4d5653",true)
			_box(node,Vector3(-0.24,1.48,0.28),Vector3(0.07,0.07,0.5),"#9c764a")
		"cauldron":
			_world._cauldron_visual(node)


func _tree_visual(node: Node3D,id: String) -> void:
	var standing := _model(node,"nature-kit/tree_oak",Vector3.ZERO,Vector3.ONE*7.5)
	standing.name = "StandingTree"
	var stump := _model(node,"nature-kit/stump_round",Vector3.ZERO,Vector3.ONE*2.3)
	stump.name = "FelledStump"
	stump.visible = false
	# A small cloth marker distinguishes usable trees from backdrop foliage.
	_box(node,Vector3(0,1.05,0.37),Vector3(0.45,0.20,0.05),"#d4b569")


func _set_tree_felled(id: String,felled: bool) -> void:
	if not _nodes.has(id):
		return
	var node: Node3D = _nodes[id]
	node.get_node("StandingTree").visible = not felled
	node.get_node("FelledStump").visible = felled
	var body := node.get_node("ClickBody") as StaticBody3D
	var collider := body.get_child(0) as CollisionShape3D
	(collider.shape as CylinderShape3D).height = 0.8 if felled else 5.0
	collider.position.y = 0.4 if felled else 2.5
	_world.objects[id].name = "Пень · дерево срублено" if felled else TITLES.logging_tree
	for obstacle: Dictionary in _world.obstacles:
		if str(obstacle.get("industry_id","")) == id:
			obstacle.radius = 0.25 if felled else 0.45


func _shelter(id: String,p: Vector2,stable: bool) -> Node3D:
	var root := Node3D.new()
	root.name = id
	root.position = _ground(p)
	add_child(root)
	for x in [-3.8,3.8]:
		for z in [-2.5,2.5]:
			_box(root,Vector3(x,1.6,z),Vector3(0.28,3.4,0.28),"#684a31")
			_world.obstacles.append({"position":root.to_global(Vector3(x,0,z)),"radius":0.25,"industry_id":id})
	_model(root,"fantasy-town-kit/roof-gable",Vector3(0,3.1,0),Vector3(8.4,3.0,6.2))
	if stable:
		for z in [-2.5,0.0]:
			_box(root,Vector3(0,1.0,z),Vector3(7.5,0.15,0.14),"#a0784c")
			_box(root,Vector3(0,0.5,z),Vector3(7.5,0.15,0.14),"#a0784c")
	return root


func _building(kind: String,id: String,p: Vector2,radius: float) -> void:
	var node: Node3D
	if kind=="stable":
		node = _shelter(id,p,true)
		_box(node,Vector3(-2.3,0.35,1.1),Vector3(2.1,0.7,0.8),"#785538")
		_box(node,Vector3(-2.3,0.73,1.1),Vector3(1.9,0.1,0.65),"#cfb46a")
		_box(node,Vector3(2.0,0.35,1.1),Vector3(1.7,0.7,0.85),"#665743")
		_box(node,Vector3(2.0,0.70,1.1),Vector3(1.5,0.03,0.66),"#5b929b")
	else:
		node = Node3D.new()
		node.position = _ground(p)
		add_child(node)
		_box(node,Vector3(0,-0.3,0),Vector3(6.2,0.8,6.2),"#757765")
		for side in range(4):
			_model(node,"fantasy-town-kit/"+("wall-wood-door" if side==0 else "wall-wood-window-shutters"),Vector3.ZERO,Vector3(6,2.8,6),side*PI*0.5)
		_model(node,"fantasy-town-kit/roof-gable",Vector3(0,2.8,0),Vector3(6.5,3,6.5))
		_model(node,"fantasy-town-kit/chimney",Vector3(-1.4,4.3,0),Vector3(1.2,2,1.2))
	_nodes[id] = node
	_records[id] = {"kind":kind,"position":[p.x,node.position.y,p.y],"rotation":0.0,"placed":false}
	_register(id,kind,node,radius,4.0)


func snapshot() -> Dictionary:
	return {"version":1,"objects":_records.duplicate(true)}


func clear_placed() -> void:
	# The game clears both construction owners before restoring either one:
	# their independent save branches may reuse the same built_N identifier.
	for id: String in _records.keys():
		if bool(_records[id].get("placed",false)):
			_remove_placed(id)


func restore(data: Dictionary) -> void:
	if not _built:
		_pending_restore = data.duplicate(true)
		return
	var records: Dictionary = data.get("objects",{})
	# Recreate every player station so reused IDs restore saved kind/transform.
	clear_placed()
	for id: String in _records.keys():
		if str(_records[id].kind)=="logging_tree" and not records.has(id):
			_records[id].felled = false
			_set_tree_felled(id,false)
	for id: String in records:
		if not records[id] is Dictionary:
			continue
		var record: Dictionary = records[id]
		var kind := str(record.get("kind",""))
		if not _records.has(id) and bool(record.get("placed",false)) and BLUEPRINTS.has(kind) and not _world.objects.has(id):
			var p: Array = record.get("position",[])
			if p.size()==3 and is_finite(float(p[0])) and is_finite(float(p[2])):
				_add_object(kind,id,Vector2(float(p[0]),float(p[2])),float(record.get("rotation",0)),true)
		if _records.has(id) and str(_records[id].kind)=="logging_tree":
			_records[id].felled = bool(record.get("felled",false))
			_set_tree_felled(id,bool(_records[id].felled))
	_refresh_approaches()
	navigation_changed.emit()


func _remove_placed(id: String) -> void:
	if _nodes.has(id):
		_nodes[id].queue_free()
	_nodes.erase(id)
	_records.erase(id)
	_world.objects.erase(id)
	for i in range(_world.obstacles.size()-1,-1,-1):
		if str(_world.obstacles[i].get("industry_id",""))==id:
			_world.obstacles.remove_at(i)
