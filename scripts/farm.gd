extends Node3D

# Stand-alone garden simulation. The caller owns time, action queues and skill XP.
const NATURE := "res://assets/environment/nature-kit/"
const STORE_ID := "garden_store"
const BED_ID := "garden_bed"
const PRODUCE := ["carrot", "herb", "apple", "mint", "lavender", "berry", "hay"]
const CROP_RULES := {
	"carrot": {"seed":"seeds_carrot", "minutes":180.0, "yield":6, "name":"Морковь"},
	"herb": {"seed":"seeds_herb", "minutes":150.0, "yield":4, "name":"Лечебные травы"}
}
const LABELS := {
	"farm_harvest":"Собрать урожай", "farm_store":"Сложить урожай и лишние семена",
	"farm_water":"Полить · 1 вода", "farm_tend":"Прополоть и ухаживать",
	"farm_plant_carrot":"Посеять морковь · 1 семена", "farm_plant_herb":"Посеять травы · 1 семена",
	"farm_till":"Вскопать грядку · нужна мотыга", "farm_plant_apple":"Посадить яблоню · 1 саженец",
	"farm_take_supplies":"Взять семена из ящика", "farm_take_produce":"Забрать урожай из ящика"
}

var plots: Dictionary = {}
var trees: Dictionary = {}
var storage: Dictionary = {}
var new_plots_allowed: bool = false
var elapsed_minutes: float = 0.0
var _world: Node3D
var _nodes: Dictionary = {}
var _visuals: Dictionary = {}
var _materials: Dictionary = {}
var _model_cache: Dictionary = {}
var _visual_timer: float = 0.0
var _built: bool = false


func configure(world: Node3D) -> void:
	_world = world


func _ready() -> void:
	if not is_instance_valid(_world):
		push_error("Farm.configure(world) must precede add_child().")
		return
	_build()


func _ground(x: float, z: float, lift: float = 0.0) -> Vector3:
	return Vector3(x, float(_world.sample_height(x,z))+lift,z)


func _build() -> void:
	if _built:
		return
	_built = true
	for i in 4:
		var id: String = "garden_plot_%d" % (i+1)
		plots[id] = {"created":true, "tilled":i!=3, "quest_required":false, "crop":"carrot" if i==0 else ("herb" if i==1 else ""), "growth":1.0 if i==0 else .42, "water":52.0 if i==0 else 58.0, "care":.85, "harvests":0}
		_make_plot(id,Vector2(3999+i*7,4433))
	for i in 3:
		var id: String = "garden_new_%d" % (i+1)
		plots[id] = {"created":false, "tilled":false, "quest_required":true, "crop":"", "growth":0.0, "water":0.0, "care":1.0, "harvests":0}
		_make_plot(id,Vector2(4027+i*7,4433))
	for i in 3:
		var id: String = "garden_apple_%d" % (i+1)
		trees[id] = {"planted":i<2, "growth":1.0 if i<2 else 0.0, "fruit":1.0 if i==0 else .35, "water":72.0, "care":.8, "harvests":0}
		_make_tree(id,Vector2(3980,4428+i*10))
	var box: Node3D = _register(STORE_ID,"garden_storage","Садовый ящик",Vector2(3991,4441),1.0,1.95)
	_world.obstacles.append({"position":box.position,"radius":.9})
	_box(box,Vector3(0,.65,0),Vector3(1.8,1.3,1.3),_mat("wood",Color("#88613e")))
	for x in [-.75,.75]:
		_box(box,Vector3(x,.66,.68),Vector3(.13,1.4,.10),_mat("lightwood",Color("#bc9662")))
	for y in [.12,.6,1.12]:
		_box(box,Vector3(0,y,.68),Vector3(1.8,.1,.12),_mat("lightwood",Color("#bc9662")))
	_label(box,"САДОВЫЙ ЯЩИК",Vector3(0,1.75,0),Color("#e6d8aa"),23)
	var bed: Node3D = _register(BED_ID,"bed","Лежанка у сада",Vector2(3990,4450),1.2,1.6)
	_model("bed_floor",bed,Vector3.ZERO,Vector3(2.3,2.3,2.3))
	_world.objects[BED_ID].description="Сухая лежанка под яблонями. Сон и часы отдыха управляются общим режимом поселения."
	_refresh_all()


func owns(id: String) -> bool:
	return plots.has(id) or trees.has(id) or id==STORE_ID


func set_new_plots_allowed(allowed: bool) -> void:
	new_plots_allowed=allowed
	for id: String in plots:
		if not bool(plots[id].created):
			_refresh(id)


func actions(id: String, person: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var names: Array[String]=[]
	if plots.has(id):
		var plot:Dictionary=plots[id]
		if not bool(plot.created) or not bool(plot.tilled):
			names.append("farm_till")
		elif str(plot.crop).is_empty():
			names.append_array(["farm_plant_carrot","farm_plant_herb"])
		else:
			names.append_array(["farm_harvest","farm_water","farm_tend"])
	elif trees.has(id):
		if bool(trees[id].planted):
			names.append_array(["farm_harvest","farm_water","farm_tend"])
		else:
			names.append("farm_plant_apple")
	elif id==STORE_ID:
		names.append_array(["farm_store","farm_take_supplies","farm_take_produce"])
	for action: String in names:
		var reason: String=validate(action,id,person)
		result.append({"id":action,"label":LABELS[action],"enabled":reason.is_empty(),"reason":reason})
	return result


func duration(action: String, _id: String) -> float:
	match action:
		"farm_till": return 7.0
		"farm_plant_apple": return 5.5
		"farm_tend": return 4.5
		"farm_plant_carrot","farm_plant_herb": return 3.5
		"farm_harvest": return 3.0
		"farm_water": return 2.5
		_: return 2.0


func validate(action: String, id: String, person: Dictionary) -> String:
	if not owns(id): return "Этот объект не относится к огороду."
	if not person.get("inventory") is Dictionary: return "У героя нет доступного рюкзака."
	var inv:Dictionary=person.inventory
	if id==STORE_ID:
		if action=="farm_store":
			return "" if _has_storable(inv) else "В рюкзаке нет урожая или лишних семян."
		if action=="farm_take_supplies":
			return "" if _supplies_needed(inv) else "В ящике нет нужных семян или запас уже набран."
		if action=="farm_take_produce":
			for item:String in PRODUCE:
				if int(storage.get(item,0))>0: return ""
			return "В ящике пока нет урожая."
		return "Здесь можно хранить и забирать припасы."
	if plots.has(id):
		var p:Dictionary=plots[id]
		if not bool(p.created) and (not bool(person.get("allow_new_plots",false)) or not bool(p.quest_required)):
			return "Новые грядки разрешаются только галочкой задания."
		match action:
			"farm_till":
				if bool(p.tilled): return "Грядка уже вскопана."
				if int(inv.get("hoe",0))<1: return "Нужна мотыга в личном рюкзаке."
				return ""
			"farm_plant_carrot","farm_plant_herb":
				if not bool(p.created) or not bool(p.tilled): return "Сначала вскопайте грядку мотыгой."
				if not str(p.crop).is_empty(): return "Эта грядка уже занята."
				var crop:String="carrot" if action=="farm_plant_carrot" else "herb"
				return "" if int(inv.get(CROP_RULES[crop].seed,0))>0 else "Нужны семена выбранной культуры."
			"farm_harvest":
				return "" if not str(p.crop).is_empty() and float(p.growth)>=1.0 else "Урожай ещё не созрел."
			"farm_water","farm_tend":
				if str(p.crop).is_empty(): return "Сначала посадите культуру."
				if float(p.growth)>=1.0: return "Урожай созрел — сначала соберите его."
				if action=="farm_water":
					if float(p.water)>=85: return "Земля уже достаточно влажная."
					return "" if int(inv.get("water",0))>0 else "Наберите воду в колодце."
				return "" if float(p.care)<.95 else "Грядка уже ухожена."
	elif trees.has(id):
		var t:Dictionary=trees[id]
		match action:
			"farm_plant_apple":
				if bool(t.planted): return "Яблоня уже посажена."
				if int(inv.get("hoe",0))<1: return "Для посадки нужна мотыга."
				return "" if int(inv.get("apple_sapling",0))>0 else "Нужен саженец яблони."
			"farm_harvest":
				return "" if bool(t.planted) and float(t.growth)>=1 and float(t.fruit)>=1 else "Яблоки ещё не созрели."
			"farm_water","farm_tend":
				if not bool(t.planted): return "Сначала посадите яблоню."
				if action=="farm_water":
					if float(t.water)>=85: return "У корней достаточно воды."
					return "" if int(inv.get("water",0))>0 else "Наберите воду в колодце."
				return "" if float(t.care)<.95 else "Яблоня уже ухожена."
	return "Это действие не подходит к выбранному месту."


func complete(action: String, id: String, person: Dictionary) -> Dictionary:
	var reason:String=validate(action,id,person)
	if not reason.is_empty(): return {"ok":false,"message":reason,"skill":"","xp":0}
	var inv:Dictionary=person.inventory
	var skill:String="farming"
	var xp:int=4
	var message:String=""
	if id==STORE_ID:
		var count:int=0
		if action=="farm_store":
			for item:String in PRODUCE+["seeds_carrot","seeds_herb"]:
				var keep:int=4 if item=="seeds_carrot" else (2 if item=="seeds_herb" else 0)
				var amount:int=maxi(0,int(inv.get(item,0))-keep)
				if amount>0:
					inv[item]=int(inv[item])-amount
					storage[item]=int(storage.get(item,0))+amount
					count+=amount
			message="В садовый ящик сложено: %d. Семена для ближайших посадок остались в рюкзаке." % count
		elif action=="farm_take_supplies":
			for item:String in ["seeds_carrot","seeds_herb"]:
				var limit:int=4 if item=="seeds_carrot" else 2
				var amount:int=mini(int(storage.get(item,0)),maxi(0,limit-int(inv.get(item,0))))
				storage[item]=int(storage.get(item,0))-amount
				inv[item]=int(inv.get(item,0))+amount
				count+=amount
			message="Взяты семена для посадок: %d." % count
		else:
			for item:String in PRODUCE:
				var amount:int=mini(12,int(storage.get(item,0)))
				storage[item]=int(storage.get(item,0))-amount
				inv[item]=int(inv.get(item,0))+amount
				count+=amount
			message="Из садового ящика взято: %d." % count
		skill=""
		xp=0
	elif plots.has(id):
		var p:Dictionary=plots[id]
		if str(p.crop)=="herb" or action=="farm_plant_herb": skill="herbalism"
		match action:
			"farm_till":
				p.created=true
				p.tilled=true
				p.care=1.0
				xp=8
				message="Грядка вскопана. Можно выбирать семена."
			"farm_plant_carrot","farm_plant_herb":
				var crop:String="carrot" if action=="farm_plant_carrot" else "herb"
				var seed:String=CROP_RULES[crop].seed
				inv[seed]=int(inv[seed])-1
				p.crop=crop
				p.growth=0.0
				p.care=1.0
				p.water=minf(float(p.water),30.0)
				xp=6
				message="Посажено: %s. Не забудьте полить." % CROP_RULES[crop].name
			"farm_water":
				inv.water=int(inv.water)-1
				p.water=100.0
				message="Грядка полита. Влажная земля поддерживает рост."
			"farm_tend":
				p.care=1.0
				message="Сорняки убраны. Ухоженная грядка растёт быстрее."
			"farm_harvest":
				var crop:String=str(p.crop)
				var amount:int=int(CROP_RULES[crop].yield)+(1 if float(p.care)>=.75 else 0)
				inv[crop]=int(inv.get(crop,0))+amount
				var seed:String=CROP_RULES[crop].seed
				inv[seed]=int(inv.get(seed,0))+2
				p.crop=""
				p.growth=0.0
				p.harvests=int(p.harvests)+1
				xp=12
				message="Урожай: %s ×%d. Сохранены семена для следующих посадок." % [CROP_RULES[crop].name,amount]
	else:
		var t:Dictionary=trees[id]
		match action:
			"farm_plant_apple":
				inv.apple_sapling=int(inv.apple_sapling)-1
				t.planted=true
				t.growth=0.04
				t.fruit=0.0
				t.water=25.0
				t.care=1.0
				xp=12
				message="Молодая яблоня посажена. Поливайте её, пока укореняется."
			"farm_water":
				inv.water=int(inv.water)-1
				t.water=100.0
				message="Корни яблони политы."
			"farm_tend":
				t.care=1.0
				message="Приствольный круг очищен и разрыхлён."
			"farm_harvest":
				var amount:int=5+(1 if float(t.care)>=.75 else 0)
				inv.apple=int(inv.get("apple",0))+amount
				t.fruit=0.0
				t.harvests=int(t.harvests)+1
				xp=10
				message="Собрано яблок: %d. Взрослая яблоня даст новый урожай." % amount
	_refresh(id)
	return {"ok":true,"message":message,"skill":skill,"xp":xp}


func _has_storable(inv: Dictionary) -> bool:
	for item:String in PRODUCE:
		if int(inv.get(item,0))>0: return true
	return int(inv.get("seeds_carrot",0))>4 or int(inv.get("seeds_herb",0))>2


func _supplies_needed(inv: Dictionary) -> bool:
	return (int(inv.get("seeds_carrot",0))<4 and int(storage.get("seeds_carrot",0))>0) or (int(inv.get("seeds_herb",0))<2 and int(storage.get("seeds_herb",0))>0)


func plan_work(person: Dictionary, allow_new: bool) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if not person.get("inventory") is Dictionary: return result
	var simulated:Dictionary=person.duplicate(true)
	simulated.allow_new_plots=allow_new
	var inv:Dictionary=simulated.inventory
	var ids:Array=[]
	for id:String in plots:
		if bool(plots[id].created) or (allow_new and bool(plots[id].quest_required)):
			ids.append(id)
	ids.append_array(trees.keys())
	if person.get("position") is Vector3:
		var origin:Vector3=person.position
		ids.sort_custom(func(a:String,b:String)->bool: return _world.objects[a].position.distance_squared_to(origin)<_world.objects[b].position.distance_squared_to(origin))
	for id:String in ids:
		if validate("farm_harvest",id,simulated).is_empty(): result.append({"action":"farm_harvest","id":id})
	if _has_storable(inv):
		result.append({"action":"farm_store","id":STORE_ID})
		for item:String in PRODUCE: inv[item]=0
		inv.seeds_carrot=mini(4,int(inv.get("seeds_carrot",0)))
		inv.seeds_herb=mini(2,int(inv.get("seeds_herb",0)))
	var needs_water:bool=false
	for id:String in ids:
		var entry:Dictionary=plots[id] if plots.has(id) else trees[id]
		var active:bool=not str(entry.crop).is_empty() and float(entry.growth)<1 if plots.has(id) else bool(entry.planted)
		if active and float(entry.water)<40:
			needs_water=true
			if validate("farm_water",id,simulated).is_empty():
				result.append({"action":"farm_water","id":id})
				inv.water=int(inv.water)-1
	if needs_water and int(person.inventory.get("water",0))==0 and _world.objects.has("farm_well"):
		result.append({"action":"fill","id":"farm_well"})
	for id:String in ids:
		var entry:Dictionary=plots[id] if plots.has(id) else trees[id]
		if float(entry.care)<.7 and validate("farm_tend",id,simulated).is_empty(): result.append({"action":"farm_tend","id":id})
	if _supplies_needed(inv): result.append({"action":"farm_take_supplies","id":STORE_ID})
	for id:String in ids:
		for action:String in ["farm_plant_carrot","farm_plant_herb","farm_plant_apple"]:
			if validate(action,id,simulated).is_empty():
				result.append({"action":action,"id":id})
				var item:String="seeds_carrot" if action=="farm_plant_carrot" else ("seeds_herb" if action=="farm_plant_herb" else "apple_sapling")
				inv[item]=int(inv[item])-1
				break
	for id:String in ids:
		if plots.has(id) and validate("farm_till",id,simulated).is_empty(): result.append({"action":"farm_till","id":id})
	return result.slice(0,12)


func tick(delta: float, game_minutes: float) -> void:
	# game_minutes is ELAPSED simulated minutes in this call, never clock-of-day.
	if not is_finite(game_minutes) or game_minutes<0: return
	var minutes:float=minf(game_minutes,10080.0)
	elapsed_minutes+=minutes
	for p:Dictionary in plots.values():
		if not bool(p.created) or str(p.crop).is_empty() or float(p.growth)>=1: continue
		var wet:float=minf(minutes,maxf(0,float(p.water)-12.0)/.30)
		p.growth=minf(1.0,float(p.growth)+wet/float(CROP_RULES[p.crop].minutes)*(.75+.35*float(p.care)))
		p.water=maxf(0,float(p.water)-minutes*.30)
		p.care=maxf(.15,float(p.care)-minutes*.0009)
	for t:Dictionary in trees.values():
		if not bool(t.planted): continue
		var wet:float=minf(minutes,maxf(0,float(t.water)-8.0)/.08)
		var rate:float=.75+.30*float(t.care)
		if float(t.growth)<1:
			var needed:float=(1.0-float(t.growth))*500.0/rate
			var growing:float=minf(wet,needed)
			t.growth=minf(1.0,float(t.growth)+growing/500.0*rate)
			wet-=growing
		if float(t.growth)>=1: t.fruit=minf(1.0,float(t.fruit)+wet/240.0*rate)
		t.water=maxf(0,float(t.water)-minutes*.08)
		t.care=maxf(.15,float(t.care)-minutes*.0005)
	_visual_timer+=maxf(0,delta)
	if _visual_timer>=1.0 or minutes>=5:
		_visual_timer=0
		_refresh_all()


func status(id: String) -> Dictionary:
	if plots.has(id): return plots[id].duplicate(true)
	if trees.has(id): return trees[id].duplicate(true)
	if id==STORE_ID: return {"storage":storage.duplicate(true)}
	return {}


func snapshot() -> Dictionary:
	return {"version":1,"plots":plots.duplicate(true),"trees":trees.duplicate(true),"storage":storage.duplicate(true),"new_plots_allowed":new_plots_allowed,"elapsed_minutes":elapsed_minutes}


func valid_snapshot(data: Dictionary) -> bool:
	if int(data.get("version",0))!=1: return false
	for group:String in ["plots","trees","storage"]:
		if not data.get(group) is Dictionary: return false
	for id:String in data.plots:
		if not plots.has(id) or not data.plots[id] is Dictionary: return false
		var p:Dictionary=data.plots[id]
		if p.get("crop","") not in ["","carrot","herb"]: return false
		for flag:String in ["created","tilled","quest_required"]:
			if not p.get(flag) is bool: return false
		for key:String in ["growth","water","care","harvests"]:
			if not _finite_number(p.get(key)): return false
	for id:String in data.trees:
		if not trees.has(id) or not data.trees[id] is Dictionary: return false
		if not data.trees[id].get("planted") is bool: return false
		for key:String in ["growth","fruit","water","care","harvests"]:
			if not _finite_number(data.trees[id].get(key)): return false
	for item:String in data.storage:
		if item not in PRODUCE+["seeds_carrot","seeds_herb"] or not _finite_number(data.storage[item]) or float(data.storage[item])<0: return false
	return _finite_number(data.get("elapsed_minutes",0)) and data.get("new_plots_allowed",false) is bool


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func restore(data: Dictionary) -> void:
	if not valid_snapshot(data): return
	for id:String in data.plots:
		var quest_required:bool=bool(plots[id].quest_required)
		plots[id]=data.plots[id].duplicate(true)
		plots[id].quest_required=quest_required
		_normalize(plots[id])
	for id:String in data.trees:
		trees[id]=data.trees[id].duplicate(true)
		_normalize(trees[id])
	storage.clear()
	for item:String in data.storage: storage[item]=clampi(int(data.storage[item]),0,99999)
	elapsed_minutes=maxf(0,float(data.get("elapsed_minutes",0)))
	new_plots_allowed=bool(data.get("new_plots_allowed",false))
	_refresh_all()


func _normalize(entry: Dictionary) -> void:
	for key:String in ["growth","fruit","care"]:
		if entry.has(key): entry[key]=clampf(float(entry[key]),0,1)
	entry.water=clampf(float(entry.water),0,100)
	entry.harvests=maxi(0,int(entry.harvests))


func _register(id: String, kind: String, title: String, point: Vector2, radius: float, approach_distance: float) -> Node3D:
	var node:Node3D=_world.spawn_interactable(id,kind,title,_ground(point.x,point.y),"")
	for child:Node in node.get_children():
		if child is CollisionObject3D:
			var shape_node:CollisionShape3D=child.get_child(0) as CollisionShape3D
			if shape_node and shape_node.shape is CylinderShape3D:
				shape_node.shape.radius=radius
				shape_node.shape.height=.7 if kind=="garden_plot" else 1.8
				shape_node.position.y=.35 if kind=="garden_plot" else .9
		else:
			node.remove_child(child)
			child.queue_free()
	_world.objects[id].surface_radius=radius
	_world.objects[id].approach=_ground(point.x,point.y+approach_distance)
	_nodes[id]=node
	return node


func _make_plot(id: String, point: Vector2) -> void:
	var node:Node3D=_register(id,"garden_plot","Грядка" if bool(plots[id].created) else "Место новой грядки · задание",point,2.6,4.0)
	var soil:StandardMaterial3D=StandardMaterial3D.new()
	soil.roughness=1
	var earth:MeshInstance3D=_box(node,Vector3(0,.06,0),Vector3(4.8,.13,5.4),soil)
	var border:=Node3D.new()
	node.add_child(border)
	for side:float in [-1.0,1.0]:
		_box(border,Vector3(side*2.45,.18,0),Vector3(.15,.3,5.6),_mat("wood",Color("#88613e")))
		_box(border,Vector3(0,.18,side*2.75),Vector3(4.9,.3,.15),_mat("wood",Color("#88613e")))
	var plants:=Node3D.new()
	plants.name="Crops"
	node.add_child(plants)
	var carrots:=Node3D.new()
	plants.add_child(carrots)
	var herbs:=Node3D.new()
	plants.add_child(herbs)
	for row in 4:
		for col in 3:
			var at:=Vector3((col-1)*1.4,.15,(row-1.5)*1.25)
			_model("crops_leafsStageB",carrots,at,Vector3.ONE*1.35)
			_sphere(carrots,at+Vector3(0,.1,0),.16,_mat("carrot",Color("#dd913c")))
			_model("flower_purpleA",herbs,at,Vector3.ONE*2.2)
	var ghost:=Node3D.new()
	node.add_child(ghost)
	var ghost_mat:StandardMaterial3D=_mat("ghost",Color(.54,.86,.61,.68))
	ghost_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	for side:float in [-1.0,1.0]:
		_box(ghost,Vector3(side*2.45,.12,0),Vector3(.06,.12,5.6),ghost_mat)
		_box(ghost,Vector3(0,.12,side*2.75),Vector3(4.9,.12,.06),ghost_mat)
	_label(ghost,"НОВАЯ ГРЯДКА\nпо заданию",Vector3(0,.55,0),Color("#c8df95"),20)
	var label:Label3D=_label(node,"",Vector3(0,.7,0),Color("#eee5bd"),19)
	_visuals[id]={"soil":earth,"material":soil,"border":border,"plants":plants,"carrots":carrots,"herbs":herbs,"ghost":ghost,"label":label}


func _make_tree(id: String, point: Vector2) -> void:
	var node:Node3D=_register(id,"garden_tree","Яблоня" if bool(trees[id].planted) else "Место для яблони",point,.8,1.7)
	_world.obstacles.append({"position":node.position,"radius":.45})
	var tree:Node3D=_model("tree_oak",node,Vector3.ZERO,Vector3.ONE*4.5)
	var fruit:=Node3D.new()
	node.add_child(fruit)
	for i in 9:
		var angle:float=i*TAU/9
		_sphere(fruit,Vector3(cos(angle)*1.25,2.6+sin(angle*2)*.35,sin(angle)*1.25),.16,_mat("apple",Color("#c84935")))
	var stake:=Node3D.new()
	node.add_child(stake)
	_box(stake,Vector3(0,.5,0),Vector3(.08,1,.08),_mat("wood",Color("#88613e")))
	_box(stake,Vector3(.18,.9,0),Vector3(.45,.35,.06),_mat("greenflag",Color("#83a85d")))
	var label:Label3D=_label(node,"",Vector3(0,4.5,0),Color("#eee5bd"),20)
	_visuals[id]={"tree":tree,"fruit":fruit,"stake":stake,"label":label}


func _refresh_all() -> void:
	for id:String in _nodes:
		_refresh(id)


func _refresh(id: String) -> void:
	if not _nodes.has(id): return
	var node:Node3D=_nodes[id]
	if plots.has(id):
		var p:Dictionary=plots[id]
		var view:Dictionary=_visuals[id]
		var visible_now:bool=bool(p.created) or (new_plots_allowed and bool(p.quest_required))
		node.visible=visible_now
		for child:Node in node.get_children():
			if child is CollisionObject3D: child.collision_layer=2 if visible_now else 0
		view.soil.visible=bool(p.created)
		view.border.visible=bool(p.created)
		view.plants.visible=bool(p.created) and not str(p.crop).is_empty()
		view.carrots.visible=str(p.crop)=="carrot"
		view.herbs.visible=str(p.crop)=="herb"
		for group:Node3D in [view.carrots,view.herbs]:
			for plant:Node3D in group.get_children():
				plant.scale=plant.get_meta("base_scale",Vector3.ONE)*(.22+.78*float(p.growth))
		view.ghost.visible=not bool(p.created)
		view.label.visible=bool(p.created)
		view.material.albedo_color=Color("#755437").lerp(Color("#493e2c"),float(p.water)/100*.65)
		var title:String="Нужно вскопать" if not bool(p.tilled) else "Свободная грядка"
		if not str(p.crop).is_empty():
			title="%s · %s" % [CROP_RULES[p.crop].name,"урожай" if float(p.growth)>=1 else "%d%%" % roundi(float(p.growth)*100)]
		view.label.text=title
		_world.objects[id].name=title if bool(p.created) else "Новая грядка · задание"
		_world.objects[id].description="%s. Влажность %d%%, уход %d%%. %s" % [title,roundi(float(p.water)),roundi(float(p.care)*100),"Место нового огорода доступно только по разрешению задания." if not bool(p.created) else "Влажные посадки растут с игровым временем. Сухая земля останавливает рост."]
		_world.objects[id].quest_required=bool(p.quest_required)
	elif trees.has(id):
		var t:Dictionary=trees[id]
		var view:Dictionary=_visuals[id]
		view.tree.visible=bool(t.planted)
		view.tree.scale=Vector3.ONE*(.7+3.8*float(t.growth))
		view.fruit.visible=bool(t.planted) and float(t.growth)>=1 and float(t.fruit)>=.65
		view.fruit.scale=Vector3.ONE*(.55+.45*float(t.fruit))
		view.stake.visible=not bool(t.planted)
		view.label.position.y=1.5+3.0*float(t.growth) if bool(t.planted) else 1.4
		view.label.text="Посадить яблоню" if not bool(t.planted) else ("Яблоня · урожай" if float(t.fruit)>=1 and float(t.growth)>=1 else ("Яблоня · %d%%" % roundi(float(t.growth)*100) if float(t.growth)<1 else "Яблоки · %d%%" % roundi(float(t.fruit)*100)))
		_world.objects[id].description="%s. Вода у корней %d%%. Молодое дерево постепенно растёт, взрослое повторно плодоносит." % [view.label.text,roundi(float(t.water))]
	elif id==STORE_ID:
		var count:int=0
		for value in storage.values(): count+=int(value)
		_world.objects[id].description="Садовый ящик: %d предметов. Складывайте урожай, забирайте семена для посадок. Личные инструменты остаются в рюкзаке." % count


func _mat(key: String, color: Color) -> StandardMaterial3D:
	if not _materials.has(key):
		var material:=StandardMaterial3D.new()
		material.albedo_color=color
		material.roughness=1.0
		_materials[key]=material
	return _materials[key]


func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	var mesh:=BoxMesh.new()
	mesh.size=size
	node.mesh=mesh
	node.position=at
	node.material_override=material
	parent.add_child(node)
	return node


func _sphere(parent: Node3D, at: Vector3, radius: float, material: Material) -> void:
	var node:=MeshInstance3D.new()
	var mesh:=SphereMesh.new()
	mesh.radius=radius
	mesh.height=radius*2
	mesh.radial_segments=8
	mesh.rings=4
	node.mesh=mesh
	node.position=at
	node.material_override=material
	parent.add_child(node)


func _model(asset: String, parent: Node3D, at: Vector3, factor: Vector3) -> Node3D:
	if not _model_cache.has(asset): _model_cache[asset]=load(NATURE+asset+".glb") as PackedScene
	var packed:PackedScene=_model_cache[asset]
	var node:Node3D=packed.instantiate()
	node.position=at
	node.scale=factor
	node.set_meta("base_scale",factor)
	parent.add_child(node)
	return node


func _label(parent: Node3D, title: String, at: Vector3, color: Color, font_size: int) -> Label3D:
	var label:=Label3D.new()
	label.text=title
	label.position=at
	label.font_size=font_size
	label.pixel_size=.028
	label.modulate=color
	label.outline_size=6
	label.outline_modulate=Color(.10,.13,.08,.9)
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end=85
	parent.add_child(label)
	return label
