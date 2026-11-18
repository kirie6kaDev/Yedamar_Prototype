extends Node3D
## Domestic animals are persistent world entities, independent of character slots.
## The game calls tick(); this module never clears or rewrites a hero's action queue.

signal notice(message: String)
signal mounted_changed(role: String, mounted: bool)

const MAX_ANIMALS := 16
const ADULT_AGE := 600.0
const GESTATION := 180.0
const SPECIES := {
	"horse":{"name":"Лошадь","diet":["hay","carrot","apple"],"price":80,"speed":8.0,"produce":"","interval":0.0},
	"sheep":{"name":"Овца","diet":["hay","carrot"],"price":26,"speed":1.5,"produce":"wool","interval":300.0},
	"goat":{"name":"Коза","diet":["hay","carrot","apple"],"price":30,"speed":1.8,"produce":"milk","interval":240.0},
	"chicken":{"name":"Курица","diet":["wheat","seeds_carrot"],"price":8,"speed":1.1,"produce":"egg","interval":180.0},
	"dog":{"name":"Собака","diet":["meat","ration"],"price":0,"speed":3.2,"produce":"","interval":0.0},
}
const LABELS := {
	"ranch_feed":"Покормить", "ranch_water":"Напоить · 1 вода", "ranch_collect":"Забрать продукцию",
	"ranch_buy":"Купить животное", "ranch_adopt":"Принять в семью · корм", "ranch_tame":"Приручить · 3 корма",
	"ranch_breed":"Подготовить пару к размножению", "ranch_mount":"Сесть верхом", "ranch_unmount":"Спешиться",
	"ranch_pet":"Приласкать", "ranch_follow":"Следовать / остаться", "ranch_heal":"Перевязать · 1 повязка", "ranch_bury":"Убрать погибшее животное",
}
const FOOD_NAMES := {"hay":"сено","carrot":"морковь","apple":"яблоки","wheat":"зерно","seeds_carrot":"семена","meat":"мясо","ration":"дорожная еда"}

var animals: Dictionary = {}
var _game: Node
var _world: Node3D
var _nav: RefCounted
var _nodes: Dictionary = {}
var _visuals: Dictionary = {}
var _legs: Dictionary = {}
var _horse_players: Dictionary = {}
var _labels: Dictionary = {}
var _roam_paths: Dictionary = {}
var _roam_indices: Dictionary = {}
var _waits: Dictionary = {}
var _materials: Dictionary = {}
var _built := false
var _clock := 0.0
var _next_id := 1
var _rider_role := ""
var _mount_id := ""
var _rider: Node3D
var _rider_physics := true
var _ride_route := PackedVector3Array()
var _ride_cursor := 0
var _ride_target := Vector3.ZERO
var _status_clock := 0.0
var _pending_restore: Dictionary = {}
var _initial_snapshot: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func configure(game: Node) -> void:
	_game = game
	_world = game.get("world") as Node3D
	_nav = game.get("navigation") as RefCounted
	if is_node_ready():
		_build()

func _ready() -> void:
	if _game:
		_build()

func _build() -> void:
	if _built or not _world or not _nav:
		return
	_built = true
	_rng.seed = 826311
	_add_initial("ranch_horse_1","horse","Каштан",Vector2(3754,4026),"male","stable")
	_add_initial("ranch_horse_2","horse","Ивушка",Vector2(3766,4026),"female","stable")
	_add_initial("ranch_sheep_1","sheep","Пушинка",Vector2(3680,4073),"female","village")
	_add_initial("ranch_sheep_2","sheep","Баран Ярко",Vector2(3688,4073),"male","village")
	_add_initial("ranch_goat_1","goat","Белянка",Vector2(3700,4078),"female","village")
	_add_initial("ranch_goat_2","goat","Козёл Рыжик",Vector2(3708,4078),"male","village")
	_add_initial("ranch_chicken_1","chicken","Пеструшка",Vector2(3723,4075),"female","village")
	_add_initial("ranch_chicken_2","chicken","Петух Зорик",Vector2(3728,4075),"male","village")
	_add_initial("ranch_dog_1","dog","Бродяга",Vector2(3738,4083),"male","")
	_initial_snapshot=snapshot()
	if not _pending_restore.is_empty():
		var pending := _pending_restore
		_pending_restore = {}
		restore(pending)

func _add_initial(id: String, species: String, title: String, p: Vector2, sex: String, owner: String) -> void:
	var at := _safe_point(p)
	var record := _new_record(id,species,title,at,sex,owner,ADULT_AGE*2)
	animals[id] = record
	_create_node(id)

func _new_record(id: String, species: String, title: String, at: Vector3, sex: String, owner: String, age: float) -> Dictionary:
	return {"id":id,"species":species,"name":title,"position":_array(at),"home":_array(at),"sex":sex,"owner":owner,"food":85.0,"water":85.0,"health":100.0,"stamina":100.0,"bond":0.0,"age":age,"heading":0.0,"produce":str(SPECIES[species].produce),"stock":0,"production":0.0,"gestation":0.0,"breed_cooldown":0.0,"follow_role":"","status":"Отдыхает"}

func owns(id: String) -> bool:
	return animals.has(id)

func get_animals() -> Dictionary:
	return animals.duplicate(true)

func is_mounted(role: String = "") -> bool:
	return not _mount_id.is_empty() and (role.is_empty() or role==_rider_role)

func mounted_role() -> String:
	return _rider_role

func mount_id() -> String:
	return _mount_id

func is_moving() -> bool:
	return is_mounted() and _ride_cursor < _ride_route.size()

func get_animal_position(id: String = "") -> Vector3:
	var chosen := _mount_id if id.is_empty() else id
	return _vector(animals[chosen].position) if animals.has(chosen) else Vector3.ZERO

func actions(id: String, person: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not owns(id):
		return result
	var a: Dictionary = animals[id]
	var names: Array[String] = []
	if float(a.health)<=0:
		names.append("ranch_bury")
	else:
		names.append_array(["ranch_feed","ranch_water","ranch_pet"])
		if str(a.owner) not in ["house_player", ""]:
			names.append("ranch_buy")
		elif str(a.owner).is_empty():
			names.append("ranch_adopt" if a.species=="dog" else "ranch_tame")
		else:
			if not str(a.produce).is_empty():
				names.append("ranch_collect")
			names.append_array(["ranch_heal","ranch_breed"])
			if a.species=="horse":
				names.append("ranch_unmount" if id==_mount_id else "ranch_mount")
			if a.species=="dog":
				names.append("ranch_follow")
	for action: String in names:
		var candidate := person.duplicate(false)
		candidate.erase("position")
		var reason := validate(action,id,candidate)
		var title := str(LABELS[action])
		if action=="ranch_buy":
			title += " · %d монет" % int(SPECIES[a.species].price)
		if action=="ranch_collect":
			title += " · %d" % int(a.stock)
		result.append({"id":action,"label":title,"enabled":reason.is_empty(),"reason":reason})
	return result

func duration(action: String, _id: String = "") -> float:
	match action:
		"ranch_breed": return 12.0
		"ranch_tame": return 10.0
		"ranch_collect": return 6.0
		"ranch_bury": return 8.0
		"ranch_feed","ranch_water","ranch_adopt","ranch_heal": return 4.0
		_: return 2.0

func hold(id: String, seconds: float) -> void:
	if not animals.has(id): return
	_waits[id]=maxf(float(_waits.get(id,0)),seconds)
	_roam_paths.erase(id)
	_roam_indices.erase(id)
	if id==_mount_id: stop_moving()

func validate(action: String, id: String, person: Dictionary) -> String:
	if not owns(id) or not LABELS.has(action):
		return "Это действие не относится к животному."
	if not person.get("inventory",{}) is Dictionary:
		return "Нет доступного личного рюкзака."
	var a: Dictionary = animals[id]
	var inv: Dictionary = person.get("inventory",{})
	var role := str(person.get("role",person.get("id","brother")))
	if action=="ranch_bury":
		return "" if float(a.health)<=0 else "Животное живо."
	if float(a.health)<=0:
		return "Животное погибло."
	if person.has("position") and action!="ranch_unmount":
		var at: Vector3 = person.position if person.position is Vector3 else _vector(person.position)
		if Vector2(at.x,at.z).distance_to(Vector2(float(a.position[0]),float(a.position[2])))>4.5:
			return "Подойдите к животному."
	if action in ["ranch_collect","ranch_heal","ranch_breed","ranch_mount","ranch_unmount","ranch_follow"] and str(a.owner)!="house_player":
		return "Сначала приобретите это животное."
	match action:
		"ranch_feed":
			if float(a.food)>=98: return "Животное сыто."
			if _food_count(inv,str(a.species))<1:
				var names: Array[String] = []
				for item: String in SPECIES[a.species].diet: names.append(str(FOOD_NAMES.get(item,item)))
				return "Подходящий корм: "+", ".join(names)
		"ranch_water":
			if float(a.water)>=98: return "Животное уже напоено."
			if int(inv.get("water",0))<1: return "Нужна вода из колодца."
		"ranch_collect":
			if int(a.stock)<1: return "Продукция ещё не готова."
		"ranch_buy":
			if str(a.owner) in ["house_player",""]: return "Это животное не продаётся."
			if not person.get("wallet",{}) is Dictionary or int(person.get("wallet",{}).get("coins",0))<int(SPECIES[a.species].price): return "В семейном кошельке не хватает монет."
		"ranch_adopt","ranch_tame":
			if not str(a.owner).is_empty(): return "У животного уже есть хозяин."
			if action=="ranch_adopt" and a.species!="dog": return "Этому животному нужно приручение."
			if _food_count(inv,str(a.species)) < (1 if action=="ranch_adopt" else 3): return "Нужен подходящий корм для знакомства."
		"ranch_heal":
			if float(a.health)>=98: return "Животное здорово."
			if int(inv.get("bandage",0))<1: return "Нужна повязка."
		"ranch_breed":
			if animals.size()+_pregnancies()>=MAX_ANIMALS: return "Для нового приплода нет места (предел 16)."
			if float(a.age)<ADULT_AGE: return "Животное ещё не выросло."
			if float(a.gestation)>0 or float(a.breed_cooldown)>0: return "Паре пока нужен отдых."
			if minf(float(a.food),minf(float(a.water),float(a.health)))<60: return "Сначала накормите, напоите и вылечите животное."
			if _find_mate(id).is_empty(): return "Рядом нужна здоровая взрослая пара того же вида, принадлежащая семье."
			if _food_count(inv,str(a.species))<2: return "Нужны ещё 2 порции корма для пары."
		"ranch_mount":
			if a.species!="horse": return "На это животное нельзя сесть верхом."
			if float(a.age)<ADULT_AGE: return "Жеребёнок ещё не вырос."
			if _stage(person) in ["infant","toddler","child"]: return "Ребёнок может ухаживать за лошадью; верховая езда доступна с подросткового возраста."
			if is_mounted(): return "Сначала спешьтесь с другой лошади."
			if _combat(role): return "Во время боя сначала отойдите в безопасное место."
			if _caravan_controls(role): return "Сначала выйдите из повозки."
			if float(a.stamina)<10 or float(a.food)<10 or float(a.water)<10: return "Лошади нужны корм, вода и отдых."
		"ranch_unmount":
			if id!=_mount_id or role!=_rider_role: return "Этот герой сейчас не верхом."
		"ranch_follow":
			if a.species!="dog": return "Следовать за героем может домашняя собака."
	return ""

func complete(action: String, id: String, person: Dictionary) -> Dictionary:
	var reason := validate(action,id,person)
	if not reason.is_empty():
		return {"ok":false,"message":reason}
	var a: Dictionary = animals[id]
	var inv: Dictionary = person.get("inventory",{})
	var role := str(person.get("role",person.get("id","brother")))
	var result := {"ok":true,"message":"","skill":"animal_husbandry","xp":8}
	match action:
		"ranch_feed":
			_consume_food(inv,str(a.species),1)
			a.food=minf(100,float(a.food)+38)
			a.bond=minf(100,float(a.bond)+5)
			result.message="Животное накормлено."
		"ranch_water":
			_take(inv,"water",1)
			a.water=minf(100,float(a.water)+48)
			result.message="Животное напоено."
		"ranch_collect":
			var item := str(a.produce)
			var count := int(a.stock)
			inv[item]=int(inv.get(item,0))+count
			a.stock=0
			result.merge({"message":"Продукция собрана.","item":item,"count":count,"xp":12},true)
		"ranch_buy":
			var wallet: Dictionary = person.wallet
			wallet.coins=int(wallet.coins)-int(SPECIES[a.species].price)
			a.owner="house_player"
			result.message=str(a.name)+" теперь принадлежит вашему хозяйству."
		"ranch_adopt","ranch_tame":
			_consume_food(inv,str(a.species),1 if action=="ranch_adopt" else 3)
			a.owner="house_player"
			a.bond=maxf(35,float(a.bond))
			a.food=minf(100,float(a.food)+30)
			result.message=str(a.name)+" доверяет вам."
			result.xp=20
		"ranch_heal":
			_take(inv,"bandage",1)
			a.health=minf(100,float(a.health)+35)
			result.message="Раны животного перевязаны."
		"ranch_breed":
			var mate_id := _find_mate(id)
			_consume_food(inv,str(a.species),2)
			var mate: Dictionary = animals[mate_id]
			var mother: Dictionary = a if a.sex=="female" else mate
			mother.gestation=GESTATION
			a.breed_cooldown=600.0
			mate.breed_cooldown=600.0
			a.food=maxf(0,float(a.food)-12)
			mate.food=maxf(0,float(mate.food)-12)
			result.message="Пара подготовлена. За приплодом нужно будет ухаживать."
			result.xp=20
		"ranch_mount":
			if not _mount(id,role): return {"ok":false,"message":"Не удалось посадить героя."}
			result.message="Вы верхом. Щёлкните по земле, чтобы ехать; действие «Спешиться» вернёт обычную очередь."
			result["mounted"]=true
		"ranch_unmount":
			dismount_all()
			result.message="Вы спешились."
			result["mounted"]=false
		"ranch_pet":
			a.bond=minf(100,float(a.bond)+12)
			a.stamina=minf(100,float(a.stamina)+5)
			if person.has("fun"): person.fun=minf(100,float(person.fun)+6)
			result.message="Животное спокойно рядом с вами."
		"ranch_follow":
			a.follow_role="" if str(a.follow_role)==role else role
			result.message="Собака останется во дворе." if str(a.follow_role).is_empty() else "Собака будет идти за вами."
		"ranch_bury":
			_remove_animal(id)
			result.message="Вы убрали погибшее животное."
	if animals.has(id):
		_waits[id]=3.0
		_roam_paths.erase(id)
		_update_status(id)
	return result

func _stage(person: Dictionary) -> String:
	if person.has("stage"):
		return str(person.stage)
	var role := str(person.get("role","brother"))
	if _game and _game.get("life"):
		var life: Node = _game.get("life")
		var sim: RefCounted = life.get("sim")
		if sim and sim.get("residents").has(role):
			return str(sim.get("residents")[role].get("stage","adult"))
	return "child" if role=="sister" else "adult"

func _food_count(inventory: Dictionary, species: String) -> int:
	var count := 0
	for item: String in SPECIES[species].diet:
		count += maxi(0,int(inventory.get(item,0)))
	return count

func _consume_food(inventory: Dictionary, species: String, count: int) -> void:
	var remaining := count
	for item: String in SPECIES[species].diet:
		var amount := mini(remaining,maxi(0,int(inventory.get(item,0))))
		_take(inventory,item,amount)
		remaining -= amount
		if remaining<=0:
			return

func _take(inventory: Dictionary, item: String, count: int) -> void:
	if count<=0:
		return
	var amount := int(inventory.get(item,0))-count
	if amount<=0:
		inventory.erase(item)
	else:
		inventory[item]=amount

func _find_mate(id: String) -> String:
	var a: Dictionary = animals[id]
	for other_id: String in animals:
		if other_id==id: continue
		var b: Dictionary = animals[other_id]
		if a.species!=b.species or a.sex==b.sex or b.owner!="house_player" or float(b.age)<ADULT_AGE: continue
		if float(b.gestation)>0 or float(b.breed_cooldown)>0 or minf(float(b.food),minf(float(b.water),float(b.health)))<60: continue
		if _vector(a.position).distance_to(_vector(b.position))<=35:
			return other_id
	return ""

func _pregnancies() -> int:
	var count := 0
	for a: Dictionary in animals.values():
		if float(a.gestation)>0: count+=1
	return count

func tick(delta: float) -> void:
	if not _built or delta<=0:
		return
	_clock += delta
	_status_clock -= delta
	if is_mounted() and _combat():
		dismount_all()
	if is_mounted() and not is_instance_valid(_rider):
		_bind_rider()
	for id: String in animals.keys():
		_tick_animal(id,delta)
	if is_mounted():
		_tick_ride(delta)
		_position_rider()
	if _status_clock<=0:
		_status_clock=.5
		for id: String in animals:
			_update_status(id)

func _tick_animal(id: String, delta: float) -> void:
	var a: Dictionary = animals[id]
	if float(a.health)<=0:
		a.status="Погибло"
		return
	a.age=float(a.age)+delta
	a.food=maxf(0,float(a.food)-delta*.022)
	a.water=maxf(0,float(a.water)-delta*.027)
	a.breed_cooldown=maxf(0,float(a.breed_cooldown)-delta)
	if float(a.food)<=0 or float(a.water)<=0:
		a.health=maxf(0,float(a.health)-delta*.045)
	elif float(a.food)>50 and float(a.water)>50:
		a.health=minf(100,float(a.health)+delta*.006)
	if id!=_mount_id:
		a.stamina=minf(100,float(a.stamina)+delta*.25)
	if float(a.health)<=0:
		if id==_mount_id: dismount_all()
		return
	if float(a.gestation)>0:
		a.gestation=maxf(0,float(a.gestation)-delta)
		if float(a.gestation)<=0:
			if animals.size()<MAX_ANIMALS:
				_birth(id)
			else:
				a.gestation=.1
	var interval := float(SPECIES[a.species].interval)
	var fertile := str(a.species)=="sheep" or str(a.sex)=="female"
	if interval>0 and fertile and float(a.age)>=ADULT_AGE and float(a.food)>25 and float(a.water)>25 and float(a.health)>35 and int(a.stock)<6:
		a.production=float(a.production)+delta
		while float(a.production)>=interval and int(a.stock)<6:
			a.production=float(a.production)-interval
			a.stock=int(a.stock)+1
	var size := lerpf(.55,1.0,clampf(float(a.age)/ADULT_AGE,0,1))
	if _visuals.has(id):
		(_visuals[id] as Node3D).scale=Vector3.ONE*size
	if id!=_mount_id:
		_wander(id,delta)

func _birth(mother_id: String) -> void:
	var mother: Dictionary = animals[mother_id]
	var id := "ranch_born_%d"%_next_id
	while animals.has(id):
		_next_id+=1
		id="ranch_born_%d"%_next_id
	_next_id+=1
	var at := _safe_point(Vector2(float(mother.position[0])+2,float(mother.position[2])+2))
	var species := str(mother.species)
	animals[id]=_new_record(id,species,str(SPECIES[species].name)+" · детёныш",at,"female" if _next_id%2==0 else "male",str(mother.owner),0.0)
	_create_node(id)
	notice.emit("В хозяйстве появился приплод: "+str(SPECIES[species].name).to_lower()+".")

func _wander(id: String, delta: float) -> void:
	var a: Dictionary = animals[id]
	var path: PackedVector3Array = _roam_paths.get(id,PackedVector3Array())
	var cursor := int(_roam_indices.get(id,0))
	var moving := false
	if cursor<path.size():
		var speed := float(SPECIES[a.species].speed)*.6
		moving=_move_step(id,path[cursor],speed*delta)
		if get_animal_position(id).distance_to(path[cursor])<.25:
			_roam_indices[id]=cursor+1
		if not moving:
			_roam_paths.erase(id)
			_waits[id]=2.0
	else:
		_waits[id]=float(_waits.get(id,0))-delta
		if float(_waits[id])<=0:
			var target := _vector(a.home)
			var follow := str(a.follow_role)
			if not follow.is_empty() and _hero(follow):
				target=(_hero(follow) as Node3D).global_position
				if get_animal_position(id).distance_to(target)<3.5:
					_waits[id]=1.5
					_animate(id,false,delta)
					return
				target += Vector3(-2,0,-2)
			else:
				var angle := _rng.randf()*TAU
				target += Vector3(sin(angle),0,cos(angle))*_rng.randf_range(2,7)
			target=_ground(Vector2(target.x,target.z))
			if _nav.is_walkable(Vector2(target.x,target.z)):
				var candidate: PackedVector3Array = _nav.path(get_animal_position(id),target)
				if not candidate.is_empty() and candidate[-1].distance_to(target)<2.0:
					_roam_paths[id]=candidate
					_roam_indices[id]=0
			_waits[id]=_rng.randf_range(4,10)
	a.status="Бродит по двору" if moving else "Отдыхает"
	_animate(id,moving,delta)

func move_target(point: Vector3) -> bool:
	if not is_mounted() or not animals.has(_mount_id) or _combat():
		return false
	var a: Dictionary = animals[_mount_id]
	if float(a.stamina)<2 or float(a.food)<5 or float(a.water)<5:
		notice.emit("Лошади нужны отдых, корм и вода.")
		return false
	var target := _ground(Vector2(point.x,point.z))
	if not _nav.is_walkable(Vector2(target.x,target.z)):
		notice.emit("Лошадь не может пройти в воду, на крутой склон или сквозь препятствие.")
		return false
	var route: PackedVector3Array = _nav.path(get_animal_position(),target)
	if route.is_empty() or route[-1].distance_to(target)>2.5:
		notice.emit("До выбранного места нет проходимого пути.")
		return false
	_ride_target=target
	_ride_route=route
	_ride_cursor=0
	return true

func stop_moving() -> void:
	_ride_route.clear()
	_ride_cursor=0

func _tick_ride(delta: float) -> void:
	if not animals.has(_mount_id):
		dismount_all()
		return
	var a: Dictionary = animals[_mount_id]
	var moving := is_moving()
	if moving and (float(a.stamina)<1 or float(a.food)<3 or float(a.water)<3):
		stop_moving()
		notice.emit("Лошадь остановилась: ей нужен отдых и уход.")
		moving=false
	if moving:
		var at := get_animal_position()
		var target: Vector3 = _ride_route[_ride_cursor]
		var horizontal := Vector2(target.x-at.x,target.z-at.z).length()
		var slope := absf(target.y-at.y)/maxf(horizontal,.1)
		var speed := 8.0 if float(a.stamina)>25 else 3.8
		speed *= clampf(1.0-slope*.7,.45,1.0)
		if not _move_step(_mount_id,target,speed*delta):
			stop_moving()
			notice.emit("Путь перекрыт. Выберите другую точку.")
			moving=false
		elif get_animal_position().distance_to(target)<.30:
			_ride_cursor+=1
		a.stamina=maxf(0,float(a.stamina)-delta*.20)
		a.food=maxf(0,float(a.food)-delta*.018)
		a.water=maxf(0,float(a.water)-delta*.024)
	else:
		a.stamina=minf(100,float(a.stamina)+delta*.30)
	a.status="Верховая поездка" if moving else "Под седлом · отдыхает"
	_animate(_mount_id,moving,delta)

func _move_step(id: String, destination: Vector3, distance: float) -> bool:
	var old := get_animal_position(id)
	var delta := Vector3(destination.x-old.x,0,destination.z-old.z)
	if delta.length()<.12:
		animals[id].position=_array(_ground(Vector2(destination.x,destination.z)))
		(_nodes[id] as Node3D).position=_vector(animals[id].position)
		return true
	var next := old+delta.normalized()*minf(distance,delta.length())
	if not _nav._clear(Vector2(old.x,old.z),Vector2(next.x,next.z)):
		return false
	next.y=float(_world.sample_height(next.x,next.z))
	var node: Node3D = _nodes[id]
	node.position=next
	node.rotation.y=lerp_angle(node.rotation.y,atan2(delta.x,delta.z),.22)
	animals[id].position=_array(next)
	animals[id].heading=node.rotation.y
	return true

func _mount(id: String, role: String) -> bool:
	var actor := _hero(role)
	if not is_instance_valid(actor):
		return false
	_mount_id=id
	_rider_role=role
	_rider=actor
	_rider_physics=actor.is_physics_processing()
	_roam_paths.erase(id)
	_roam_indices.erase(id)
	actor.stop_moving()
	actor.begin_work("Sit_Chair_Idle")
	actor.set_physics_process(false)
	animals[id].status="Под седлом · отдыхает"
	_position_rider()
	_update_status(id)
	mounted_changed.emit(role,true)
	return true

func _bind_rider() -> void:
	if _rider_role.is_empty() or not animals.has(_mount_id):
		return
	var actor := _hero(_rider_role)
	if is_instance_valid(actor):
		_rider=actor
		actor.stop_moving()
		actor.begin_work("Sit_Chair_Idle")
		actor.set_physics_process(false)
		_position_rider()

func _position_rider() -> void:
	if not is_instance_valid(_rider) or not _nodes.has(_mount_id):
		return
	var horse: Node3D = _nodes[_mount_id]
	_rider.global_transform=horse.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,.83,-.08))
	var model := _rider.get("_model") as Node3D
	if model:
		model.rotation=Vector3.ZERO

func dismount_all() -> bool:
	if not is_mounted():
		return true
	var old_role := _rider_role
	var old_mount := _mount_id
	var at := get_animal_position()
	var target := at
	for i in range(16):
		var p := Vector2(at.x,at.z)+Vector2(sin(i*TAU/16),cos(i*TAU/16))*2.2
		if _nav and _nav.is_walkable(p):
			target=_ground(p)
			break
	if is_instance_valid(_rider):
		_rider.end_work()
		_rider.global_rotation=Vector3.ZERO
		_rider.global_position=target
		_rider.set_physics_process(_rider_physics)
		_rider.play_action("idle")
	_rider=null
	_rider_role=""
	_mount_id=""
	stop_moving()
	if animals.has(old_mount):
		_waits[old_mount]=6.0
		_animate(old_mount,false,0)
	mounted_changed.emit(old_role,false)
	return true

func _hero(role: String) -> Node3D:
	if not is_instance_valid(_game) or not _game.has_method("_hero"):
		return null
	var state: Variant = _game.get("state")
	if state is Dictionary and state.get("characters",{}) is Dictionary and not state.characters.has(role):
		return null
	return _game.call("_hero",role) as Node3D

func _combat(role: String = "") -> bool:
	if not is_instance_valid(_game): return false
	var chosen := _rider_role if role.is_empty() else role
	if not chosen.is_empty() and _game.has_method("_role_in_combat"):
		return bool(_game.call("_role_in_combat",chosen))
	return bool(_game.get("in_combat")) if _game.get("in_combat")!=null else false

func _caravan_controls(role: String) -> bool:
	var caravan: Variant = _game.get("caravan") if _game else null
	return caravan!=null and caravan.has_method("is_controlled") and caravan.is_controlled(role)

func snapshot() -> Dictionary:
	var route: Array = []
	for point: Vector3 in _ride_route:
		route.append(_array(point))
	return {"version":1,"animals":animals.duplicate(true),"clock":_clock,"next_id":_next_id,"rider":_rider_role,"mount":_mount_id,"route":route,"route_index":_ride_cursor,"target":_array(_ride_target),"rider_physics":_rider_physics}

func valid_snapshot(state: Variant) -> bool:
	if not state is Dictionary:
		return false
	if state.is_empty():
		return true
	if state.get("version",1)!=1:
		return false
	if not state.get("animals") is Dictionary or state.animals.size()>MAX_ANIMALS:
		return false
	for id: Variant in state.animals:
		if not id is String or not str(id).begins_with("ranch_") or not state.animals[id] is Dictionary:
			return false
		var a: Dictionary = state.animals[id]
		if a.get("id","")!=id or not SPECIES.has(str(a.get("species",""))) or not _valid_vector(a.get("position")) or not _valid_vector(a.get("home")):
			return false
		for key: String in ["name","owner","sex","produce","follow_role","status"]:
			if not a.get(key) is String or str(a[key]).length()>128:
				return false
		if a.sex not in ["male","female"] or a.owner not in ["","house_player","stable","village"]:
			return false
		if str(a.produce)!=str(SPECIES[a.species].produce):
			return false
		for key: String in ["food","water","health","stamina","bond"]:
			if not _number(a.get(key),0,100): return false
		for key: String in ["age","production","gestation","breed_cooldown"]:
			if not _number(a.get(key),0,1.0e10): return false
		if not _number(a.get("heading"),-1000,1000) or not _number(a.get("stock"),0,6) or float(a.stock)!=floorf(float(a.stock)):
			return false
		if str(a.produce).is_empty() and (int(a.stock)!=0 or float(a.production)!=0):
			return false
	if not _number(state.get("clock",0),0,1e12) or not _number(state.get("next_id",1),1,1e8):
		return false
	if float(state.get("next_id",1))!=floorf(float(state.get("next_id",1))): return false
	if not state.get("rider","") is String or not state.get("mount","") is String or not state.get("route",[]) is Array or not state.get("rider_physics",true) is bool:
		return false
	if state.get("route",[]).size()>4096 or not _number(state.get("route_index",0),0,state.get("route",[]).size()):
		return false
	if float(state.get("route_index",0))!=floorf(float(state.get("route_index",0))): return false
	for point: Variant in state.get("route",[]):
		if not _valid_vector(point): return false
	if not _valid_vector(state.get("target",[0,0,0]),true): return false
	var rider := str(state.get("rider",""))
	var mount := str(state.get("mount",""))
	if rider.is_empty()!=mount.is_empty(): return false
	if not mount.is_empty():
		if not state.animals.has(mount) or state.animals[mount].species!="horse" or state.animals[mount].owner!="house_player" or float(state.animals[mount].health)<=0:
			return false
	return true

func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

func _valid_vector(value: Variant, allow_zero: bool = false) -> bool:
	if not value is Array or value.size()!=3:
		return false
	for item: Variant in value:
		if not _number(item,-1e6,1e6): return false
	if allow_zero and _vector(value)==Vector3.ZERO: return true
	return not _world or _world.bounds.has_point(Vector2(float(value[0]),float(value[2])))

func restore(state: Dictionary) -> void:
	if not _built:
		_pending_restore=state.duplicate(true)
		return
	if not valid_snapshot(state):
		return
	var saved: Dictionary = _initial_snapshot.duplicate(true) if state.is_empty() else state.duplicate(true)
	dismount_all()
	for id: String in animals.keys():
		_remove_animal(id)
	animals=saved.animals.duplicate(true)
	_clock=float(saved.get("clock",0))
	_next_id=maxi(1,int(saved.get("next_id",1)))
	for id: String in animals:
		var at := _vector(animals[id].position)
		animals[id].position=_array(_ground(Vector2(at.x,at.z)))
		_create_node(id)
		if id.begins_with("ranch_born_"):
			_next_id=maxi(_next_id,int(id.trim_prefix("ranch_born_"))+1)
	_rider_role=str(saved.get("rider",""))
	_mount_id=str(saved.get("mount",""))
	_rider_physics=bool(saved.get("rider_physics",true))
	_ride_route.clear()
	for value: Array in saved.get("route",[]):
		var point := _vector(value)
		_ride_route.append(_ground(Vector2(point.x,point.z)))
	_ride_cursor=int(saved.get("route_index",0))
	_ride_target=_vector(saved.get("target",[0,0,0]))
	_bind_rider()

func _remove_animal(id: String) -> void:
	if id==_mount_id:
		dismount_all()
	if _nodes.has(id):
		var node: Node3D = _nodes[id]
		if _world.objects.has(id) and _world.objects[id].get("node")==node:
			_world.objects.erase(id)
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	for records: Dictionary in [_nodes,_visuals,_legs,_horse_players,_labels,_roam_paths,_roam_indices,_waits]:
		records.erase(id)
	animals.erase(id)

func _exit_tree() -> void:
	if is_instance_valid(_rider):
		_rider.end_work()
		_rider.set_physics_process(_rider_physics)

func _array(p: Vector3) -> Array:
	return [p.x,p.y,p.z]

func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x,float(_world.sample_height(p.x,p.y)),p.y)

func _safe_point(p: Vector2) -> Vector3:
	if _nav.is_walkable(p): return _ground(p)
	for ring in range(1,12):
		for i in range(16):
			var q := p+Vector2(sin(i*TAU/16),cos(i*TAU/16))*float(ring)*1.5
			if _nav.is_walkable(q): return _ground(q)
	return _ground(p)

func _create_node(id: String) -> void:
	var a: Dictionary = animals[id]
	var node := Node3D.new()
	node.name=id
	add_child(node)
	node.position=_vector(a.position)
	node.rotation.y=float(a.heading)
	_nodes[id]=node
	var visual := Node3D.new()
	node.add_child(visual)
	_visuals[id]=visual
	_legs[id]=[]
	var species := str(a.species)
	if species=="horse":
		var model := (load("res://assets/animals/horse.glb") as PackedScene).instantiate() as Node3D
		visual.add_child(model)
		model.scale=Vector3.ONE*.4
		for player: AnimationPlayer in model.find_children("*","AnimationPlayer",true,false):
			_horse_players[id]=player
			for clip: StringName in player.get_animation_list():
				if str(clip).ends_with("Idle") or str(clip).ends_with("Walk") or str(clip).ends_with("Gallop"):
					player.get_animation(clip).loop_mode=Animation.LOOP_LINEAR
		_box(visual,Vector3(0,1.38,-.12),Vector3(.72,.16,.70),"saddle")
		_box(visual,Vector3(0,1.33,-.12),Vector3(.88,.10,.90),"red")
		for side: float in [-1,1]:
			_box(visual,Vector3(side*.43,1.06,-.12),Vector3(.06,.45,.08),"leather")
			_box(visual,Vector3(side*.44,.83,-.12),Vector3(.12,.06,.20),"metal")
	else:
		_build_domestic(visual,species,id,str(a.sex))
	visual.scale=Vector3.ONE*lerpf(.55,1.0,clampf(float(a.age)/ADULT_AGE,0,1))
	var body := StaticBody3D.new()
	body.collision_layer=2
	body.collision_mask=0
	body.set_meta("object_id",id)
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius=.8 if species=="horse" else .55
	shape.height=2.3 if species=="horse" else (.75 if species=="chicken" else 1.4)
	collider.shape=shape
	collider.position.y=shape.height*.5
	body.add_child(collider)
	node.add_child(body)
	var label := Label3D.new()
	label.position.y=2.6 if species=="horse" else (1.1 if species=="chicken" else 1.8)
	label.font_size=24
	label.pixel_size=.009
	label.modulate=Color("#ffedc5")
	label.outline_modulate=Color("#343a2c")
	label.outline_size=8
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end=55
	node.add_child(label)
	_labels[id]=label
	_world.objects[id]={"id":id,"type":"ranch_animal","name":str(a.name),"description":"","position":node.position,"approach":node.position+Vector3(2,0,0),"surface_radius":shape.radius,"node":node}
	_waits[id]=_rng.randf_range(3,9)
	_animate(id,false,0)
	_update_status(id)

func _update_status(id: String) -> void:
	if not _nodes.has(id): return
	var a: Dictionary = animals[id]
	var at := get_animal_position(id)
	var approach := _safe_point(Vector2(at.x+2,at.z))
	_world.objects[id]["position"]=at
	_world.objects[id]["approach"]=approach
	_world.objects[id]["description"]="%s · корм%d · вода%d · здоровье%d · силы%d\n%s"%[str(SPECIES[a.species].name),roundi(float(a.food)),roundi(float(a.water)),roundi(float(a.health)),roundi(float(a.stamina)),str(a.status)]
	(_labels[id] as Label3D).text=str(a.name)+(" · ваш двор" if a.owner=="house_player" else "")+"\n"+str(a.status)

func _animate(id: String, moving: bool, _delta: float) -> void:
	if _horse_players.has(id):
		var player: AnimationPlayer = _horse_players[id]
		var desired := "Gallop" if moving and id==_mount_id else ("Walk" if moving else "Idle")
		for clip: StringName in player.get_animation_list():
			if str(clip).ends_with(desired):
				if str(player.current_animation)!=str(clip): player.play(clip,.2)
				break
	else:
		var legs: Array = _legs.get(id,[])
		for i in legs.size():
			var leg: Node3D = legs[i]
			leg.rotation.x=sin(_clock*8.0+(PI if i in [1,2] else 0))*.42 if moving else 0.0
		if _visuals.has(id):
			(_visuals[id] as Node3D).position.y=absf(sin(_clock*8))*.035 if moving else 0.0

func _build_domestic(parent: Node3D, species: String, id: String, sex: String) -> void:
	if species=="chicken":
		_sphere(parent,Vector3(0,.44,0),Vector3(.38,.43,.47),"cream")
		_sphere(parent,Vector3(0,.72,.25),Vector3(.25,.27,.24),"cream")
		_box(parent,Vector3(0,.74,.43),Vector3(.11,.08,.19),"beak")
		_box(parent,Vector3(0,.91,.23),Vector3(.06,.16 if sex=="male" else .08,.18),"red")
		for side: float in [-1,1]:
			_leg(parent,id,Vector3(side*.11,.3,0),.3,.045,"beak")
			_sphere(parent,Vector3(side*.125,.77,.32),Vector3(.035,.035,.035),"black")
			_box(parent,Vector3(side*.19,.48,-.02),Vector3(.07,.23,.30),"brown")
		var tail := _box(parent,Vector3(0,.61,-.35),Vector3(.26,.4,.08),"brown")
		tail.rotation.x=-.5
		return
	var dog := species=="dog"
	var length := 1.1 if dog else 1.25
	var hip := .48 if dog else .65
	var body_color := "brown" if dog else ("cream" if species=="sheep" else "tan")
	if species=="sheep":
		for x: float in [-.15,.15]:
			for z: float in [-.25,.25]:
				_sphere(parent,Vector3(x,.88,z),Vector3(.55,.70,.72),"cream")
	else:
		_box(parent,Vector3(0,hip+.18,0),Vector3(.48,.45,length),body_color)
	var head_y := hip+.35
	_box(parent,Vector3(0,head_y,length*.58),Vector3(.33,.38,.42),"brown" if dog else "tan")
	_box(parent,Vector3(0,head_y-.04,length*.78),Vector3(.25,.21,.24),"black" if dog else "tan")
	for side: float in [-1,1]:
		for z: float in [-length*.33,length*.31]:
			_leg(parent,id,Vector3(side*.2,hip,z),hip,.12,"brown" if dog else "black")
		_sphere(parent,Vector3(side*.17,head_y+.04,length*.69),Vector3(.045,.045,.045),"black")
		var ear := _box(parent,Vector3(side*.23,head_y+.17,length*.52),Vector3(.12,.25,.12),body_color)
		ear.rotation.z=side*.6
		if species=="goat":
			var horn := _cylinder(parent,Vector3(side*.13,head_y+.35,length*.48),.055,.4,"horn",.01)
			horn.rotation.x=-.35
	var tail := _box(parent,Vector3(0,hip+.26,-length*.62),Vector3(.10,.42,.1),body_color)
	tail.rotation.x=.8 if dog else -.5

func _leg(parent: Node3D, id: String, at: Vector3, length: float, width: float, material: String) -> void:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	pivot.position=at
	_box(pivot,Vector3(0,-length*.5,0),Vector3(width,length,width),material)
	_legs[id].append(pivot)

func _material(key: String) -> StandardMaterial3D:
	if _materials.has(key): return _materials[key]
	var colors := {"cream":"#d9d3b7","tan":"#b8a481","brown":"#795d41","black":"#33382e","horn":"#d4c9a5","beak":"#d1a34f","red":"#9b5044","saddle":"#6d4830","leather":"#533b2b","metal":"#7f8989"}
	var mat := StandardMaterial3D.new()
	mat.albedo_color=Color(str(colors.get(key,"#b5a483")))
	mat.roughness=.9
	_materials[key]=mat
	return mat

func _box(parent: Node3D, at: Vector3, size: Vector3, material: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size=size
	return _mesh(parent,at,mesh,material)

func _sphere(parent: Node3D, at: Vector3, size: Vector3, material: String) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius=.5
	mesh.height=1
	mesh.radial_segments=10
	mesh.rings=5
	var instance := _mesh(parent,at,mesh,material)
	instance.scale=size
	return instance

func _cylinder(parent: Node3D, at: Vector3, radius: float, height: float, material: String, top: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius=radius
	mesh.top_radius=top
	mesh.height=height
	mesh.radial_segments=7
	return _mesh(parent,at,mesh,material)

func _mesh(parent: Node3D, at: Vector3, mesh: Mesh, material: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh=mesh
	instance.position=at
	instance.material_override=_material(material)
	instance.visibility_range_end=180
	parent.add_child(instance)
	return instance
