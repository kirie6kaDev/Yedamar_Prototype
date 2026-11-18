extends Node3D
## Authoritative household simulation; all persistent data is JSON-compatible.
const Catalog := preload("res://scripts/domestic_catalog.gd")
const Dressing := preload("res://scripts/domestic_world.gd")
var game
var objects: Dictionary = {}
var homes: Dictionary = {}
var people: Dictionary = {}
var meals: Dictionary = {}
var jobs: Dictionary = {}
var reservations: Dictionary = {}
var events: Array = []
var clock := 0.0
var next_batch := 1
var _records: Dictionary = {}
var _fixtures: Dictionary = {}
var _venues: Dictionary = {}
var _visual
var _configured := false
var _refresh := 0.0
var _chores := 0.0
var _step := 0.0

func configure(owner_game) -> void:
	game=owner_game
	if is_node_ready(): _setup()

func _ready() -> void:
	if game: _setup()

func _setup() -> void:
	if _configured: return
	_configured=true
	clock=float(game.life.sim.clock)
	_visual=Dressing.new()
	_visual.configure(self,game)
	sync_objects()

func _sim():
	return game.life.sim

func _vec(value: Variant) -> Vector3:
	if value is Vector3: return value
	if value is Array and value.size()==3: return Vector3(float(value[0]),float(value[1]),float(value[2]))
	return Vector3.ZERO

func _arr(p: Vector3) -> Array:
	return [p.x,p.y,p.z]

func _new_object(kind: String, home: String) -> Dictionary:
	return {"kind":kind,"home":home,"condition":100.0,"cleanliness":90.0,"fuel":0.0,"lit":false,"fire":0.0,"hazard":0.0,"upgrade":0,"uses":0}

func _new_home() -> Dictionary:
	return {"dirty_laundry":2.0,"collected":0,"wet":0,"hanging":0,"dry":0,"clean_linen":4,"drying":0.0,"dishes":0,"chores_done":0}

func _new_person() -> Dictionary:
	return {"linen":90.0,"warm_clothes":false,"cloak_owned":false,"wetness":0.0,"cold":0.0,"heat":0.0,"illness":"","severity":0.0,"treatment":0.0,"care":85.0}

func sync_objects() -> void:
	if not _configured: return
	var seen: Dictionary={}
	var venues: Dictionary=game.city.get_venues()
	_venues=venues
	for home: String in venues:
		var venue: Dictionary=venues[home]
		if not str(venue.kind) in ["home","plot"]: continue
		if not homes.has(home): homes[home]=_new_home()
		if str(venue.kind)=="plot" and not _home_occupied(home): continue
		var center:=_vec(venue.get("center",venue.position))
		var entry:=_vec(venue.get("approach",venue.position))
		var depth:float=float(venue.get("size",[24,20])[1])
		var kinds: Array=["basket","wash_tub","drying_line","cradle"]
		for i in kinds.size():
			var kind:String=kinds[i]
			var id: String="home_"+home+"_"+kind
			if _fixtures.has(id): continue
			var desired:=Vector2(center.x-10+i*6,center.z+depth*.5+5)
			if kind=="cradle": desired=Vector2(center.x+3,center.z+2)
			var record: Dictionary=_visual.add_fixture(id,kind,home,desired,entry)
			if not record.is_empty(): _fixtures[id]=record
	for id: String in game.city.get_objects():
		var info: Dictionary=game.city.get_object(id)
		var kind: String=str(info.get("prop",""))
		if not kind in Catalog.MAINTAINED: continue
		var home: String=str(info.get("venue_id",""))
		_records[id]={"id":id,"kind":kind,"home":home,"name":str(info.name),"position":info.position,"approach":info.approach}
		seen[id]=true
		if not objects.has(id): objects[id]=_new_object(kind,home)
	for id: String in _fixtures:
		_records[id]=_fixtures[id].duplicate(true)
		seen[id]=true
		if not objects.has(id): objects[id]=_new_object(str(_records[id].kind),str(_records[id].home))
	for id: String in game.settlement.buildings:
		if not game.world.objects.has(id): continue
		var kind: String=str(game.settlement.buildings[id].kind)
		if not kind in Catalog.MAINTAINED: continue
		var w: Dictionary=game.world.objects[id]
		var home:String=str(_sim().venues.get(id,{}).get("parent",""))
		if not homes.has(home): home=_closest_home(_vec(w.position))
		_records[id]={"id":id,"kind":kind,"home":home,"name":str(w.name),"position":_arr(_vec(w.position)),"approach":_arr(_vec(w.approach))}
		seen[id]=true
		if not objects.has(id): objects[id]=_new_object(kind,home)
		objects[id].kind=kind; objects[id].home=home
	for id: String in objects.keys():
		if not seen.has(id):
			objects.erase(id); _records.erase(id); reservations.erase(id)
			_visual.update_fire(id,Vector3.ZERO,0)
	for role: String in _sim().residents:
		if not people.has(role): people[role]=_new_person()
	for role: String in people.keys():
		if not _sim().residents.has(role): people.erase(role); _cancel_job(role)
	var extra_venues:=get_venues()
	for id:String in extra_venues: _sim().venues[id]=extra_venues[id]
	_mirror()

func _closest_home(point: Vector3) -> String:
	var best: String="life_player_home"
	var distance:=INF
	for id: String in homes:
		var record: Dictionary=_venues.get(id,{})
		if record.is_empty(): continue
		var d:float=point.distance_squared_to(_vec(record.position))
		if d<distance: distance=d; best=id
	return best

func get_venues() -> Dictionary:
	var result: Dictionary={}
	for id: String in _fixtures:
		var r: Dictionary=_fixtures[id]
		result[id]={"id":id,"kind":r.kind,"name":r.name,"parent":r.home,"position":r.approach.duplicate(),"capacity":1,"safe":true}
	return result

func owns(id: String) -> bool:
	return objects.has(id)

func _home(role: String) -> String:
	return str(_sim().residents.get(role,{}).get("home_id","life_player_home"))

func _family(role: String) -> Dictionary:
	var p: Dictionary=_sim().residents.get(role,{})
	return _sim().households.get(str(p.get("household_id","")),{})

func _inventory(role: String) -> Dictionary:
	return _sim().residents.get(role,{}).get("inventory",{})

func _position(role: String) -> Vector3:
	if game.state.characters.has(role): return game._hero(role).position
	if game.life.citizens.has(role) and is_instance_valid(game.life.citizens[role]): return game.life.citizens[role].position
	return _sim().position_of(role)

func _access(role: String, home: String) -> bool:
	if not homes.has(home): return true
	return _family(role).get("properties",[]).has(home) or _home(role)==home

func _amount(role: String, item: String) -> int:
	return int(_inventory(role).get(item,0))+int(_family(role).get("inventory",{}).get(item,0))

func _cost_error(role: String, cost: Dictionary) -> String:
	for item: String in cost:
		if _amount(role,item)<int(cost[item]): return "Не хватает: "+str(game.Campaign.ITEMS.get(item,item))+" × "+str(cost[item])+" (рюкзак или семейный запас)."
	return ""

func _pay(role: String, cost: Dictionary) -> void:
	var inv:=_inventory(role)
	var store:Dictionary=_family(role).get("inventory",{})
	for item: String in cost:
		var from_bag:int=mini(int(inv.get(item,0)),int(cost[item]))
		inv[item]=int(inv.get(item,0))-from_bag
		var left:int=int(cost[item])-from_bag
		if left>0: store[item]=int(store.get(item,0))-left

func _cost(action: String, payload: Dictionary, role: String="") -> Dictionary:
	match action:
		"clean","wash_dishes","change_child": return {"water":1}
		"repair": return {"wood":1}
		"upgrade": return {"plank":2,"iron_ingot":1}
		"fuel": return {"wood":1}
		"extinguish","wash_laundry": return {"water":2}
		"warm_clothes": return {} if bool(people.get(role,{}).get("cloak_owned",false)) else {"wool":2,"cloth":1}
		"herbal_care": return {"herb":2,"water":1}
		"cook": return Catalog.RECIPES.get(str(payload.get("recipe_id","stew")),{}).get("cost",{})
	return {}

func _child(role: String, payload: Dictionary) -> String:
	var requested:String=str(payload.get("child_id",""))
	if not requested.is_empty(): return requested
	for id: String in _family(role).get("members",[]):
		if _sim().residents.has(id) and float(_sim().residents[id].age_years)<5 and bool(_sim().residents[id].alive): return id
	return ""

func _find(home: String, kinds: Array) -> String:
	for id: String in objects:
		if str(objects[id].home)==home and str(objects[id].kind) in kinds: return id
	return ""

func _target_id(role: String, action: String, payload: Dictionary) -> String:
	var id:String=str(payload.get("target_id",""))
	if not id.is_empty(): return id
	var home:=_home(role)
	match action:
		"doctor": return "life_clinic"
		"cook","fuel","light","douse": return _find(home,["hearth","cauldron"])
		"eat","serve_food","wash_dishes": return _find(home,["dining","table"])
		"store_food","discard_food": return _find(home,["pantry","storage"])
		"collect_laundry": return _find(home,["basket"])
		"wash_laundry": return _find(home,["wash_tub"])
		"hang_laundry","fold_laundry": return _find(home,["drying_line"])
		"feed_child","change_child","soothe_child": return _find(home,["cradle"])
		"rest","change_linen","warm_clothes","remove_cloak","herbal_care": return _find(home,["bed"])
	return ""

func _verb(action: String) -> String:
	return action.trim_prefix("home:").get_slice(":",0)

func _payload(action: String, payload: Dictionary) -> Dictionary:
	var result:Dictionary=payload.duplicate(true)
	var bare:String=action.trim_prefix("home:")
	if bare.begins_with("cook:") and not result.has("recipe_id"): result.recipe_id=bare.get_slice(":",1)
	return result

func _batch(home: String, payload: Dictionary, mode: String="fresh") -> String:
	var requested:String=str(payload.get("batch_id",""))
	for id: String in meals:
		if not requested.is_empty() and requested!=id: continue
		var b:Dictionary=meals[id]
		if str(b.home)!=home or int(b.portions)<=0: continue
		if mode=="spoiled" and float(b.freshness)>0: continue
		if mode=="fresh" and float(b.freshness)<=0: continue
		if mode=="pantry" and (str(b.location)!="pantry" or float(b.freshness)<=0): continue
		if mode=="table" and str(b.location)!="table": continue
		return id
	return ""

func validate(role: String, action: String, payload: Dictionary={}) -> String:
	payload=_payload(action,payload)
	action=_verb(action)
	if not Catalog.ACTIONS.has(action): return "Неизвестное домашнее действие."
	if not _sim().residents.has(role) or not bool(_sim().residents[role].alive): return "Персонаж недоступен."
	for key: String in ["target_id","recipe_id","batch_id","child_id"]:
		if payload.has(key) and not payload[key] is String: return "Неверные параметры действия."
	var p:Dictionary=_sim().residents[role]
	if float(p.age_years)<5: return "Малышу нужна помощь старшего."
	if action in ["cook","light","repair","upgrade","extinguish","feed_child","change_child","soothe_child"] and float(p.age_years)<13: return "Для этой работы нужен подросток или взрослый."
	var id:=_target_id(role,action,payload)
	if id.is_empty(): return "Подходящий предмет отсутствует."
	if action=="doctor":
		if id!="life_clinic": return "Для осмотра нужно прийти к лекарю."
		if not game.world.objects.has("life_clinic"): return "Лекарь недоступен."
		if float(people.get(role,{}).get("severity",0))<=0: return "Лечение сейчас не требуется."
		if int(_family(role).get("coins",0))<8: return "Нужно 8 монет семьи."
		return ""
	if not objects.has(id): return "Предмет больше не существует."
	var o:Dictionary=objects[id]
	var home:String=str(o.home)
	if not _access(role,home): return "Это чужой дом."
	if reservations.has(id) and str(reservations[id].role)!=role and float(reservations[id].until)>clock: return "Предмет занят."
	if float(o.fire)>0 and action!="extinguish": return "Сначала потушите пожар."
	if float(o.condition)<=0 and not action in ["repair","extinguish"]: return "Предмет сломан: нужен ремонт."
	var kind:String=str(o.kind)
	var h:Dictionary=homes.get(home,{})
	var care:Dictionary=people.get(role,_new_person())
	match action:
		"clean":
			if float(o.cleanliness)>=98: return "Уже чисто."
		"repair":
			if float(o.condition)>=98: return "Ремонт не требуется."
		"upgrade":
			if int(o.upgrade)>=2: return "Предмет уже укреплён полностью."
		"fuel","light","douse","cook":
			if not kind in Catalog.HEAT: return "Нужен кухонный очаг."
			if action=="fuel" and float(o.fuel)>75: return "Топлива достаточно."
			if action=="light" and (bool(o.lit) or float(o.fuel)<1): return "Огонь уже горит или нет топлива."
			if action=="douse" and not bool(o.lit): return "Очаг уже погашен."
			if action=="cook":
				if h.is_empty(): return "Для семейного блюда нужен домашний очаг."
				if not Catalog.RECIPES.has(str(payload.get("recipe_id","stew"))): return "Неизвестный рецепт."
				if not bool(o.lit) or float(o.fuel)<3: return "Подложите дрова и разожгите очаг."
				if float(o.cleanliness)<15: return "Сначала вымойте очаг."
				if _meal_count(home)>=24: return "В доме уже достаточно готовых порций."
		"extinguish":
			if float(o.fire)<=0: return "Здесь нет пожара."
		"eat","store_food","serve_food","discard_food","wash_dishes":
			if h.is_empty(): return "Нужен домашний стол или кладовая."
			if action=="eat" and not kind in ["dining","table","pantry","storage"]: return "Нужен стол или кладовая."
			if action=="eat" and _batch(home,payload).is_empty(): return "Нет свежих приготовленных порций."
			if action=="store_food" and not kind in ["pantry","storage"]: return "Нужна кладовая."
			if action=="store_food" and _batch(home,payload,"table").is_empty(): return "На столе нет остатков."
			if action=="serve_food" and (not kind in ["dining","table"] or _batch(home,payload,"pantry").is_empty()): return "Нет свежих запасов для подачи на стол."
			if action=="discard_food" and _batch(home,payload,"spoiled").is_empty(): return "Испорченных блюд нет."
			if action=="wash_dishes" and (not kind in ["wash_tub","washbasin","bath","dining","table"] or int(h.dishes)<=0): return "Нет грязной посуды."
		"collect_laundry":
			if kind!="basket" or float(h.get("dirty_laundry",0))<1: return "Нет грязного белья для сбора."
			if int(h.get("collected",0))>=12: return "Корзина заполнена: сначала выстирайте собранное бельё."
		"wash_laundry":
			if kind!="wash_tub" or int(h.get("collected",0))<1: return "Сначала соберите грязное бельё в корзину."
			if int(h.get("wet",0))+int(h.get("hanging",0))>=6: return "Сначала высушите предыдущую стирку."
		"hang_laundry":
			if kind!="drying_line" or int(h.get("wet",0))<1 or int(h.get("hanging",0))>0: return "Нужно мокрое бельё и свободная верёвка."
		"fold_laundry":
			if kind!="drying_line" or int(h.get("dry",0))<1: return "Бельё ещё не высохло."
		"change_linen":
			if not kind in ["bed","basket"] or int(h.get("clean_linen",0))<1: return "Нужен комплект чистого белья."
			if float(care.linen)>95: return "Бельё пока чистое."
		"warm_clothes":
			if not kind in ["bed","basket"]: return "Подготовьте одежду дома."
			if bool(care.warm_clothes): return "Тёплая накидка уже надета."
		"remove_cloak":
			if not bool(care.warm_clothes): return "Тёплая накидка не надета."
		"herbal_care","rest":
			if kind!="bed": return "Нужна кровать."
			if action=="herbal_care" and float(care.severity)<=0: return "Лечение сейчас не требуется."
		"feed_child","change_child","soothe_child":
			if kind!="cradle": return "Выберите колыбель дома ребёнка."
			var child:=_child(role,payload)
			if child.is_empty() or not _sim().residents.has(child): return "В семье нет малыша до пяти лет."
			var c:Dictionary=_sim().residents[child]
			if not bool(c.alive) or float(c.age_years)>=5 or str(c.household_id)!=str(p.household_id): return "Можно ухаживать за малышом своей семьи."
			if str(c.home_id)!=home: return "Колыбель находится в другом доме."
			if action=="feed_child" and _amount(role,"milk")<1 and _amount(role,"meal")<1: return "Нужно молоко или порция похлёбки."
			if action=="change_child" and int(h.get("clean_linen",0))<1: return "Нужна чистая пелёнка из домашнего белья."
	return _cost_error(role,_cost(action,payload,role))

func spec(role: String, action: String, payload: Dictionary={}) -> Dictionary:
	payload=_payload(action,payload)
	action=_verb(action)
	var reason:=validate(role,action,payload)
	var id:=_target_id(role,action,payload)
	var def:Dictionary=Catalog.ACTIONS.get(action,{})
	var target:Vector3=_position(role) if _sim().residents.has(role) else Vector3.ZERO
	if _records.has(id): target=_vec(_records[id].approach)
	elif game.world.objects.has(id): target=_vec(game.world.objects[id].get("approach",game.world.objects[id].position))
	if action in ["feed_child","change_child","soothe_child"]:
		var child:=_child(role,payload)
		if _sim().residents.has(child): target=_position(child)
	return {"ok":reason.is_empty(),"reason":reason,"label":str(def.get("name",action)),"target":target,"venue_id":id,"duration":float(def.get("duration",10)),"animation":"interact" if action!="rest" else "Lie_Idle","portable":false}

func reserve(role: String, id: String, seconds: float) -> bool:
	if id.is_empty(): return false
	if reservations.has(id) and str(reservations[id].role)!=role and float(reservations[id].until)>clock: return false
	reservations[id]={"role":role,"until":clock+maxf(5,seconds+5)}
	return true

func release(role: String) -> void:
	for id: String in reservations.keys():
		if str(reservations[id].role)==role: reservations.erase(id)

func _meal_count(home: String) -> int:
	var count:=0
	for b: Dictionary in meals.values():
		if str(b.home)==home: count+=int(b.portions)
	return count

func _need(role: String, key: String, amount: float) -> void:
	if _sim().residents.has(role): _sim()._change_need(role,key,amount)

func _health(role: String, amount: float) -> void:
	if not _sim().residents.has(role): return
	var p:Dictionary=_sim().residents[role]
	if game.state.characters.has(role):
		var actor=game._hero(role)
		actor.health=clampf(float(actor.health)+amount,1,float(actor.max_health))
		p.health=actor.health
		game.state.characters[role].health=actor.health
	else:
		p.health=clampf(float(p.health)+amount,1,100)

func _mood(role: String, name: String, strength: float, duration: float=180.0) -> void:
	if _sim().has_method("_moodlet"): _sim()._moodlet(role,"domestic",name,strength,duration,"home")

func complete(role: String, action: String, payload: Dictionary={}) -> Dictionary:
	payload=_payload(action,payload)
	action=_verb(action)
	var s:=spec(role,action,payload)
	if not bool(s.ok): return {"ok":false,"message":str(s.reason)}
	if Vector2(_position(role).x,_position(role).z).distance_to(Vector2(s.target.x,s.target.z))>3.2: return {"ok":false,"message":"Нужно подойти к месту работы."}
	var id:String=str(s.venue_id)
	var o:Dictionary=objects.get(id,{})
	var home:String=str(o.get("home",_home(role)))
	var h:Dictionary=homes.get(home,{})
	var person:Dictionary=people[role]
	_pay(role,_cost(action,payload,role))
	var message:String=str(Catalog.ACTIONS[action].name)+": готово."
	match action:
		"clean": o.cleanliness=100.0; _need(role,"hygiene",-3)
		"repair": o.condition=minf(100,float(o.condition)+70); o.hazard=0.0
		"upgrade": o.upgrade=int(o.upgrade)+1; o.condition=100.0
		"fuel": o.fuel=minf(100,float(o.fuel)+35)
		"light": o.lit=true
		"douse": o.lit=false; o.hazard=0.0
		"extinguish": o.fire=0.0; o.lit=false; o.fuel=0.0; o.hazard=0.0; _event("Пожар потушен.",home)
		"cook":
			var recipe:String=str(payload.get("recipe_id","stew"))
			var r:Dictionary=Catalog.RECIPES[recipe]
			var xp:float=float(_sim().residents[role].skills.get("cooking",0))
			var quality:float=clampf(35+sqrt(xp)*2+float(o.cleanliness)*.25,10,100)
			var batch:String="dish_"+str(next_batch); next_batch+=1
			meals[batch]={"id":batch,"home":home,"recipe":recipe,"portions":int(r.portions),"quality":quality,"freshness":float(r.life),"location":"table","made":clock}
			o.fuel=maxf(0,float(o.fuel)-3); o.cleanliness=maxf(0,float(o.cleanliness)-8); o.condition=maxf(0,float(o.condition)-1)
			message="Приготовлено: "+str(r.name)+" · "+str(r.portions)+" порции · качество "+str(roundi(quality))+"."
		"eat":
			var batch:=_batch(home,payload)
			var b:Dictionary=meals[batch]
			_need(role,"hunger",float(Catalog.RECIPES[b.recipe].nutrition)*(.75+float(b.quality)/200))
			_need(role,"comfort",8); _mood(role,"Домашняя еда",5+float(b.quality)/20)
			b.portions=int(b.portions)-1; h.dishes=mini(100,int(h.dishes)+1)
			if int(b.portions)==0: meals.erase(batch)
			if float(o.cleanliness)<25: _infect(role,"food",12)
		"store_food":
			meals[_batch(home,payload,"table")].location="pantry"
		"serve_food": meals[_batch(home,payload,"pantry")].location="table"
		"discard_food": meals.erase(_batch(home,payload,"spoiled")); _need(role,"hygiene",-2)
		"wash_dishes": h.dishes=maxi(0,int(h.dishes)-6); o.cleanliness=minf(100,float(o.cleanliness)+10)
		"collect_laundry":
			var amount:int=mini(mini(6,12-int(h.collected)),floori(float(h.dirty_laundry)))
			h.dirty_laundry=float(h.dirty_laundry)-amount; h.collected=int(h.collected)+amount
		"wash_laundry":
			var amount:int=mini(6,int(h.collected))
			h.collected=int(h.collected)-amount; h.wet=int(h.wet)+amount; o.cleanliness=maxf(0,float(o.cleanliness)-5)
		"hang_laundry": h.hanging=int(h.wet); h.wet=0; h.drying=0.0
		"fold_laundry": h.clean_linen=mini(100,int(h.clean_linen)+int(h.dry)); h.dry=0
		"change_linen": h.clean_linen=int(h.clean_linen)-1; h.dirty_laundry=minf(100,float(h.dirty_laundry)+1); person.linen=100.0; _need(role,"hygiene",25); _need(role,"comfort",18); _mood(role,"Чистое бельё",10,360)
		"warm_clothes": person.warm_clothes=true; person.cloak_owned=true; _mood(role,"Тёплая накидка",5,120)
		"remove_cloak": person.warm_clothes=false
		"doctor":
			_family(role).coins=int(_family(role).coins)-8
			_family(role).expenses=int(_family(role).get("expenses",0))+8
			_sim().market.treasury=int(_sim().market.treasury)+8
			person.severity=maxf(0,float(person.severity)-65); person.treatment=360.0; _health(role,12)
			if float(person.severity)<=0: person.illness=""
			message="Лекарь назначил покой и травы. Оплачено 8 монет."
		"herbal_care": person.severity=maxf(0,float(person.severity)-25); person.treatment=180.0; _health(role,5); if float(person.severity)<=0: person.illness=""
		"rest": person.severity=maxf(0,float(person.severity)-8); person.cold=maxf(0,float(person.cold)-35); person.wetness=maxf(0,float(person.wetness)-30); _need(role,"energy",22); _health(role,3); if float(person.severity)<=0: person.illness=""
		"feed_child":
			var child:=_child(role,payload)
			_pay(role,{"milk":1} if _amount(role,"milk")>0 else {"meal":1})
			_need(child,"hunger",55); people[child].care=minf(100,float(people[child].care)+20); h.dishes=mini(100,int(h.dishes)+1)
		"change_child":
			var child:=_child(role,payload)
			h.clean_linen=int(h.clean_linen)-1; h.dirty_laundry=minf(100,float(h.dirty_laundry)+1)
			_need(child,"hygiene",70); _need(child,"bladder",70); people[child].linen=100.0; people[child].care=minf(100,float(people[child].care)+25)
		"soothe_child":
			var child:=_child(role,payload)
			_need(child,"energy",45); _need(child,"social",35); people[child].care=minf(100,float(people[child].care)+35); _mood(child,"Забота семьи",15,360)
	if not h.is_empty(): h.chores_done=int(h.chores_done)+1
	_mirror()
	return {"ok":true,"message":message,"skill":str(Catalog.ACTIONS[action].skill),"xp":float(Catalog.ACTIONS[action].xp)}

func before_use(role: String, object_id: String, verb: String) -> String:
	if not objects.has(object_id): return ""
	var o:Dictionary=objects[object_id]
	if float(o.fire)>0: return "Здесь пожар: сначала потушите его водой."
	if float(o.condition)<=0: return "Предмет сломан. Сначала почините его."
	if verb.trim_prefix("life:")=="cook" and str(o.kind) in Catalog.HEAT and (not bool(o.lit) or float(o.fuel)<3): return "Для готовки нужны дрова и зажжённый очаг."
	if reservations.has(object_id) and str(reservations[object_id].role)!=role and float(reservations[object_id].until)>clock: return "Предмет обслуживает другой житель."
	return ""

func record_use(role: String, object_id: String, verb: String) -> void:
	if not objects.has(object_id): return
	var o:Dictionary=objects[object_id]
	verb=verb.trim_prefix("life:")
	var wear:float={"sleep":1.2,"wash":2.0,"toilet":2.5,"cook":3.0,"eat":.7,"train":2.0}.get(verb,.5)
	o.condition=maxf(0,float(o.condition)-wear/(1+int(o.upgrade)*.65))
	o.cleanliness=maxf(0,float(o.cleanliness)-({"toilet":12.0,"wash":5.0,"cook":8.0,"eat":4.0}.get(verb,1.5)))
	o.uses=int(o.uses)+1
	var home:String=str(o.home)
	if homes.has(home):
		if verb=="eat": homes[home].dishes=mini(100,int(homes[home].dishes)+1)
		if verb in ["sleep","wash"]: homes[home].dirty_laundry=minf(100,float(homes[home].dirty_laundry)+.25)
	if verb=="cook": o.fuel=maxf(0,float(o.fuel)-3)
	if people.has(role) and float(o.cleanliness)<20:
		_need(role,"comfort",-8)
		if verb=="eat": _infect(role,"food",12)
	_mirror()

func _infect(role: String, kind: String, amount: float) -> void:
	if not people.has(role): return
	var p:Dictionary=people[role]
	if str(p.illness).is_empty():
		p.illness=kind
		_event(str(_sim().residents[role].name)+": "+str(Catalog.DISEASES[kind]),_home(role))
	p.severity=clampf(float(p.severity)+amount,0,100)

func _event(message: String, home: String) -> void:
	events.append({"time":clock,"message":message,"home":home})
	while events.size()>40: events.pop_front()

func tick(delta: float) -> void:
	if not _configured or not is_finite(delta) or delta<=0: return
	clock+=delta
	_refresh+=delta; _chores+=delta; _step+=delta
	var changed:bool=_step>=2
	if _refresh>=10: _refresh=fmod(_refresh,10); sync_objects()
	while _step>=2:
		_step-=2
		_tick_objects(2)
		_tick_food(2)
		_tick_people(2)
		_tick_jobs(2)
	if _chores>=20:
		_chores=fmod(_chores,20)
		_start_npc_chores()
	for id: String in reservations.keys():
		if float(reservations[id].until)<clock: reservations.erase(id)
	if changed: _mirror()

func _tick_objects(minutes: float) -> void:
	var wet:bool=str(_sim().weather.get("id","clear")) in ["rain","storm","snow"]
	for home: String in homes:
		var h:Dictionary=homes[home]
		if int(h.hanging)>0:
			h.drying=float(h.drying)+minutes*(.05 if wet else 1.0)
			if float(h.drying)>=120:
				h.dry=mini(100,int(h.dry)+int(h.hanging)); h.hanging=0; h.drying=0.0
	for id: String in objects:
		var o:Dictionary=objects[id]
		var occupied:bool=_home_occupied(str(o.home))
		if occupied:
			o.cleanliness=maxf(0,float(o.cleanliness)-minutes*.006)
			o.condition=maxf(0,float(o.condition)-minutes*.0005/(1+int(o.upgrade)))
		if bool(o.lit):
			o.fuel=maxf(0,float(o.fuel)-minutes*.08)
			if float(o.fuel)<=0: o.lit=false
			if float(o.condition)<25 or float(o.cleanliness)<12:
				o.hazard=float(o.hazard)+minutes*(1.0 if int(o.upgrade)==0 else .45)
				if float(o.hazard)>=45 and float(o.fire)<=0:
					o.fire=25.0
					_event("Возгорание: "+str(_records[id].name)+". Нужна вода!",str(o.home))
			else: o.hazard=maxf(0,float(o.hazard)-minutes)
		if float(o.fire)>0:
			o.fire=minf(100,float(o.fire)+minutes*.4)
			o.condition=maxf(0,float(o.condition)-minutes*.22)
			o.cleanliness=maxf(0,float(o.cleanliness)-minutes*.3)
			o.fuel=maxf(0,float(o.fuel)-minutes*.15)
			if float(o.condition)<=0 and float(o.fuel)<=0: o.fire=maxf(0,float(o.fire)-minutes*1.8); o.lit=false
			if float(o.fire)>80:
				for other: String in objects:
					if other==id or str(objects[other].home)!=str(o.home) or float(objects[other].fire)>0: continue
					if _vec(_records[id].position).distance_to(_vec(_records[other].position))<3.5 and float(objects[other].condition)>0:
						objects[other].fire=10.0
						break
			for role: String in people:
				if _position(role).distance_to(_vec(_records[id].position))<3.5: _health(role,-minutes*.10); _need(role,"comfort",-minutes*.5)

func _home_occupied(home: String) -> bool:
	for household: Dictionary in _sim().households.values():
		if str(household.home_id)==home and not household.members.is_empty(): return true
	return false

func _tick_food(minutes: float) -> void:
	for id: String in meals:
		var b:Dictionary=meals[id]
		var rate:float=.35 if str(b.location)=="pantry" else 1.0
		if float(_sim().weather.get("temperature",18))>25: rate*=1.4
		var old:float=float(b.freshness)
		b.freshness=maxf(0,old-minutes*rate)
		if old>0 and float(b.freshness)<=0: _event("Испортилась еда: "+str(Catalog.RECIPES[b.recipe].name),str(b.home))

func _sheltered(role: String) -> bool:
	var p:=_position(role)
	for venue: Dictionary in _venues.values():
		if not str(venue.kind) in ["home","clinic","tavern","school","library","academy","bathhouse","temple"]: continue
		var center:=_vec(venue.get("center",venue.position))
		var size: Array=venue.get("size",[20,20])
		if absf(p.x-center.x)<float(size[0])*.5 and absf(p.z-center.z)<float(size[1])*.5: return true
	for building: Dictionary in game.settlement.buildings.values():
		if str(building.kind) in ["shelter","roof"] and p.distance_to(_vec(building.position))<5: return true
	return false

func _tick_people(minutes: float) -> void:
	var weather:Dictionary=_sim().weather
	var outdoors:float=float(weather.get("temperature",18))
	var raining:bool=str(weather.get("id","clear")) in ["rain","storm","snow"]
	var heat_sources:Array[Vector3]=[]
	for id:String in objects:
		if bool(objects[id].lit): heat_sources.append(_vec(_records[id].position))
	for role: String in people:
		if not _sim().residents.has(role) or not bool(_sim().residents[role].alive): continue
		var p:Dictionary=people[role]
		var resident:Dictionary=_sim().residents[role]
		var shelter:=_sheltered(role)
		var temp:float=outdoors+(8 if shelter else 0)+(10 if bool(p.warm_clothes) else 0)-float(p.wetness)*.08
		for source:Vector3 in heat_sources:
			if _position(role).distance_to(source)<10: temp+=10; break
		p.wetness=clampf(float(p.wetness)+(minutes*.3 if raining and not shelter else -minutes*.5),0,100)
		p.cold=clampf(float(p.cold)+(minutes*(1+absf(temp)*.05) if temp<5 else -minutes*2),0,500)
		p.heat=clampf(float(p.heat)+(minutes if temp>32 else -minutes*2),0,500)
		p.linen=maxf(0,float(p.linen)-minutes*.018)
		var home:String=str(resident.home_id)
		if homes.has(home): homes[home].dirty_laundry=minf(100,float(homes[home].dirty_laundry)+minutes/1800.0)
		if float(p.linen)<25: _need(role,"hygiene",-minutes*.04); _need(role,"comfort",-minutes*.04)
		if float(p.cold)>120:
			_need(role,"comfort",-minutes*.15)
			if float(p.cold)>180: _infect(role,"cold",minutes*.05)
		if float(p.heat)>90: _need(role,"thirst",-minutes*.12); _need(role,"comfort",-minutes*.08)
		if float(p.wetness)>80 and float(p.linen)<20: _infect(role,"fever",minutes*.025)
		if float(p.treatment)>0: p.treatment=maxf(0,float(p.treatment)-minutes)
		if float(p.severity)>0:
			var resting:bool=bool(resident.get("current_action",{}).get("action","")=="sleep") or bool(game.state.characters.get(role,{}).get("sleeping",false))
			var recovery:float=.08 if float(p.treatment)>0 else (.025 if shelter and float(resident.needs.hunger)>40 else .005)
			if resting: recovery*=2
			p.severity=maxf(0,float(p.severity)-minutes*recovery)
			_need(role,"energy",-minutes*.02)
			if float(p.severity)>60: _health(role,-minutes*.025)
			if float(p.severity)<=0: p.illness=""
		if float(resident.age_years)<5:
			p.care=maxf(0,float(p.care)-minutes*.035)
			if float(p.care)<25: _need(role,"social",-minutes*.08); _need(role,"comfort",-minutes*.05)
		if homes.has(home) and _position(role).distance_to(_vec(_venues.get(home,{}).get("position",[0,0,0])))<25:
			if int(homes[home].dishes)>8: _need(role,"comfort",-minutes*.03)

func _mirror() -> void:
	if not is_instance_valid(game.city): return
	for id: String in objects:
		var o:Dictionary=objects[id]
		if game.city.owns(id): game.city.set_object_state(id,{"condition":o.condition,"cleanliness":o.cleanliness,"fuel":o.fuel})
		if _records.has(id): _visual.update_fire(id,_vec(_records[id].position),float(o.fire))
	for home: String in homes:
		_visual.set_laundry("home_"+home+"_drying_line",int(homes[home].hanging)+int(homes[home].dry)>0)

func _row(role: String, action: String, id: String, extra: Dictionary={}) -> Dictionary:
	var payload:Dictionary=extra.duplicate(true)
	payload.target_id=id
	var s:=spec(role,action,payload)
	return {"id":"home:"+action,"label":str(s.label),"enabled":bool(s.ok),"reason":str(s.reason),"target_id":id,"payload":payload}

func context_actions(id: String, role: String) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if id=="life_clinic": result.append(_row(role,"doctor",id)); return result
	if not objects.has(id): return result
	var o:Dictionary=objects[id]
	if not _access(role,str(o.home)): return result
	if float(o.fire)>0: result.append(_row(role,"extinguish",id)); return result
	for verb: String in ["clean","repair","upgrade"]: result.append(_row(role,verb,id))
	if float(o.condition)<=0: return result
	var verbs: Array=[]
	match str(o.kind):
		"hearth","cauldron","kiln","campfire":
			verbs=["fuel","douse" if bool(o.lit) else "light"]
			for recipe: String in Catalog.RECIPES:
				var row:=_row(role,"cook",id,{"recipe_id":recipe})
				row.id="home:cook:"+recipe
				row.label="Приготовить: "+str(Catalog.RECIPES[recipe].name)+" · 4 порции"
				result.append(row)
		"dining","table": verbs=["eat","serve_food","wash_dishes"]
		"pantry","storage": verbs=["eat","store_food","discard_food"]
		"basket": verbs=["collect_laundry","change_linen"]
		"wash_tub": verbs=["wash_laundry","wash_dishes"]
		"drying_line": verbs=["hang_laundry","fold_laundry"]
		"bed": verbs=["change_linen","remove_cloak" if bool(people.get(role,{}).get("warm_clothes",false)) else "warm_clothes","herbal_care","rest"]
		"cradle": verbs=["feed_child","change_child","soothe_child"]
	for verb: String in verbs: result.append(_row(role,verb,id))
	return result

func actions(id: String, role: String) -> Array[Dictionary]:
	return context_actions(id,role)

func ui_state(role: String) -> Dictionary:
	var home:=_home(role)
	var h:Dictionary=homes.get(home,_new_home())
	var result:Dictionary={"summary":{"name":"Домашнее хозяйство","home_id":home,"dishes":h.dishes,"dirty_laundry":floori(float(h.dirty_laundry)),"clean_linen":h.clean_linen,"chores_done":h.chores_done},"objects":[],"meals":[],"care":[],"events":events.duplicate(true)}
	for id: String in objects:
		var o:Dictionary=objects[id]
		if str(o.home)!=home: continue
		var details:Array=["Прочность %d · чистота %d · улучшение %d"%[roundi(o.condition),roundi(o.cleanliness),o.upgrade]]
		if str(o.kind) in Catalog.HEAT: details.append("Дрова %d · %s"%[roundi(o.fuel),"горит" if bool(o.lit) else "погашен"])
		if float(o.fire)>0: details.append("ПОЖАР — нужна вода")
		if str(o.kind) in ["basket","wash_tub","drying_line"]: details.append("Бельё: грязное %d · собрано %d · мокрое %d · сушится %d · сухое %d · чистое %d"%[floori(h.dirty_laundry),h.collected,h.wet,h.hanging,h.dry,h.clean_linen])
		if str(o.kind) in ["dining","table"]: details.append("Грязных тарелок: "+str(h.dishes))
		result.objects.append({"id":id,"name":str(_records[id].name),"details":details,"actions":context_actions(id,role)})
	for id: String in meals:
		var b:Dictionary=meals[id]
		if str(b.home)!=home: continue
		var storage:=_find(home,["pantry","storage"])
		var table:=_find(home,["dining","table"])
		var available:Array=[]
		if float(b.freshness)<=0: available.append(_row(role,"discard_food",storage,{"batch_id":id}))
		else:
			available.append(_row(role,"eat",table,{"batch_id":id}))
			available.append(_row(role,"store_food" if str(b.location)=="table" else "serve_food",storage if str(b.location)=="table" else table,{"batch_id":id}))
		result.meals.append({"id":id,"name":str(Catalog.RECIPES[b.recipe].name),"details":["Порций %d · качество %d · %s"%[b.portions,roundi(b.quality),"в кладовой" if str(b.location)=="pantry" else "на столе"],"Испорчено" if float(b.freshness)<=0 else "Свежесть: ещё %.0f мин при комнатной температуре"%float(b.freshness)],"actions":available})
	for id: String in _family(role).get("members",[]):
		if not people.has(id): continue
		var p:Dictionary=people[id]
		var details:Array=[str(Catalog.DISEASES.get(p.illness,"Здоров"))+" · тяжесть "+str(roundi(p.severity)),"Бельё %d · сырость %d · %s"%[roundi(p.linen),roundi(p.wetness),"тёплая накидка" if bool(p.warm_clothes) else "обычная одежда"]]
		var available:Array=[]
		if float(_sim().residents[id].age_years)<5:
			var cradle:=_find(home,["cradle"])
			for verb:String in ["feed_child","change_child","soothe_child"]: available.append(_row(role,verb,cradle,{"child_id":id}))
			details.append("Забота: "+str(roundi(p.care)))
		elif id==role: available.append(_row(role,"doctor","life_clinic"))
		result.care.append({"id":id,"name":str(_sim().residents[id].name),"details":details,"actions":available})
	return result

func _proposal(role: String) -> Dictionary:
	if not people.has(role) or not _sim().residents.has(role): return {}
	var p:Dictionary=_sim().residents[role]
	if not bool(p.alive) or float(p.age_years)<13: return {}
	var home:=_home(role)
	if not homes.has(home): return {}
	var h:Dictionary=homes[home]
	var care:Dictionary=people[role]
	for id:String in objects:
		if str(objects[id].home)==home and float(objects[id].fire)>0: return {"action":"home:extinguish","payload":{"target_id":id}}
	var child:=_child(role,{})
	if not child.is_empty():
		var c:Dictionary=_sim().residents[child]
		var verb:=""
		if float(c.needs.hunger)<60: verb="feed_child"
		elif float(c.needs.hygiene)<55 or float(c.needs.bladder)<40: verb="change_child"
		elif float(people[child].care)<55 or float(c.needs.energy)<45: verb="soothe_child"
		if not verb.is_empty(): return {"action":"home:"+verb,"payload":{"target_id":_find(home,["cradle"]),"child_id":child}}
	if float(care.severity)>25: return {"action":"home:doctor","payload":{"target_id":"life_clinic"}}
	if float(care.linen)<35 and int(h.clean_linen)>0: return {"action":"home:change_linen","payload":{"target_id":_find(home,["bed"])}}
	if float(p.needs.hunger)<65 and not _batch(home,{}).is_empty(): return {"action":"home:eat","payload":{"target_id":_find(home,["dining","table"])}}
	if not _batch(home,{},"spoiled").is_empty(): return {"action":"home:discard_food","payload":{"target_id":_find(home,["pantry","storage"])}}
	if int(h.dishes)>=4: return {"action":"home:wash_dishes","payload":{"target_id":_find(home,["wash_tub","dining"])}}
	if int(h.dry)>0: return {"action":"home:fold_laundry","payload":{"target_id":_find(home,["drying_line"])}}
	if int(h.wet)>0 and int(h.hanging)==0: return {"action":"home:hang_laundry","payload":{"target_id":_find(home,["drying_line"])}}
	if int(h.collected)>0 and int(h.wet)+int(h.hanging)<6: return {"action":"home:wash_laundry","payload":{"target_id":_find(home,["wash_tub"])}}
	if float(h.dirty_laundry)>=4: return {"action":"home:collect_laundry","payload":{"target_id":_find(home,["basket"])}}
	for id:String in objects:
		var o:Dictionary=objects[id]
		if str(o.home)!=home: continue
		if float(o.condition)<30: return {"action":"home:repair","payload":{"target_id":id}}
		if float(o.cleanliness)<40: return {"action":"home:clean","payload":{"target_id":id}}
	if float(_sim().weather.get("temperature",18))<5 and not bool(care.warm_clothes): return {"action":"home:warm_clothes","payload":{"target_id":_find(home,["bed"])}}
	if float(_sim().weather.get("temperature",18))>24 and bool(care.warm_clothes): return {"action":"home:remove_cloak","payload":{"target_id":_find(home,["bed"])}}
	if _meal_count(home)<4 and float(p.needs.hunger)<70:
		var hearth:=_find(home,["hearth","cauldron"])
		if objects.has(hearth):
			var verb:String="fuel" if float(objects[hearth].fuel)<5 else ("light" if not bool(objects[hearth].lit) else "cook")
			return {"action":"home:"+verb,"payload":{"target_id":hearth,"recipe_id":"stew"}}
	return {}

func suggest_action(role: String) -> Dictionary:
	var choice:=_proposal(role)
	if choice.is_empty() or not validate(role,str(choice.action),choice.payload).is_empty(): return {}
	return choice

func _restock_npc(role: String, action: String, payload: Dictionary) -> void:
	var cost:=_cost(_verb(action),payload,role)
	if action=="home:feed_child" and _amount(role,"milk")<1 and _amount(role,"meal")<1: cost={"milk":1}
	var household:=_family(role)
	var market:Dictionary=_sim().market
	var plan:Dictionary={}
	var total:=0
	for item:String in cost:
		var missing:int=maxi(0,int(cost[item])-_amount(role,item))
		if missing==0: continue
		if int(market.stocks.get(item,0))<missing: return
		var price:int=int(_sim().price(item,false))
		total+=missing*price
		plan[item]={"count":missing,"price":price}
	if int(household.get("coins",0))<total: return
	for item:String in plan:
		var count:int=int(plan[item].count)
		market.stocks[item]=int(market.stocks[item])-count
		household.inventory[item]=int(household.inventory.get(item,0))+count
		household.coins=int(household.coins)-count*int(plan[item].price)
		household.expenses=int(household.expenses)+count*int(plan[item].price)
		market.treasury=int(market.treasury)+count*int(plan[item].price)

func _start_npc_chores() -> void:
	if jobs.size()>=4: return
	for role:String in _sim().residents:
		var p:Dictionary=_sim().residents[role]
		if game.state.characters.has(role) or jobs.has(role) or not bool(p.autonomy) or bool(p.get("busy",false)) or not p.current_action.is_empty() or not p.queue.is_empty(): continue
		if not str(p.get("social_holder","")).is_empty() or float(p.needs.energy)<15: continue
		var choice:=_proposal(role)
		if choice.is_empty(): continue
		_restock_npc(role,str(choice.action),choice.payload)
		var s:=spec(role,str(choice.action),choice.payload)
		if float(p.get("blocked",{}).get(str(s.venue_id),0))>clock: continue
		if not bool(s.ok) or not reserve(role,str(s.venue_id),float(s.duration)+300): continue
		var route:PackedVector3Array=game.navigation.path(_position(role),s.target)
		if route.is_empty() or route[-1].distance_to(s.target)>2: release(role); continue
		var path:Array=[]
		for point:Vector3 in route: path.append(_arr(point))
		jobs[role]={"action":str(choice.action),"payload":choice.payload.duplicate(true),"target":_arr(s.target),"venue_id":str(s.venue_id),"duration":float(s.duration),"remaining":float(s.duration),"phase":"walking","path":path,"index":0,"waited":0.0,"animation":str(s.animation)}
		_sim().set_busy(role,true)
		if jobs.size()>=4: break

func npc_target(role: String) -> Dictionary:
	if not jobs.has(role): return {}
	var job:Dictionary=jobs[role]
	return {"id":job.venue_id,"position":job.target.duplicate(),"action":job.action,"phase":job.phase,"animation":job.animation}

func _cancel_job(role: String) -> void:
	if _sim().residents.has(role) and jobs.has(role): _sim().set_busy(role,false)
	jobs.erase(role)
	release(role)

func report_unreachable(role: String, venue_id: String="") -> void:
	if not jobs.has(role): return
	if venue_id.is_empty(): venue_id=str(jobs[role].venue_id)
	if _sim().residents.has(role): _sim().residents[role].blocked[venue_id]=clock+120
	_cancel_job(role)

func _tick_jobs(minutes: float) -> void:
	for role:String in jobs.keys():
		if not _sim().residents.has(role) or not bool(_sim().residents[role].alive) or game.state.characters.has(role): _cancel_job(role); continue
		var job:Dictionary=jobs[role]
		var s:=spec(role,str(job.action),job.payload)
		if not bool(s.ok): _cancel_job(role); continue
		_sim().set_busy(role,true)
		reserve(role,str(job.venue_id),float(job.remaining)+30)
		var target:Vector3=s.target
		if target.distance_to(_vec(job.target))>2:
			var route:PackedVector3Array=game.navigation.path(_position(role),target)
			if route.is_empty() or route[-1].distance_to(target)>2: _cancel_job(role); continue
			job.path=[]
			for point:Vector3 in route: job.path.append(_arr(point))
			job.index=0; job.target=_arr(target); job.phase="walking"
		var distance:float=Vector2(_position(role).x,_position(role).z).distance_to(Vector2(target.x,target.z))
		if distance>2:
			job.phase="walking"; job.waited=float(job.waited)+minutes
			if float(job.waited)>600: _cancel_job(role); continue
			if game.life.citizens.has(role) and is_instance_valid(game.life.citizens[role]): continue
			var point:=_position(role)
			var movement:float=minutes*4.5
			while int(job.index)<job.path.size() and movement>0:
				var waypoint:=_vec(job.path[int(job.index)])
				var step:float=minf(point.distance_to(waypoint),movement)
				point=point.move_toward(waypoint,step); movement-=step
				if point.distance_to(waypoint)<.1: job.index=int(job.index)+1
			point.y=float(game.world.sample_height(point.x,point.z))
			_sim().set_position(role,point)
			continue
		job.phase="working"
		job.remaining=maxf(0,float(job.remaining)-minutes)
		if float(job.remaining)<=0:
			var result:=complete(role,str(job.action),job.payload)
			if bool(result.get("ok",false)): _sim()._skill(role,str(result.skill),float(result.xp))
			_cancel_job(role)

func snapshot() -> Dictionary:
	return {"version":1,"clock":clock,"next_batch":next_batch,"objects":objects.duplicate(true),"homes":homes.duplicate(true),"people":people.duplicate(true),"meals":meals.duplicate(true),"jobs":jobs.duplicate(true),"events":events.duplicate(true)}

func restore_object_condition(id: String, saved: Dictionary) -> void:
	if not objects.has(id): return
	var value:Variant=saved.get("objects",{}).get(id,{}) if saved.has("objects") and saved.objects is Dictionary else saved
	if not value is Dictionary: return
	var o:Dictionary=value
	if not o.get("lit") is bool: return
	for key:String in ["condition","cleanliness","fuel","fire"]:
		if not _number(o.get(key),0,100): return
	if not _number(o.get("hazard"),0,100000) or not _integer(o.get("upgrade"),0,2) or not _integer(o.get("uses")): return
	for key:String in ["condition","cleanliness","fuel","fire","hazard","lit","upgrade","uses"]: objects[id][key]=o[key]
	_mirror()

func _number(value: Variant, low: float=0, high: float=1000000000.0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

func _integer(value: Variant, low: int=0, high: int=1000000) -> bool:
	return _number(value,low,high) and floorf(float(value))==float(value)

func _vector_valid(value: Variant) -> bool:
	if not value is Array or value.size()!=3: return false
	for component:Variant in value:
		if not _number(component,-100000,100000): return false
	return true

func valid_snapshot(data: Variant) -> bool:
	if not data is Dictionary: return false
	if data.is_empty(): return true
	if not _integer(data.get("version"),1,1) or not _number(data.get("clock")) or not _integer(data.get("next_batch"),1): return false
	for section:String in ["objects","homes","people","meals","jobs"]:
		if not data.get(section) is Dictionary or data[section].size()>2000: return false
	for id:Variant in data.objects:
		if not id is String or not data.objects[id] is Dictionary: return false
		var o:Dictionary=data.objects[id]
		if not o.get("kind") in Catalog.MAINTAINED or not o.get("home") is String or not o.get("lit") is bool: return false
		for key:String in ["condition","cleanliness","fuel","fire"]:
			if not _number(o.get(key),0,100): return false
		if not _number(o.get("hazard"),0,100000) or not _integer(o.get("upgrade"),0,2) or not _integer(o.get("uses")): return false
	for id:Variant in data.homes:
		if not id is String or not data.homes[id] is Dictionary: return false
		var h:Dictionary=data.homes[id]
		if not _number(h.get("dirty_laundry"),0,100) or not _number(h.get("drying"),0,120): return false
		for key:String in ["collected","wet","hanging","dry","clean_linen","dishes","chores_done"]:
			if not _integer(h.get(key),0,1000000 if key=="chores_done" else 100): return false
	for id:Variant in data.people:
		if not id is String or not data.people[id] is Dictionary: return false
		var p:Dictionary=data.people[id]
		if not Catalog.DISEASES.has(str(p.get("illness","?"))) or not p.get("warm_clothes") is bool or not p.get("cloak_owned") is bool: return false
		for key:String in ["linen","wetness","severity","care"]:
			if not _number(p.get(key),0,100): return false
		for key:String in ["cold","heat"]:
			if not _number(p.get(key),0,500): return false
		if not _number(p.get("treatment"),0,10000): return false
	for id:Variant in data.meals:
		if not id is String or not data.meals[id] is Dictionary: return false
		var b:Dictionary=data.meals[id]
		if str(b.get("id",""))!=id or not Catalog.RECIPES.has(str(b.get("recipe",""))) or not data.homes.has(str(b.get("home",""))): return false
		if not _integer(b.get("portions"),1,4) or not _number(b.get("quality"),0,100) or not _number(b.get("freshness"),0,10000) or not _number(b.get("made")): return false
		if not b.get("location") in ["table","pantry"]: return false
	for role:Variant in data.jobs:
		if not role is String or not data.jobs[role] is Dictionary or not data.people.has(role): return false
		var j:Dictionary=data.jobs[role]
		if not Catalog.ACTIONS.has(_verb(str(j.get("action","")))) or not j.get("payload") is Dictionary: return false
		for key:String in ["target_id","child_id","recipe_id","batch_id"]:
			if j.payload.has(key) and not j.payload[key] is String: return false
		if not _vector_valid(j.get("target")) or not j.get("venue_id") is String or not j.get("phase") in ["walking","working"] or not j.get("animation") is String: return false
		for key:String in ["duration","remaining","waited"]:
			if not _number(j.get(key),0,10000): return false
		if not j.get("path") is Array or j.path.size()>5000 or not _integer(j.get("index"),0,j.path.size()): return false
		for point:Variant in j.path:
			if not _vector_valid(point): return false
	if not data.get("events") is Array or data.events.size()>40: return false
	for e:Variant in data.events:
		if not e is Dictionary or not _number(e.get("time")) or not e.get("message") is String or not e.get("home") is String: return false
	return true

func restore(data: Dictionary) -> void:
	if not valid_snapshot(data): return
	var saved:Dictionary=data.duplicate(true)
	for role:String in jobs.keys(): _cancel_job(role)
	for id:String in _fixtures.keys():
		var home:String=str(_fixtures[id].home)
		if str(_venues.get(home,{}).get("kind",""))=="plot" and not saved.get("objects",{}).has(id):
			_visual.remove_fixture(id)
			_fixtures.erase(id); _records.erase(id); _sim().venues.erase(id)
	objects.clear(); homes.clear(); people.clear(); meals.clear(); jobs.clear(); reservations.clear(); events.clear()
	_visual.clear_fires()
	clock=float(_sim().clock); next_batch=1; _step=0; _refresh=0; _chores=0
	sync_objects()
	if saved.is_empty(): return
	clock=float(saved.clock); next_batch=int(saved.next_batch)
	for id:String in saved.objects:
		if objects.has(id):
			var kind:String=str(objects[id].kind)
			var home:String=str(objects[id].home)
			objects[id]=saved.objects[id].duplicate(true)
			objects[id].kind=kind; objects[id].home=home
	for id:String in saved.homes:
		if homes.has(id): homes[id]=saved.homes[id].duplicate(true)
	for role:String in saved.people:
		if people.has(role): people[role]=saved.people[role].duplicate(true)
	for id:String in saved.meals:
		if not homes.has(str(saved.meals[id].home)): continue
		meals[id]=saved.meals[id].duplicate(true)
		if id.begins_with("dish_"): next_batch=maxi(next_batch,int(id.trim_prefix("dish_"))+1)
	events=saved.events.duplicate(true)
	for role:String in saved.jobs:
		if not people.has(role) or game.state.characters.has(role): continue
		var job:Dictionary=saved.jobs[role].duplicate(true)
		var s:=spec(role,str(job.action),job.payload)
		if not bool(s.ok) or not reserve(role,str(s.venue_id),float(job.remaining)+300): continue
		jobs[role]=job
		_sim().set_busy(role,true)
	_mirror()

func _exit_tree() -> void:
	if game and is_instance_valid(game):
		for role:String in jobs.keys(): _cancel_job(role)
