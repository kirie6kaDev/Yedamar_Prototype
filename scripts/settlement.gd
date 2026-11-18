extends Node3D

const BLUEPRINTS={
	"wall":{"name":"Стена · секция","cost":{"plank":3,"stone":2},"radius":1.4,"duration":35.0},
	"doorway":{"name":"Широкий дверной проём","cost":{"plank":4},"radius":1.8,"duration":35.0},
	"floor":{"name":"Дощатый пол · 4 × 4 м","cost":{"plank":4},"radius":1.5,"duration":25.0},
	"roof":{"name":"Навес крыши · 4 × 4 м","cost":{"plank":3,"hay":2},"radius":1.5,"duration":30.0},
	"bath":{"name":"Купальная бочка","cost":{"plank":5,"iron_ingot":1},"radius":1.2,"duration":45.0},
	"latrine":{"name":"Отхожее место","cost":{"plank":4,"wood":2},"radius":1.0,"duration":40.0},
	"hearth":{"name":"Домашний очаг","cost":{"stone":6,"wood":3},"radius":1.2,"duration":40.0},
	"bench":{"name":"Скамья для отдыха","cost":{"plank":3},"radius":1.0,"duration":25.0},
	"bookshelf":{"name":"Книжная полка","cost":{"plank":5},"radius":1.0,"duration":40.0},
	"training":{"name":"Учебное чучело","cost":{"wood":3,"hay":3},"radius":1.0,"duration":35.0},
	"dining":{"name":"Обеденный стол","cost":{"plank":4},"radius":1.2,"duration":35.0},
	"fence":{"name":"Ограда · секция","cost":{"branch":4,"wood":2},"radius":1.4,"duration":20.0},
	"shelter":{"name":"Простой навес","cost":{"log":4,"plank":4},"radius":3.2,"duration":65.0},
	"bed":{"name":"Лежанка","cost":{"wood":3,"hay":2},"radius":1.0,"duration":25.0},
	"storage":{"name":"Ящик для припасов","cost":{"plank":3},"radius":1.0,"duration":30.0},
	"workbench":{"name":"Плотницкий верстак","cost":{"log":3,"plank":2},"radius":1.6,"duration":45.0},
	"sawmill":{"name":"Ручная пилорама","cost":{"log":5,"plank":4,"iron_ingot":1},"radius":3.0,"duration":80.0},
	"smelter":{"name":"Плавильня","cost":{"stone":12,"wood":4},"radius":1.8,"duration":70.0},
	"anvil":{"name":"Наковальня","cost":{"iron_ingot":4,"log":1},"radius":1.4,"duration":55.0},
	"cauldron":{"name":"Котёл на очаге","cost":{"iron_ingot":2,"stone":4},"radius":1.5,"duration":40.0},
	"stable":{"name":"Конюшня","cost":{"log":8,"plank":8,"hay":4},"radius":4.0,"duration":100.0}
}
var game
var buildings:Dictionary={}
var companions:Dictionary={}
var zombies:Dictionary={}
var last_raid_day:=0
var next_build:=1
var next_zombie:=1
var focus_zombie:=""
var hero_attack:=0.0
var _ai_tick:=0.0

func configure(owner_game)->void:
	game=owner_game

func _ready()->void:
	_place_plain("bed","settlement_bed_0",Vector3(3995,0,4426),0)
	_place_plain("bed","settlement_bed_1",Vector3(3999,0,4426),0)
	_spawn_companion("comp_rada","Рада · лучница",Vector2(4021,4428),"guard",false)
	_spawn_companion("comp_lina","Лина · садовница",Vector2(4015,4428),"garden",false)
	_spawn_companion("comp_sten","Стэн · лесник",Vector2(4009,4428),"follow",false)
	_spawn_companion("watch_0","Страж фермы",Vector2(3981,4375),"guard",true)
	_spawn_companion("watch_1","Страж фермы",Vector2(4062,4415),"guard",true)

func _spawn_companion(id:String,title:String,xz:Vector2,task:String,permanent:bool)->void:
	var actor=game._actor("enemy",title,game._ground(xz))
	actor.role=id
	actor.max_health=100
	actor.health=100
	actor.set_meta("object_id",id)
	actor.collision_layer=2
	actor.move_speed=5.5
	var person:Dictionary=game.Campaign.character_state({"hoe":1,"seeds_carrot":12,"seeds_herb":8,"water":6,"ration":3},100)
	person["role"]=id
	person["sleep"]=100.0
	person["skills"]={}
	companions[id]={"actor":actor,"name":title,"task":task,"recruited":permanent,"permanent":permanent,"home":game._ground(xz),"person":person,"order":{},"cooldown":0.0}
	game.world.objects[id]={"id":id,"type":"companion","name":title,"description":"Можно пригласить в отряд и назначить работу, охрану или сопровождение.","position":actor.position,"approach":actor.position+Vector3(0,0,1.2),"node":actor}
	if task=="guard" or permanent: _bow(actor)

func _bow(actor)->void:
	var bow:=Node3D.new()
	actor._model.add_child(bow)
	bow.position=Vector3(.55,1.15,.3)
	for i in range(7):
		var angle:float=float(i)/6*PI
		_box(bow,Vector3(sin(angle)*.25,cos(angle)*.55,0),Vector3(.07,.19,.07),Color("#754b2e"))
	_box(bow,Vector3(0,0,0),Vector3(.018,1.1,.018),Color("#dace9e"))

func command(action:String,id:String)->void:
	if not companions.has(id): return
	var c:Dictionary=companions[id]
	if action=="recruit":
		c.recruited=true
		game._say(c.name,"Договорились. Назначь мне работу или пост в управлении хозяйством. Если нужно идти вместе — выбери сопровождение.")
	elif action=="dismiss" and not c.permanent:
		c.recruited=false
		c.actor.end_work()
		c.actor.stop_moving()
		c.order={}
	elif action.begins_with("assign_") and c.recruited:
		c.task=action.trim_prefix("assign_")
		c.order={}
		c.actor.end_work()
		c.actor.stop_moving()
		if c.task=="guard": c.home=c.actor.position

func ui_companions()->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	for id in companions:
		var c:Dictionary=companions[id]
		if c.permanent: continue
		rows.append({"id":id,"name":c.name,"health":c.actor.health,"sleep":c.person.sleep,"task":c.task,"recruited":c.recruited})
	return rows

func build_options(person:Dictionary)->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	for id in BLUEPRINTS:
		var def:Dictionary=BLUEPRINTS[id]
		var reason:=_materials(def.cost,person.inventory)
		rows.append({"id":id,"name":def.name,"cost":def.cost,"enabled":reason.is_empty(),"reason":reason})
	return rows

func _materials(cost:Dictionary,inv:Dictionary)->String:
	for item in cost:
		if int(inv.get(item,0))<int(cost[item]): return "Не хватает: "+str(game.Campaign.ITEMS.get(item,item))
	return ""

func can_place(kind:String,point:Vector3,role:String="",ignore_id:String="")->String:
	if not BLUEPRINTS.has(kind): return "Неизвестная постройка."
	if game.life:
		var ownership:String=game.life.can_build(point,role,kind)
		if not ownership.is_empty(): return ownership
	var p:=Vector2(point.x,point.z)
	if not game.world.bounds.grow(-12).has_point(p): return "За пределами игровой области."
	if game.world.sample_height(p.x,p.y)<1: return "Нельзя строить в воде."
	var radius:float=BLUEPRINTS[kind].radius
	if game.v5:
		for corner in [Vector3(radius,0,radius),Vector3(-radius,0,radius),Vector3(radius,0,-radius),Vector3(-radius,0,-radius)]:
			var boundary:String=game.life.can_build(point+corner,role,kind)
			if not boundary.is_empty(): return "Вся постройка должна помещаться внутри разрешённого участка."
	for offset in [Vector2(radius,0),Vector2(-radius,0),Vector2(0,radius),Vector2(0,-radius)]:
		if absf(game.world.sample_height(p.x+offset.x,p.y+offset.y)-point.y)>radius*.4: return "Слишком крутой склон."
	for obstacle in game.world.obstacles:
		if kind in ["floor","roof"] and (obstacle.has("settlement_id") or obstacle.has("industry_id")): continue
		if not ignore_id.is_empty() and (str(obstacle.get("settlement_id",""))==ignore_id or str(obstacle.get("industry_id",""))==ignore_id): continue
		if p.distance_to(Vector2(obstacle.position.x,obstacle.position.z))<float(obstacle.radius)+radius+.4: return "Здесь мешает дерево или постройка."
	for id in game.world.objects:
		if id==ignore_id: continue
		var obj:Dictionary=game.world.objects[id]
		if kind in ["floor","roof"] and (buildings.has(id) or game.industry._records.has(id)): continue
		if str(obj.type)=="plot": continue
		if obj.type in ["floor","roof"]: continue
		if obj.type in ["branch","stone","herb","mint","lavender","berry","carrot","hay","enemy","zombie"]: continue
		if (obj.node.visible or obj.type=="garden_plot") and p.distance_to(Vector2(obj.position.x,obj.position.z))<radius+maxf(1.1,float(obj.get("surface_radius",1.1)))+.3: return "Оставьте место для прохода и предметов."
	return ""

func build(kind:String,point:Vector3,rotation:float,person:Dictionary)->Dictionary:
	var reason:=can_place(kind,point,str(person.get("role",game.active.role)))
	if reason.is_empty(): reason=_materials(BLUEPRINTS[kind].cost,person.inventory)
	if not reason.is_empty(): return {"ok":false,"message":reason}
	var id:="built_"+str(next_build)
	var node:Node3D
	if kind in ["workbench","sawmill","smelter","anvil","cauldron"]:
		node=game.industry.place_station(kind,id,point,rotation)
		if node==null: return {"ok":false,"message":"Постройка здесь не помещается."}
	else:
		node=_place_plain(kind,id,point,rotation)
	for item in BLUEPRINTS[kind].cost:
		person.inventory[item]=int(person.inventory[item])-int(BLUEPRINTS[kind].cost[item])
	next_build+=1
	game._sync_navigation()
	return {"ok":true,"message":"Готово: "+str(BLUEPRINTS[kind].name),"skill":"carpentry","xp":20}

func _place_plain(kind:String,id:String,point:Vector3,rotation:float)->Node3D:
	var node:=Node3D.new()
	node.name=id
	game.world.add_child(node)
	node.position=game._ground(Vector2(point.x,point.z))
	node.rotation.y=rotation
	var timber:=Color("#866346")
	var canvas:=Color("#a6ad83")
	match kind:
		"wall":
			_box(node,Vector3(0,1.8,0),Vector3(3.8,3.6,.3),Color("#c2ac85"))
			for x in [-1.8,0,1.8]: _box(node,Vector3(x,1.8,.17),Vector3(.16,3.7,.18),timber)
		"doorway":
			for x in [-2.8,2.8]: _box(node,Vector3(x,1.8,0),Vector3(.3,3.6,.4),timber)
			_box(node,Vector3(0,3.6,0),Vector3(6,.3,.5),timber)
		"floor":
			for i in 8: _box(node,Vector3(-1.75+i*.5,.12,0),Vector3(.48,.16,4),timber.lightened(.12 if i%2 else 0))
		"roof":
			_box(node,Vector3(0,3.8,0),Vector3(4.2,.25,4.2),Color("#a4774f"))
		"bath","latrine","hearth","bench","bookshelf","training","dining":
			game.city.create_prop(kind,node)
		"fence":
			for x in [-1.25,1.25]: _box(node,Vector3(x,.85,0),Vector3(.16,1.7,.16),timber)
			for y in [.6,1.25]: _box(node,Vector3(0,y,0),Vector3(2.6,.14,.12),timber.lightened(.15))
		"shelter","stable":
			for x in [-2,2]:
				for z in [-1.6,1.6]: _box(node,Vector3(x,1.4,z),Vector3(.2,2.8,.2),timber)
			_box(node,Vector3(0,2.8,0),Vector3(4.8,.2,4.0),canvas)
			_box(node,Vector3(0,1.3,-1.6),Vector3(4.3,2.6,.12),canvas.darkened(.1))
			_box(node,Vector3(0,.25,0),Vector3(1.2,.5,2.1),Color("#b5ab70"))
			if kind=="stable":
				_box(node,Vector3(1.5,.6,1),Vector3(.8,.9,1.2),Color("#9c8053"))
				_box(node,Vector3(1.5,1.1,1),Vector3(.7,.2,1),Color("#cbbb70"))
		"bed":
			_box(node,Vector3(0,.2,0),Vector3(1.2,.4,2.1),timber)
			_box(node,Vector3(0,.44,0),Vector3(1.12,.14,2),Color("#c6b77f"))
			_box(node,Vector3(0,.56,-.7),Vector3(.9,.18,.35),canvas)
		"storage":
			_box(node,Vector3(0,.5,0),Vector3(1.4,1,1.1),timber)
			for y in [.1,.9]: _box(node,Vector3(0,y,0),Vector3(1.45,.12,1.15),Color("#c4a576"))
	var radius:float=BLUEPRINTS[kind].radius
	var body:=StaticBody3D.new()
	body.collision_layer=2
	body.collision_mask=0
	body.set_meta("object_id",id)
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(2.6,1.7,.4) if kind=="fence" else Vector3(radius*1.5,1.2,radius*1.5)
	shape.shape=box
	shape.position.y=box.size.y/2
	body.add_child(shape)
	node.add_child(body)
	var approach:Vector3=node.position+Vector3(0,0,radius+1.0).rotated(Vector3.UP,rotation)
	approach=game._ground(Vector2(approach.x,approach.z))
	game.world.objects[id]={"id":id,"type":"bed" if kind in ["bed","shelter"] else kind,"name":BLUEPRINTS[kind].name,"description":"Постройка хозяйства. Прочность: 100.","position":node.position,"approach":approach,"node":node,"surface_radius":radius}
	buildings[id]={"kind":kind,"position":[node.position.x,node.position.y,node.position.z],"rotation":rotation,"health":100.0,"storage":{}}
	if kind not in ["floor","roof","doorway"]: game.world.obstacles.append({"position":node.position,"radius":radius,"settlement_id":id})
	if game.life: game.life._register_building(id)
	return node

func _box(parent:Node3D,point:Vector3,size:Vector3,color:Color)->MeshInstance3D:
	var mesh:=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=size
	mesh.mesh=box
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=color
	mat.roughness=1
	mesh.material_override=mat
	mesh.position=point
	parent.add_child(mesh)
	return mesh

func tick(delta:float)->void:
	if game.caravan.is_night() and int(game.caravan.day_number)>last_raid_day:
		last_raid_day=game.caravan.day_number
		spawn_raid(3+mini(3,last_raid_day-1))
	if not game.caravan.is_night() and not zombies.is_empty():
		for id in zombies.keys(): _remove_zombie(id)
	_ai_tick-=delta
	if _ai_tick>0: return
	_ai_tick=.3
	_tick_companions(.3)
	_tick_zombies(.3)
	for id in companions:
		var c:Dictionary=companions[id]
		game.world.objects[id].position=c.actor.position
		game.world.objects[id].approach=c.actor.position+Vector3(0,0,1.2)

func spawn_raid(count:int)->void:
	# Night creatures inhabit remote places; peaceful homes are not a nightly arena.
	for i in range(count):
		var centers:Array[Vector2]=[Vector2(4350,3980),Vector2(3020,4200),Vector2(4650,4490)]
		var a:float=float(i)*2.4
		var point:Vector3=game._ground(centers[i%centers.size()]+Vector2(cos(a),sin(a))*18)
		_spawn_zombie("zombie_"+str(next_zombie),point,52.0)
		next_zombie+=1

func _spawn_zombie(id:String,point:Vector3,health:float)->void:
	var actor=game._actor("enemy","Ночной мертвец",point)
	actor.role="zombie"
	actor.move_speed=2.5
	actor.max_health=52
	actor.health=health
	actor.set_meta("object_id",id)
	actor.collision_layer=2
	for mesh in actor._model.find_children("*","MeshInstance3D",true,false):
		if not mesh.visible: continue
		var mat:=StandardMaterial3D.new()
		mat.albedo_color=Color("#6d8059") if "head" in str(mesh.name).to_lower() else Color("#4b5a49")
		mesh.material_override=mat
	zombies[id]={"actor":actor,"cooldown":0.0,"home":point}
	game.world.objects[id]={"id":id,"type":"zombie","name":"Ночной мертвец","description":"Обитает в дикой местности. Преследует замеченных путников, но избегает охраняемых поселений.","position":point,"approach":point,"node":actor}

func _tick_companions(delta:float)->void:
	for id in companions:
		var c:Dictionary=companions[id]
		var actor=c.actor
		if not c.recruited: continue
		if actor.health<=0:
			if not game.caravan.is_night():
				actor.health=60
				actor.position=c.home
			continue
		var nearest:=_nearest_zombie(actor.position,36)
		if not nearest.is_empty():
			if not actor._work_clip.is_empty(): actor.end_work()
			c.order={}
			actor.stop_moving()
			c.cooldown=float(c.cooldown)-delta
			if float(c.cooldown)<=0:
				c.cooldown=2.1 if c.task=="guard" else 3.5
				actor._model.rotation.y=atan2(zombies[nearest].actor.position.x-actor.position.x,zombies[nearest].actor.position.z-actor.position.z)
				actor.play_action("2H_Ranged_Shoot")
				_projectile(actor.position+Vector3.UP*1.4,zombies[nearest].actor.position+Vector3.UP)
				_damage_zombie(nearest,14 if c.task=="guard" else 7)
			c.person.sleep=maxf(0,float(c.person.sleep)-delta*.07)
			continue
		if game.caravan.is_night() and c.task!="guard":
			actor.begin_work("Lie_Idle")
			c.person.sleep=minf(100,float(c.person.sleep)+delta*.4)
			continue
		if not game.caravan.is_night() and c.task=="guard" and float(c.person.sleep)<80:
			actor.begin_work("Sit_Floor_Idle")
			c.person.sleep=minf(100,float(c.person.sleep)+delta*.3)
			continue
		if not actor._work_clip.is_empty() and c.order.is_empty(): actor.end_work()
		c.person.sleep=maxf(0,float(c.person.sleep)-delta*.055)
		c.person["position"]=actor.position
		if c.task=="garden":
			_npc_garden(c,delta)
		elif c.task=="follow":
			if game._flat_distance(actor.position,game.active.position)>7 and not actor.is_moving(): actor.navigate_to(game.active.position+Vector3(3,0,2))
		elif c.task=="guard" and game._flat_distance(actor.position,c.home)>3 and not actor.is_moving(): actor.navigate_to(c.home)

func _npc_garden(c:Dictionary,delta:float)->void:
	if c.order.is_empty():
		var plan:Array=game.farm.plan_work(c.person,false)
		if plan.is_empty(): return
		c.order=plan[0].duplicate(true)
		c.order.phase="waiting"
	var order:Dictionary=c.order
	if not game.world.objects.has(order.id):
		c.order={}
		return
	var target:Vector3=game.world.objects[order.id].approach
	var actor=c.actor
	if game._flat_distance(actor.position,target)>1.4:
		if not actor.is_moving() and not actor.navigate_to(target): c.order={}
		return
	if order.phase=="waiting":
		actor.stop_moving()
		order.phase="working"
		order.remaining=4.0 if order.action=="fill" else game.farm.duration(order.action,order.id)
		actor.begin_work("interact")
	order.remaining=float(order.remaining)-delta
	if float(order.remaining)>0: return
	actor.end_work()
	if order.action=="fill":
		c.person.inventory.water=int(c.person.inventory.get("water",0))+8
	else:
		var result:Dictionary=game.farm.complete(order.action,order.id,c.person)
		if result.get("ok",false):
			var skill:=str(result.get("skill","farming"))
			c.person.skills[skill]=float(c.person.skills.get(skill,0))+float(result.get("xp",0))
	c.order={}

func _nearest_zombie(point:Vector3,limit:float)->String:
	var found:=""
	for id in zombies:
		var distance:float=game._flat_distance(point,zombies[id].actor.position)
		if distance<limit:
			limit=distance
			found=id
	return found

func hero_threat()->bool:
	return not _nearest_zombie(game.brother.position,16).is_empty() or zombies.has(focus_zombie)

func _tick_zombies(delta:float)->void:
	for id in zombies.keys():
		if not zombies.has(id): continue
		var z:Dictionary=zombies[id]
		var actor=z.actor
		var target=game.brother
		var nearest:float=game._flat_distance(actor.position,target.position)
		for c in companions.values():
			if not c.recruited or c.actor.health<=0: continue
			var distance:float=game._flat_distance(actor.position,c.actor.position)
			if distance<nearest:
				nearest=distance
				target=c.actor
		z.cooldown=float(z.cooldown)-delta
		var den:Vector3=z.get("home",actor.position)
		if nearest>38 or game._flat_distance(actor.position,den)>90 or (game.life and game.life.is_safe(target.position)):
			if game._flat_distance(actor.position,den)>4 and not actor.is_moving(): actor.navigate_to(den)
			continue
		if nearest<2.5 and float(z.cooldown)<=0:
			actor.stop_moving()
			actor.play_action("attack")
			var protected:bool=target==game.brother and game.state.characters.brother.get("armor_equipped",false) and int(game._inventory("brother").get("iron_armor",0))>0
			target.health-=(3 if protected else 5)*(game.v5.activities.damage_multiplier(str(target.role)) if game.v5 and game.state.characters.has(target.role) else 1.0)
			z.cooldown=2.4
		elif not actor.is_moving() and nearest>2.5:
			if not actor.navigate_to(target.position): _attack_fence(actor,delta)
		game.world.objects[id].position=actor.position
		game.world.objects[id].approach=actor.position
	if hero_threat():
		game._begin_combat()
		hero_attack-=delta
		var target_id:=focus_zombie if zombies.has(focus_zombie) else _nearest_zombie(game.brother.position,18)
		if target_id.is_empty() or float(game.state.elapsed)<game.retreat_until: return
		var target=zombies[target_id].actor
		if game._flat_distance(game.brother.position,target.position)>3:
			if not game.brother.is_moving(): game.brother.navigate_to(target.position)
		elif hero_attack<=0:
			game.brother.stop_moving()
			game.brother.play_action("attack")
			hero_attack=1.2
			var item:String=game.state.characters.brother.equipped
			_damage_zombie(target_id,30 if item=="iron_sword" else (20 if item=="sword" else 9))
			game.state.characters.brother.stamina=maxf(0,game.state.characters.brother.stamina-1.4)

func _attack_fence(actor,delta:float)->void:
	for id in buildings:
		if buildings[id].kind!="fence" or float(buildings[id].health)<=0: continue
		if game._flat_distance(actor.position,game.world.objects[id].position)<5:
			buildings[id].health=maxf(0,float(buildings[id].health)-delta*4)
			if buildings[id].health<=0:
				game.world.objects[id].node.hide()
				game._disable_clicks(game.world.objects[id].node,false)
				game.world.obstacles=game.world.obstacles.filter(func(o):return o.get("settlement_id","")!=id)
				game._sync_navigation()
			return

func _damage_zombie(id:String,damage:float)->void:
	if not zombies.has(id): return
	zombies[id].actor.health-=damage
	if zombies[id].actor.health<=0:
		_remove_zombie(id)
		game.sound.effect("hit")

func _remove_zombie(id:String)->void:
	zombies[id].actor.queue_free()
	zombies.erase(id)
	game.world.objects.erase(id)
	if focus_zombie==id: focus_zombie=""

func _projectile(from:Vector3,to:Vector3)->void:
	var arrow:=_box(self,from,Vector3(.045,.045,.8),Color("#dccaa1"))
	arrow.look_at(to)
	var tween:=create_tween()
	tween.tween_property(arrow,"position",to,maxf(.08,from.distance_to(to)/38))
	tween.tween_callback(arrow.queue_free)

func snapshot()->Dictionary:
	var data:Dictionary={"buildings":buildings.duplicate(true),"companions":{},"zombies":{},"last_raid_day":last_raid_day,"next_build":next_build,"next_zombie":next_zombie,"focus_zombie":focus_zombie,"hero_attack":hero_attack}
	for id in companions:
		var c:Dictionary=companions[id]
		var person:Dictionary=c.person.duplicate(true)
		person.erase("position")
		data.companions[id]={"person":person,"health":c.actor.health,"position":game._vector(c.actor.position),"home":game._vector(c.home),"task":c.task,"recruited":c.recruited}
	for id in zombies:
		data.zombies[id]={"position":game._vector(zombies[id].actor.position),"health":zombies[id].actor.health}
	return data

func clear_buildings()->void:
	for id in buildings.keys():
		if game.world.objects.has(id):
			game._disable_clicks(game.world.objects[id].node,false)
			game.world.objects[id].node.queue_free()
			game.world.objects.erase(id)
	buildings.clear()
	game.world.obstacles=game.world.obstacles.filter(func(o):return not o.has("settlement_id"))

func restore(data:Dictionary)->void:
	clear_buildings()
	for id in data.get("buildings",{}):
		var b:Dictionary=data.buildings[id]
		if not BLUEPRINTS.has(b.get("kind","")) or not game._valid_vector(b.get("position")): continue
		_place_plain(b.kind,id,game._decode_position(b.position),float(b.get("rotation",0)))
		buildings[id].health=clampf(float(b.get("health",100)),0,100)
		buildings[id].storage=b.get("storage",{}).duplicate(true)
		if buildings[id].health<=0:
			game.world.objects[id].node.hide()
			game._disable_clicks(game.world.objects[id].node,false)
			game.world.obstacles=game.world.obstacles.filter(func(o):return o.get("settlement_id","")!=id)
	for id in data.get("companions",{}):
		if not companions.has(id): continue
		var saved:Dictionary=data.companions[id]
		var c:Dictionary=companions[id]
		c.actor.end_work()
		c.actor.stop_moving()
		c.order={}
		c.actor.health=clampf(float(saved.get("health",100)),0,100)
		if game._valid_vector(saved.get("position")): c.actor.position=game._decode_position(saved.position)
		if game._valid_vector(saved.get("home")): c.home=game._decode_position(saved.home)
		c.task=saved.get("task",c.task)
		c.recruited=bool(saved.get("recruited",false)) or c.permanent
		if saved.get("person") is Dictionary:
			c.person=game.Campaign.character_state({},c.actor.health)
			c.person.merge(saved.person.duplicate(true),true)
			c.person["role"]=id
	for id in zombies.keys(): _remove_zombie(id)
	for id in data.get("zombies",{}):
		var z:Dictionary=data.zombies[id]
		if game._valid_vector(z.get("position")): _spawn_zombie(id,game._decode_position(z.position),float(z.get("health",52)))
	last_raid_day=int(data.get("last_raid_day",0))
	next_build=maxi(1,int(data.get("next_build",1)))
	next_zombie=maxi(1,int(data.get("next_zombie",1)))
	for id in game.world.objects:
		if str(id).begins_with("built_"): next_build=maxi(next_build,str(id).trim_prefix("built_").to_int()+1)
		if str(id).begins_with("zombie_"): next_zombie=maxi(next_zombie,str(id).trim_prefix("zombie_").to_int()+1)
	focus_zombie=str(data.get("focus_zombie",""))
	hero_attack=float(data.get("hero_attack",0))
