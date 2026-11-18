extends RefCounted
## Authoritative, scene-independent life simulation. Every resident has one persistent record.
const Catalog = preload("res://scripts/life_catalog.gd")
const Population = preload("res://scripts/life_population.gd")

var residents:Dictionary={}
var households:Dictionary={}
var venues:Dictionary={}
var professions:Dictionary={}
var market:Dictionary={}
var businesses:Dictionary={}
var reservations:Dictionary={}
var events:Array[Dictionary]=[]
var calendar_events:Array[Dictionary]=[]
var clock:float=1920.0
var weather:Dictionary={"id":"clear","temperature":18.0,"season":0}
var settings:Dictionary={"aging":true,"family_growth":true,"days_per_age_year":28.0,"population_limit":96}
var command_policy:Callable=Callable()
var command_observer:Callable=Callable()
var domestic_care_enabled:=false
var controllers:Dictionary={"local":"house_player"}
var _bindings:Dictionary={}
var _base_venues:Dictionary={}
var _external_motion:Dictionary={}
var _rng:=RandomNumberGenerator.new()
var _next_person:int=49
var _next_event:int=1
var _day:int=1
var _requests:Dictionary={}
var _configured:bool=false


func configure(config:Dictionary)->void:
	if _configured: return
	_configured=true
	_rng.seed=int(config.get("seed",782941))
	clock=float(config.get("absolute_minutes",1920.0))
	_day=maxi(1,floori(clock/1440.0))
	venues=config.get("venues",{}).duplicate(true)
	for profession:String in config.get("workplaces",{}):
		var station:Dictionary=config.workplaces[profession].duplicate(true)
		var id:String=str(station.get("id","life_job_"+profession))
		station.id=id
		if station.has("approach"): station.position=station.approach.duplicate()
		if not station.has("kind"): station.kind=str(station.get("prop","workplace"))
		if not station.has("parent"): station.parent=Catalog.City.PROFESSION_VENUES.get(profession,"")
		if not station.has("capacity"): station.capacity=1
		venues[id]=station
	if not venues.has("life_player_home"):
		venues.life_player_home={"id":"life_player_home","kind":"home","name":"Хозяйство у фермы Марты","position":[3995.0,67.0,4426.0],"capacity":8,"safe":true,"price":0}
	_base_venues=venues.duplicate(true)
	professions=Catalog.professions()
	var population:Dictionary=Population.create(venues,int(config.get("seed",782941)))
	residents=population.residents
	households=population.households
	market={"stocks":{},"treasury":1000000,"turnover":0,"production":{},"consumed":{},"services":{"community":0.0,"education":0.0,"safety":65.0,"culture":0.0}}
	for item:String in Catalog.GOODS: market.stocks[item]=int(Catalog.GOODS[item].stock)
	for profession:String in professions:
		var venue:String=str(professions[profession].venue_id)
		if not businesses.has(venue): businesses[venue]={"id":venue,"owner":"","price":360+int(professions[profession].wage)*3,"markup":1.0,"profits":0,"employees":[]}
	for id:String in residents:
		residents[id].workplace_id=_workplace(str(residents[id].profession))
		residents[id]["death_age"]=82.0+_rng.randf()*10
		residents[id]["married"]=not str(residents[id].partner_id).is_empty()
	_refresh_weather()
	_schedule("fair",clock+1440,[],"life_market","Городская ярмарка")
	_event("settlement","Арденхольм просыпается",["48 жителей ведут хозяйство, учатся и работают независимо от камеры."],[])


func register_player(id:String,person:Dictionary,household_id:String="house_player")->void:
	if not households.has(household_id): return
	if not residents.has(id):
		var title:String=str(person.get("name","Брат" if id=="brother" else ("Сестра" if id=="sister" else id)))
		residents[id]=Population.person(id,title,24 if id=="brother" else (10 if id=="sister" else 25),"male" if id=="brother" else "female",household_id,str(households[household_id].home_id),_point_array(str(households[household_id].home_id)))
		residents[id].traits=["family","curious"] if Catalog.TRAITS.has("curious") else ["family","friendly"]
	var p:Dictionary=residents[id]
	if str(p.household_id)!=household_id: _join_household(id,household_id)
	p.external=true
	p.household_id=household_id
	p.home_id=households[household_id].home_id
	if not households[household_id].members.has(id): households[household_id].members.append(id)
	_bindings[id]=person
	if not person.get("inventory") is Dictionary: person.inventory={}
	if not person.get("skills") is Dictionary: person.skills={}
	p.inventory=person.inventory
	p.skills=person.skills
	_sync_hero(id)
	if id in ["brother","sister"]:
		var sibling:String="sister" if id=="brother" else "brother"
		p["siblings"]=[sibling]
		if residents.has(sibling): _relationship(id,sibling).friendship=70.0


func sync_player(id:String,person:Dictionary,position:Vector3)->void:
	if not residents.has(id) or not _bindings.has(id) or not is_same(_bindings[id],person): register_player(id,person)
	_sync_hero(id)
	set_position(id,position)


func _sync_hero(id:String)->void:
	if not _bindings.has(id) or not residents.has(id): return
	var live:Dictionary=_bindings[id]
	var p:Dictionary=residents[id]
	for key:String in ["hunger","thirst"]: p.needs[key]=float(live.get(key,p.needs[key]))
	p.needs.energy=float(live.get("sleep",p.needs.energy))
	p.health=float(live.get("health",p.health))
	for key:String in ["hygiene","bladder","social","fun","comfort"]:
		if live.has(key): p.needs[key]=float(live[key])
		else: live[key]=float(p.needs[key])
	p.inventory=live.inventory
	p.skills=live.skills


func set_position(id:String,position:Vector3)->void:
	if residents.has(id) and position.is_finite(): residents[id].position=[position.x,position.y,position.z]


func position_of(id:String)->Vector3:
	return _vector(residents[id].position) if residents.has(id) else Vector3.ZERO


func set_external_motion(id:String,enabled:bool)->void:
	if enabled: _external_motion[id]=true
	else: _external_motion.erase(id)


func set_busy(id:String,busy:bool)->void:
	if residents.has(id): residents[id]["busy"]=busy


func set_social_hold(id:String,holder_id:String)->void:
	if not residents.has(id): return
	if not holder_id.is_empty() and not residents.has(holder_id): return
	residents[id]["social_holder"]=holder_id


func next_target(id:String)->Dictionary:
	if not residents.has(id) or residents[id].current_action.is_empty(): return {}
	var action:Dictionary=residents[id].current_action
	if action.payload.has("target_id") and residents.has(str(action.payload.target_id)):
		action.target=residents[action.payload.target_id].position.duplicate()
	return {"id":action.venue_id,"position":action.target.duplicate(),"action":action.action,"animation":action.animation,"phase":action.phase}


func report_unreachable(id:String,venue_id:String)->void:
	if not residents.has(id): return
	residents[id].blocked[venue_id]=clock+60.0
	residents[id].current_action={}
	release(id)


func _workplace(profession:String)->String:
	if profession.is_empty() or not professions.has(profession): return ""
	var station:String="life_job_"+profession
	return station if venues.has(station) else str(professions[profession].venue_id)


func _hire_profession(business_id:String,worker:Dictionary,reserved:Dictionary={})->String:
	# Keep a worker's existing role at this workplace; otherwise fill an unstaffed role instead of always the first catalog entry.
	var current:String=str(worker.get("profession",""))
	if professions.has(current) and str(professions[current].venue_id)==business_id:
		return current
	var taken:Dictionary=reserved.duplicate()
	for worker_id in businesses.get(business_id,{}).get("employees",[]):
		if not residents.has(str(worker_id)): continue
		var job:String=str(residents[worker_id].profession)
		if professions.has(job) and str(professions[job].venue_id)==business_id:
			taken[job]=true
	var fallback:String=""
	for job:String in professions:
		if str(professions[job].venue_id)!=business_id: continue
		if fallback.is_empty(): fallback=job
		if not taken.has(job): return job
	return fallback


func _point_array(venue_id:String)->Array:
	return venues.get(venue_id,{}).get("position",[3510.0,65.0,3698.0]).duplicate()


func _vector(value:Array)->Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))


func _distance(a:Vector3,b:Vector3)->float:
	return Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))


func _adult(p:Dictionary)->bool:
	return float(p.age_years)>=18 and bool(p.alive)


func _kin(a:Dictionary,b:Dictionary)->bool:
	if a.id==b.id or a.parents.has(b.id) or b.parents.has(a.id) or a.get("siblings",[]).has(b.id): return true
	for parent in a.parents:
		if b.parents.has(parent): return true
	return false


func _controlled(id:String,issuer:String)->bool:
	return residents.has(id) and controllers.get(issuer,"")==residents[id].household_id


func _is_work_time(profession:String)->bool:
	if not professions.has(profession): return false
	var job:Dictionary=professions[profession]
	if not job.days.has((_day-1)%7): return false
	var hour:float=fmod(clock,1440.0)/60.0
	return hour>=float(job.start) and hour<float(job.end) if int(job.start)<int(job.end) else hour>=float(job.start) or hour<float(job.end)


func command_spec(actor_id:String,action:String,payload:Dictionary={})->Dictionary:
	var result:Dictionary={"ok":false,"reason":"","target":Vector3.ZERO,"venue_id":"","duration":0.0,"animation":"interact","portable":false}
	if not _finite_tree(payload): result.reason="Команда содержит недопустимые данные."; return result
	for key:String in ["target_id","venue_id","profession_id","item_id","home_id","business_id","worker_id","request_id"]:
		if payload.has(key) and not payload[key] is String: result.reason="Неверный идентификатор команды."; return result
	if payload.has("quantity") and (not _numeric(payload.quantity) or float(payload.quantity)!=floorf(float(payload.quantity))): result.reason="Количество должно быть целым числом."; return result
	if not residents.has(actor_id) or not bool(residents[actor_id].alive): result.reason="Персонаж недоступен."; return result
	if not Catalog.ACTIONS.has(action): result.reason="Такое действие пока не поддерживается."; return result
	var p:Dictionary=residents[actor_id]
	var def:Dictionary=Catalog.ACTIONS[action]
	result.duration=float(def.duration)
	result.animation=str(def.animation)
	result.portable=bool(def.get("portable",false))
	result.target=position_of(actor_id)
	var target_id:String=str(payload.get("target_id",""))
	if action in Catalog.SOCIAL:
		if not residents.has(target_id) or target_id==actor_id or not bool(residents[target_id].alive): result.reason="Выберите другого живого жителя."; return result
		var other:Dictionary=residents[target_id]
		if not str(other.get("social_holder","")).is_empty() and other.social_holder!=actor_id: result.reason="Собеседник уже ведёт разговор."; return result
		if bool(other.get("busy",false)): result.reason="Собеседник занят."; return result
		if not other.current_action.is_empty() and other.current_action.action in ["work","sleep"]: result.reason="Собеседник сейчас работает или спит."; return result
		result.target=position_of(target_id)
		result.venue_id="person:"+target_id
		if action in ["flirt","propose","plan_child"]:
			if not _adult(p) or not _adult(other) or _kin(p,other): result.reason="Это взаимодействие доступно только неродственным взрослым."; return result
		if action=="propose" and (not str(p.partner_id).is_empty() or not str(other.partner_id).is_empty() or float(_relationship(actor_id,target_id).friendship)<40 or float(_relationship(actor_id,target_id).romance)<35): result.reason="Нужны свободные взрослые и взаимная близость."; return result
		if action=="plan_child":
			if p.partner_id!=target_id or str(p.household_id)!=str(other.household_id): result.reason="Нужны партнёры в одном хозяйстве."; return result
			if float(p.family_plan_due)>=0 or float(other.family_plan_due)>=0 or households[p.household_id].members.size()>=8: result.reason="Семья уже ожидает ребёнка или дом заполнен."; return result
		if action=="educate" and (float(other.age_years)>=18 or not _adult(p)): result.reason="Взрослый может помогать ребёнку с учёбой."; return result
		if action=="invite_household":
			if not _adult(other) or other.household_id==p.household_id or float(_relationship(actor_id,target_id).friendship)<40 or households[p.household_id].members.size()>=8: result.reason="Нужна дружба со взрослым жителем и свободное место в хозяйстве."; return result
	else:
		var venue_id:String=str(payload.get("venue_id",""))
		if venue_id.is_empty(): venue_id=_default_venue(p,action,payload)
		if not result.portable:
			if not venues.has(venue_id): result.reason="Подходящее место недоступно."; return result
			var privacy:String=_privacy_reason(p,venue_id)
			if not privacy.is_empty(): result.reason=privacy; return result
			if not _venue_allows(venue_id,action,p,payload): result.reason="Это место не подходит для выбранного действия."; return result
			result.venue_id=venue_id
			result.target=_vector(_point_array(venue_id))
	var inv:Dictionary=p.inventory
	var home:Dictionary=households[p.household_id]
	if action=="eat" and _food_item(p).is_empty(): result.reason="Нет еды в рюкзаке, кладовой или доступных средств на хлеб."; return result
	if action=="cook" and _cook_recipe(inv).is_empty(): result.reason="Нужны морковь и дрова, либо мука и вода в рюкзаке."; return result
	if action=="work":
		var profession:String=str(payload.get("profession_id",p.profession))
		if profession!=p.profession or not professions.has(profession): result.reason="Сначала устройтесь на эту работу."; return result
		if not _is_work_time(profession): result.reason="Сейчас нерабочее время этой профессии."; return result
		for item:String in professions[profession].inputs:
			if int(market.stocks.get(item,0))<int(professions[profession].inputs[item]): result.reason="Мастерской не хватает: "+str(Catalog.GOODS[item].name); return result
		if float(p.needs.energy)<12 or float(p.needs.hunger)<10: result.reason="Сначала восстановите силы и поешьте."; return result
	if action=="apply_job":
		if not professions.has(str(payload.get("profession_id",""))) or not _adult(p): result.reason="Профессия доступна взрослому жителю."; return result
	if action in ["buy","sell"]:
		var item:String=str(payload.get("item_id",""))
		var amount:int=int(payload.get("quantity",1))
		if not Catalog.GOODS.has(item) or amount<1 or amount>100: result.reason="Выберите товар и количество от 1 до 100."; return result
		var cost:int=price(item,action=="sell")*amount
		if action=="buy" and (int(market.stocks.get(item,0))<amount or int(home.coins)<cost): result.reason="Недостаточно товара или семейных средств."; return result
		if action=="sell" and (int(inv.get(item,0))<amount or int(market.treasury)<cost): result.reason="Нет нужного количества товара или денег у рынка."; return result
	if action in ["buy_home","move_home"]:
		var home_id:String=str(payload.get("home_id",""))
		if not venues.has(home_id) or str(venues[home_id].get("kind","")) not in ["home","plot"]: result.reason="Нужно выбрать дом или земельный участок."; return result
		if action=="buy_home" and (not _home_owner(home_id).is_empty() or int(home.coins)<int(venues[home_id].get("price",200))): result.reason="Дом уже занят или не хватает средств."; return result
		if action=="move_home" and not home.properties.has(home_id): result.reason="Этот дом не принадлежит хозяйству."; return result
	if action in ["adopt","create_member"] and (home.members.size()>=8 or residents.size()>=int(settings.population_limit)): result.reason="В хозяйстве или поселении пока нет свободного места."; return result
	if action=="adopt" and not _adult(p): result.reason="Ребёнка принимает взрослый житель."; return result
	if action=="edit_profile":
		var error:String=_profile_error(payload)
		if not error.is_empty(): result.reason=error; return result
	if action=="create_member":
		var error:String=_profile_error(payload)
		if not error.is_empty(): result.reason=error; return result
	if action in ["buy_workshop","hire_worker","set_price"]:
		var business_id:String=str(payload.get("business_id",""))
		if not businesses.has(business_id): result.reason="Выберите действующую мастерскую или предприятие."; return result
		var business:Dictionary=businesses[business_id]
		if not _adult(p): result.reason="Предприятие может вести взрослый житель."; return result
		if action=="buy_workshop" and (not str(business.owner).is_empty() or int(home.coins)<int(business.price)): result.reason="Предприятие занято или не хватает семейных средств."; return result
		if action!="buy_workshop" and business.owner!=p.household_id: result.reason="Предприятие не принадлежит вашему хозяйству."; return result
		if action=="set_price" and (not _numeric(payload.get("markup",1.0)) or float(payload.get("markup",1.0))<.75 or float(payload.get("markup",1.0))>1.5): result.reason="Допустимая наценка: от 0,75 до 1,50."; return result
		if action=="hire_worker":
			var worker_id:String=str(payload.get("worker_id","")); var profession:String=str(payload.get("profession_id",""))
			if not residents.has(worker_id) or not _adult(residents[worker_id]) or bool(residents[worker_id].external): result.reason="Выберите взрослого самостоятельного жителя."; return result
			if not professions.has(profession) or professions[profession].venue_id!=business_id: result.reason="Эта профессия не относится к предприятию."; return result
			if business.employees.has(worker_id): result.reason="Этот житель уже нанят здесь."; return result
	if command_policy.is_valid():
		var policy_reason:String=str(command_policy.call(actor_id,action,payload,result))
		if not policy_reason.is_empty(): result.reason=policy_reason; return result
	result.ok=true
	return result


func _default_venue(p:Dictionary,action:String,payload:Dictionary)->String:
	if action in ["buy_workshop","hire_worker","set_price"]: return str(payload.get("business_id",""))
	if action in ["work","apply_job"]: return _workplace(str(payload.get("profession_id",p.profession)))
	if action in ["buy","sell"]: return "life_south_market" if str(p.home_id) in ["life_home_17","life_home_18","life_home_19","life_home_20"] and venues.has("life_south_market") else "life_market"
	var home_fixture:String=_fixture(p,action,str(p.home_id))
	if not home_fixture.is_empty() and action in ["eat","drink","wash","toilet","sleep","cook","relax"]: return home_fixture
	if action=="wash": return _service_target(p,action,_nearest_venue(p.position,["bathhouse","washbasin","bath","well"],p))
	if action=="read": return _service_target(p,action,"life_school" if float(p.age_years)<18 else "life_library")
	if action=="study": return _service_target(p,action,"life_school")
	if action=="cook": return _service_target(p,action,"life_kitchen")
	if action=="train": return _service_target(p,action,"life_watch")
	if action=="relax": return _service_target(p,action,"life_square")
	if action=="adopt": return "life_town_hall"
	return str(p.home_id)


func _service_target(p:Dictionary,action:String,parent:String)->String:
	var fixture:String=_fixture(p,action,parent)
	return fixture if not fixture.is_empty() else parent


func _fixture(p:Dictionary,action:String,parent:String)->String:
	var best:float=INF; var found:String=""; var occupied_fallback:String=""
	for id:String in venues:
		if str(venues[id].get("parent",""))!=parent or not _venue_allows(id,action,p,{}): continue
		var claims:Array=reservations.get(id,[]); var occupied:int=0
		for claim:Dictionary in claims:
			if float(claim.expires)>clock and claim.actor_id!=p.id: occupied+=1
		if occupied>=int(venues[id].get("capacity",1)): occupied_fallback=id; continue
		var distance:float=_distance(_vector(p.position),_vector(_point_array(id)))
		if distance<best: best=distance; found=id
	return found if not found.is_empty() else occupied_fallback


func _privacy_reason(p:Dictionary,venue_id:String)->String:
	var venue:Dictionary=venues.get(venue_id,{})
	var home_id:String=venue_id if str(venue.get("kind","")) in ["home","plot"] else str(venue.get("parent",""))
	if not venues.has(home_id) or str(venues[home_id].get("kind","")) not in ["home","plot"]: return ""
	var owner:String=_home_owner(home_id)
	if owner.is_empty() or owner==p.household_id: return ""
	for member:String in households[owner].members:
		if float(p.relationships.get(member,{}).get("friendship",0))>=40: return ""
	return "Это чужой дом. Сначала подружитесь с его хозяевами."


func _venue_allows(id:String,action:String,p:Dictionary,payload:Dictionary)->bool:
	var venue:Dictionary=venues[id]
	var kind:String=str(venue.get("kind",""))
	if action in ["buy_workshop","hire_worker"]: return id==str(payload.get("business_id",""))
	if action in ["work","apply_job"]:
		var job:String=str(payload.get("profession_id",p.profession))
		return professions.has(job) and (id==_workplace(job) or id==professions[job].venue_id or str(venue.get("parent",""))==professions[job].venue_id or venue.get("professions",[]).has(job))
	match action:
		"buy","sell": return kind in ["market","stall","shop","counter"]
		"eat": return kind in ["home","tavern","kitchen","market","bakery","table","dining","dining_table","food_storage","pantry","hearth"]
		"drink": return kind in ["home","well","tavern","water","kitchen","table","bathhouse"]
		"wash": return kind in ["home","bathhouse","washbasin","bath","basin","wash","well"]
		"toilet": return kind in ["home","latrine","toilet","outhouse"]
		"sleep": return kind in ["home","bed","tavern","inn"]
		"relax": return kind in ["home","square","bench","chair","tavern","theatre","social","game_table","bed","bath"]
		"read": return kind in ["home","library","bookshelf","school","academy","lectern","writing_desk"]
		"study": return kind in ["school","library","academy","lectern","bookshelf","desk","writing_desk"]
		"cook": return kind in ["home","hearth","kitchen","tavern","oven","stove","cooking"]
		"train": return kind in ["watch","guild","training","training_dummy","weapon_rack","archery"]
		"adopt": return kind=="town_hall"
	return true


func _nearest_venue(from:Array,kinds:Array,person:Dictionary={})->String:
	var best:float=INF
	var found:String=""
	for id:String in venues:
		if not kinds.has(str(venues[id].get("kind",""))): continue
		if not person.is_empty() and not _privacy_reason(person,id).is_empty(): continue
		var distance:float=_distance(_vector(from),_vector(_point_array(id)))
		if distance<best: best=distance; found=id
	return found


func command(actor_id:String,action:String,payload:Dictionary={},issuer:String="local")->Dictionary:
	if not _controlled(actor_id,issuer): return {"ok":false,"message":"Нет права управлять этим хозяйством."}
	var request_id:String=str(payload.get("request_id",""))
	var request_key:String=issuer+":"+request_id
	if not request_id.is_empty() and _requests.has(request_key): return _requests[request_key].duplicate(true)
	var result:Dictionary=_execute(actor_id,action,payload)
	if result.get("ok",false) and not request_id.is_empty():
		_requests[request_key]=result.duplicate(true)
		if _requests.size()>512: _requests.erase(_requests.keys()[0])
	return result


func _execute(id:String,action:String,payload:Dictionary)->Dictionary:
	var spec:Dictionary=command_spec(id,action,payload)
	if not spec.ok: return {"ok":false,"message":spec.reason,"action":action,"actor_id":id}
	if not bool(spec.portable) and _distance(position_of(id),spec.target)>2.2: return {"ok":false,"message":"Сначала подойдите к месту действия.","action":action,"actor_id":id}
	if not bool(spec.portable):
		var occupied:int=0; var own_claim:bool=false
		for claim:Dictionary in reservations.get(spec.venue_id,[]):
			if float(claim.expires)<clock: continue
			if claim.actor_id==id: own_claim=true
			else: occupied+=1
		if not own_claim and occupied>=int(venues.get(spec.venue_id,{}).get("capacity",1)): return {"ok":false,"message":"Место сейчас занято.","action":action,"actor_id":id}
	var p:Dictionary=residents[id]
	var home:Dictionary=households[p.household_id]
	var inv:Dictionary=p.inventory
	var message:String=str(Catalog.ACTIONS[action].name)+" — готово."
	var extra:Dictionary={}
	match action:
		"eat":
			var food:String=_food_item(p)
			if int(inv.get(food,0))>0: inv[food]=int(inv[food])-1
			elif int(home.inventory.get(food,0))>0: home.inventory[food]=int(home.inventory[food])-1
			else:
				var cost:int=price(food)
				home.coins=int(home.coins)-cost; home.expenses=int(home.expenses)+cost
				market.treasury=int(market.treasury)+cost; market.stocks[food]=int(market.stocks[food])-1
			market.consumed[food]=int(market.consumed.get(food,0))+1
			_change_need(id,"hunger",float(Catalog.GOODS[food].get("food",35)))
			_moodlet(id,"well_fed","Сытный обед",12,180,"food")
			if p.preferences.get("food","")==food: _moodlet(id,"favorite_food","Любимое блюдо",10,180,"food")
			message="Поел: "+str(Catalog.GOODS[food].name)+"."
		"drink": _change_need(id,"thirst",60)
		"wash": _change_need(id,"hygiene",80); _change_need(id,"comfort",12); _moodlet(id,"clean","Чистота",10,240,"bath")
		"toilet": _change_need(id,"bladder",100); _change_need(id,"comfort",8)
		"sleep": _change_need(id,"energy",45); _change_need(id,"comfort",25); _moodlet(id,"rested","Отдохнул",12,240,"bed")
		"relax": _change_need(id,"fun",35); _change_need(id,"comfort",35); _change_need(id,"energy",8)
		"read":
			_change_need(id,"fun",30); _skill(id,"reading",12)
			if float(p.age_years)<18: p.education=float(p.education)+3; _skill(id,"literacy",10)
		"study":
			p.education=float(p.education)+5; _skill(id,"reading",18); _skill(id,"literacy",15); _change_need(id,"fun",12)
			_moodlet(id,"learned","Узнал новое",9,240,"school")
		"cook":
			var recipe:Dictionary=_cook_recipe(inv)
			for item:String in recipe: inv[item]=int(inv[item])-int(recipe[item])
			inv.meal=int(inv.get("meal",0))+2; _skill(id,"cooking",12); _moodlet(id,"cooked","Домашняя еда",8,120,"hearth")
			message="Приготовлено две порции похлёбки."
		"train": _change_need(id,"fun",20); _change_need(id,"energy",-8); _skill(id,"athletics",12); _skill(id,"combat",5)
		"socialize","joke","compliment","insult","apologize","flirt":
			_social(id,str(payload.target_id),action)
		"work":
			var job:Dictionary=professions[p.profession]
			var multiplier:float=_trait_product(p,"productivity")*(.85+maxf(-30,float(p.mood))*.002)*(1+float(Catalog.skill_level(float(p.skills.get(job.skill,0)))-1)*.05)
			if weather.id in ["rain","storm","snow"] and p.profession in ["farmer","gardener","hunter","lumberjack","fisher","shepherd"]: multiplier*=.85
			var wage:int=maxi(1,roundi(float(job.wage)/8.0*multiplier*(1+.08*(int(p.career.level)-1))))
			if int(market.treasury)<wage: return {"ok":false,"message":"Работодатель временно не может оплатить смену."}
			for item:String in job.inputs: market.stocks[item]=int(market.stocks[item])-int(job.inputs[item])
			for item:String in job.outputs:
				var amount:int=maxi(1,roundi(int(job.outputs[item])*multiplier))
				market.stocks[item]=int(market.stocks.get(item,0))+amount; market.production[item]=int(market.production.get(item,0))+amount
			if not str(job.service).is_empty(): market.services[job.service]=minf(100,float(market.services.get(job.service,0))+multiplier)
			market.treasury=int(market.treasury)-wage; home.coins=int(home.coins)+wage; home.income=int(home.income)+wage
			_business_profit(p,job,wage,multiplier)
			p.career.work_minutes=float(p.career.work_minutes)+60; p.career.earned=int(p.career.earned)+wage; p.lifetime_wages=int(p.lifetime_wages)+wage
			p.career.performance=float(p.career.performance)+5*multiplier
			var level:int=mini(10,1+floori(float(p.career.work_minutes)/1200))
			if level>int(p.career.level): p.career.level=level; _remember(id,"promotion","Повышение",[job.name+" · ступень "+str(level)]); _event("promotion",p.name+" получил повышение",[job.name], [id])
			_skill(id,str(job.skill),10); _change_need(id,"energy",-4); _change_need(id,"hygiene",-4)
			message="Рабочий час завершён. Семья получила %d монет." % wage
			extra={"wage":wage,"skill":job.skill}
		"apply_job":
			for business:Dictionary in businesses.values(): business.employees.erase(id)
			p.profession=str(payload.profession_id); p.workplace_id=_workplace(p.profession); p.career={"level":1,"performance":0.0,"work_minutes":0.0,"earned":0,"shifts":0}
			_remember(id,"job","Новая профессия",[professions[p.profession].name]); message="Вы устроились на работу: "+str(professions[p.profession].name)+"."
		"quit_job":
			for business:Dictionary in businesses.values(): business.employees.erase(id)
			p.profession=""; p.workplace_id=""; message="Персонаж оставил работу."
		"buy","sell":
			var item:String=str(payload.item_id); var amount:int=int(payload.get("quantity",1)); var cost:int=price(item,action=="sell")*amount
			if action=="buy":
				home.coins=int(home.coins)-cost; home.expenses=int(home.expenses)+cost; inv[item]=int(inv.get(item,0))+amount; market.stocks[item]=int(market.stocks[item])-amount; market.treasury=int(market.treasury)+cost
			else:
				home.coins=int(home.coins)+cost; home.income=int(home.income)+cost; inv[item]=int(inv[item])-amount; market.stocks[item]=int(market.stocks.get(item,0))+amount; market.treasury=int(market.treasury)-cost
			market.turnover=int(market.turnover)+cost; _skill(id,"trade",2*amount); message=("Куплено: " if action=="buy" else "Продано: ")+Catalog.GOODS[item].name+" ×"+str(amount)
		"buy_home":
			var house_id:String=str(payload.home_id); var cost:int=int(venues[house_id].get("price",200))
			home.coins=int(home.coins)-cost; market.treasury=int(market.treasury)+cost; home.properties.append(house_id)
			_remember(id,"home","Собственный дом",[venues[house_id].name]); message="Дом куплен. Можно назначить его семейным жильём."
		"move_home":
			home.home_id=str(payload.home_id)
			for member:String in home.members: residents[member].home_id=home.home_id
			_event("moving",home.name+" переезжает",[venues[home.home_id].name],home.members); message="Новый семейный дом назначен. Жители будут возвращаться туда."
		"invite_household": _join_household(str(payload.target_id),str(p.household_id)); extra.new_member_id=str(payload.target_id); message="Житель присоединился к хозяйству."
		"propose":
			var target:String=str(payload.target_id); p.partner_id=target; residents[target].partner_id=id
			_schedule("wedding",clock+1440,[id,target],"life_temple","Свадьба"); message="Предложение принято. Свадьба запланирована на следующий день."
		"plan_child":
			var target:String=str(payload.target_id); var due:float=clock+4320
			p.family_plan_due=due; residents[target].family_plan_due=due
			_schedule("birth",due,[id,target],str(p.home_id),"Пополнение семьи"); message="Семья готовится к появлению ребёнка через три игровых дня."
		"adopt":
			extra.new_member_id=_new_child(str(p.household_id),[id],true); message="В хозяйстве появился приёмный ребёнок."
		"educate":
			var child:String=str(payload.target_id); residents[child].education=float(residents[child].education)+5; _skill(child,"reading",15); _skill(id,"teaching",10); _social(id,child,"socialize"); message="Ребёнок продвинулся в учёбе."
		"create_member":
			var new_id:String="resident_%03d" % _next_person; _next_person+=1
			var newcomer:Dictionary=Population.person(new_id,str(payload.get("name","Новый житель")),25,str(payload.get("gender","female")),str(p.household_id),str(p.home_id),p.position)
			residents[new_id]=newcomer; home.members.append(new_id); _edit_profile(newcomer,payload); extra.new_member_id=new_id
			_event("arrival",newcomer.name+" присоединился к семье",[],[new_id]); message="Создан взрослый член хозяйства."
		"edit_profile": _edit_profile(p,payload); message="Персонаж обновлён."
		"set_autonomy": p.autonomy=bool(payload.get("enabled",true)); message="Самостоятельная жизнь "+("включена." if p.autonomy else "выключена.")
		"buy_workshop":
			var business:Dictionary=businesses[str(payload.business_id)]
			home.coins=int(home.coins)-int(business.price); home.expenses=int(home.expenses)+int(business.price); market.treasury=int(market.treasury)+int(business.price); business.owner=p.household_id
			for worker:Dictionary in residents.values():
				if professions.has(str(worker.profession)) and professions[worker.profession].venue_id==business.id: business.employees.append(worker.id)
			_remember(id,"business","Собственное предприятие",[str(venues[business.id].name)]); message="Предприятие куплено. Его работа приносит семье чистую прибыль."
		"hire_worker":
			var worker_id:String=str(payload.worker_id); var profession:String=str(payload.profession_id)
			for business:Dictionary in businesses.values(): business.employees.erase(worker_id)
			businesses[str(payload.business_id)].employees.append(worker_id)
			var worker:Dictionary=residents[worker_id]; worker.profession=profession; worker.workplace_id=_workplace(profession); worker.current_action={}; release(worker_id)
			worker.career={"level":1,"performance":0.0,"work_minutes":0.0,"earned":0,"shifts":0}
			_remember(worker_id,"job","Работа в семейном предприятии",[p.id]); message="Работник нанят и будет приходить по расписанию."
		"set_price": businesses[str(payload.business_id)].markup=float(payload.get("markup",1.0)); message="Наценка предприятия изменена."
	_refresh_mood(id)
	release(id)
	var result:Dictionary={"ok":true,"message":message,"action":action,"actor_id":id}
	result.merge(extra)
	if command_observer.is_valid(): command_observer.call(id,action,payload,result,spec)
	return result


func _business_profit(p:Dictionary,job:Dictionary,wage:int,multiplier:float)->void:
	var business:Dictionary=businesses.get(str(job.venue_id),{})
	if business.is_empty() or str(business.owner).is_empty() or not households.has(str(business.owner)): return
	if not business.employees.has(p.id): business.employees.append(p.id)
	var revenue:int=0; var inputs:int=0
	for item:String in job.outputs: revenue+=maxi(1,roundi(int(job.outputs[item])*multiplier))*int(Catalog.GOODS[item].price)
	for item:String in job.inputs: inputs+=int(job.inputs[item])*int(Catalog.GOODS[item].price)
	if not str(job.service).is_empty(): revenue=wage+3
	# High asking prices reduce sales volume; stock remains in the shared local market.
	var margin:float=float(business.markup)
	var demand:float=clampf(1.35-(margin-1)*1.5,.45,1.0)
	var profit:int=mini(int(market.treasury),maxi(0,roundi(revenue*margin*demand)-inputs-wage))
	var owner:Dictionary=households[business.owner]
	market.treasury=int(market.treasury)-profit; owner.coins=int(owner.coins)+profit; owner.income=int(owner.income)+profit; business.profits=int(business.profits)+profit


func _cook_recipe(inv:Dictionary)->Dictionary:
	if int(inv.get("carrot",0))>=1 and int(inv.get("wood",0))>=1: return {"carrot":1,"wood":1}
	if int(inv.get("flour",0))>=1 and int(inv.get("water",0))>=1: return {"flour":1,"water":1}
	return {}


func price(item:String,selling:bool=false)->int:
	if not Catalog.GOODS.has(item): return 0
	var good:Dictionary=Catalog.GOODS[item]
	var scarcity:float=clampf(float(good.stock)/maxf(1,float(market.stocks.get(item,0))),.7,2.0)
	return maxi(1,roundi(float(good.price)*(.7+.3*scarcity)*(.65 if selling else 1.0)))


func _food_item(p:Dictionary)->String:
	var choices:Array=[str(p.preferences.get("food","bread")),"bread","meal","apple","carrot","fish","meat","milk"]
	if p.traits.has("frugal"): choices.push_front("bread")
	var house:Dictionary=households[p.household_id]
	for item:String in choices:
		if Catalog.GOODS.has(item) and (int(p.inventory.get(item,0))>0 or int(house.inventory.get(item,0))>0): return item
	for item:String in ["bread","carrot","apple","meal"]:
		if int(market.stocks.get(item,0))>0 and int(house.coins)>=price(item): return item
	return ""


func _home_owner(home:String)->String:
	for id:String in households:
		if households[id].properties.has(home): return id
	return ""


func _change_need(id:String,key:String,amount:float)->void:
	var p:Dictionary=residents[id]
	p.needs[key]=clampf(float(p.needs.get(key,85))+amount,0,100)
	if _bindings.has(id):
		_bindings[id]["sleep" if key=="energy" else key]=p.needs[key]


func _skill(id:String,key:String,amount:float)->void:
	var p:Dictionary=residents[id]
	var old:Variant=p.skills.get(key,0.0)
	# Main's existing skills are numeric XP; preserve that shared representation.
	if old is Dictionary: old=float(old.get("xp",0))
	p.skills[key]=float(old)+amount*_trait_product(p,"learning")


func _trait_product(p:Dictionary,key:String)->float:
	var value:float=1.0
	for trait_id:String in p.traits: value*=float(Catalog.TRAITS.get(trait_id,{}).get(key,1.0))
	return value


func _relationship(a:String,b:String)->Dictionary:
	if not residents[a].relationships.has(b): residents[a].relationships[b]={"friendship":0.0,"romance":0.0,"met":false,"last_contact":clock}
	return residents[a].relationships[b]


func _social(a:String,b:String,action:String)->void:
	var p:Dictionary=residents[a]
	var gain:float={"socialize":8,"joke":6,"compliment":10,"insult":-18,"apologize":7,"flirt":4}.get(action,5)
	gain*=_trait_product(p,"social_bonus") if gain>0 else _trait_product(p,"conflict")
	for pair:Array in [[a,b],[b,a]]:
		var rel:Dictionary=_relationship(pair[0],pair[1])
		rel.friendship=clampf(float(rel.friendship)+gain,-100,100); rel.met=true; rel.last_contact=clock
		if action=="flirt": rel.romance=clampf(float(rel.romance)+8,0,100)
		if action=="insult": rel.romance=maxf(0,float(rel.romance)-8)
		_change_need(pair[0],"social",25 if gain>0 else 7)
		_change_need(pair[0],"fun",8 if gain>0 else -10)
		_moodlet(pair[0],"conversation" if gain>0 else "argument","Приятная беседа" if gain>0 else "Ссора",10 if gain>0 else -18,180,b if pair[0]==a else a)
		residents[pair[0]].last_social=clock
		if gain<0 or float(rel.friendship)>=40 and float(rel.friendship)-gain<40:
			_remember(pair[0],"conflict" if gain<0 else "friendship",("Поссорился с " if gain<0 else "Подружился с ")+str(residents[pair[1]].name),[pair[1]])
	_skill(a,"social",5)


func _moodlet(id:String,kind:String,title:String,strength:float,duration:float,source:String)->void:
	var list:Array=residents[id].moodlets
	for index in range(list.size()-1,-1,-1):
		if str(list[index].id)==kind and str(list[index].source)==source: list.remove_at(index)
	list.append({"id":kind,"name":title,"strength":strength,"expires":clock+duration,"source":source})
	if list.size()>20: list.pop_front()


func _remember(id:String,kind:String,title:String,others:Array=[])->void:
	if not residents.has(id): return
	var memories:Array=residents[id].memories
	memories.append({"id":"memory_"+str(_next_event),"kind":kind,"name":title,"time":clock,"people":others.duplicate()}); _next_event+=1
	if memories.size()>30: memories.pop_front()


func _event(kind:String,title:String,details:Array,people:Array)->void:
	events.append({"id":"event_"+str(_next_event),"kind":kind,"name":title,"details":details.duplicate(),"people":people.duplicate(),"time":clock}); _next_event+=1
	if events.size()>80: events.pop_front()


func _schedule(kind:String,time:float,people:Array,venue:String,title:String)->void:
	calendar_events.append({"id":"calendar_"+str(_next_event),"kind":kind,"time":time,"people":people.duplicate(),"venue_id":venue,"name":title}); _next_event+=1


func _profile_error(payload:Dictionary)->String:
	if payload.has("name") and (not payload.name is String or str(payload.name).strip_edges().is_empty() or str(payload.name).length()>48): return "Имя должно содержать от 1 до 48 знаков."
	if payload.has("gender") and not payload.gender in ["male","female"]: return "Неизвестный вариант персонажа."
	if payload.has("traits"):
		if not payload.traits is Array or payload.traits.size()>4: return "Выберите до четырёх черт."
		var seen:Dictionary={}
		for trait_id in payload.traits:
			if not Catalog.TRAITS.has(str(trait_id)) or seen.has(str(trait_id)): return "Неизвестная или повторная черта."
			seen[str(trait_id)]=true
	if payload.has("aspiration") and not Catalog.ASPIRATIONS.has(str(payload.aspiration)): return "Неизвестная жизненная цель."
	for group:String in ["appearance","preferences"]:
		if not payload.has(group): continue
		if not payload[group] is Dictionary: return "Неверный формат выбора."
		var rows:Array=Catalog.APPEARANCE if group=="appearance" else Catalog.PREFERENCES
		for key:String in payload[group]:
			var found:bool=false
			for row:Dictionary in rows:
				if row.id!=key: continue
				for option:Dictionary in row.options:
					if option.id==payload[group][key]: found=true
			if not found: return "Неизвестный вариант: "+key
	return ""


func _edit_profile(p:Dictionary,payload:Dictionary)->void:
	for key:String in ["name","traits","aspiration","gender"]:
		if payload.has(key): p[key]=payload[key].duplicate() if payload[key] is Array else payload[key]
	for key:String in ["appearance","preferences"]:
		if payload.has(key): p[key].merge(payload[key],true)
	if _bindings.has(p.id): _bindings[p.id]["name"]=p.name


func _join_household(id:String,house_id:String)->void:
	var p:Dictionary=residents[id]
	if households.has(str(p.household_id)): households[p.household_id].members.erase(id)
	p.household_id=house_id; p.home_id=households[house_id].home_id
	if not households[house_id].members.has(id): households[house_id].members.append(id)
	p.current_action={}; release(id)


func _new_child(house_id:String,parents:Array,adopted:bool=false)->String:
	if not households.has(house_id) or households[house_id].members.size()>=8 or residents.size()>=int(settings.population_limit): return ""
	var id:String="resident_%03d" % _next_person; _next_person+=1
	var gender:String="female" if _rng.randf()<.5 else "male"
	var names:Array=Population.FIRST_F if gender=="female" else Population.FIRST_M
	var title:String=str(names[_rng.randi_range(0,names.size()-1)])
	var home:Dictionary=households[house_id]
	var p:Dictionary=Population.person(id,title,6 if adopted else 0,gender,house_id,home.home_id,_point_array(home.home_id))
	p.parents=parents.duplicate(); p.traits=["friendly","family"]; p["death_age"]=82+_rng.randf()*10; p.birth_day=_day
	residents[id]=p; home.members.append(id)
	for parent:String in parents:
		if not residents.has(parent): continue
		residents[parent].children.append(id); residents[parent].family_plan_due=-1; residents[parent].last_birth_day=_day
		_remember(parent,"family",("В семье появился " if adopted else "Родился ")+title,[id]); _moodlet(parent,"child","Пополнение семьи",25,1440*3,id)
	_event("family",("Семья приняла ребёнка: " if adopted else "Родился ребёнок: ")+title,[],parents+[id])
	return id


func _refresh_mood(id:String)->void:
	var p:Dictionary=residents[id]
	var total:float=15.0
	for need:String in p.needs: total+=(float(p.needs[need])-55)*.13
	for index in range(p.moodlets.size()-1,-1,-1):
		if float(p.moodlets[index].expires)<=clock: p.moodlets.remove_at(index)
		else: total+=float(p.moodlets[index].strength)
	p.mood=clampf(total,-100,100)


func reserve(actor_id:String,venue_id:String,action:String,duration:float)->bool:
	if venue_id.is_empty(): return true
	var capacity:int=1 if venue_id.begins_with("person:") else int(venues.get(venue_id,{}).get("capacity",1))
	var claims:Array=reservations.get(venue_id,[])
	for index in range(claims.size()-1,-1,-1):
		if float(claims[index].expires)<clock or claims[index].actor_id==actor_id: claims.remove_at(index)
	if claims.size()>=maxi(1,capacity): return false
	claims.append({"actor_id":actor_id,"action":action,"expires":clock+maxf(120,duration+180)})
	reservations[venue_id]=claims
	return true


func release(actor_id:String)->void:
	for id:String in reservations.keys():
		var claims:Array=reservations[id]
		for index in range(claims.size()-1,-1,-1):
			if claims[index].actor_id==actor_id: claims.remove_at(index)
		if claims.is_empty(): reservations.erase(id)


func suggest_action(id:String)->Dictionary:
	if not residents.has(id): return {}
	var p:Dictionary=residents[id]
	if not bool(p.alive) or not bool(p.autonomy) or bool(p.get("busy",false)) or not str(p.get("social_holder","")).is_empty(): return {}
	if float(p.age_years)<5: return {}
	var candidates:Array=[]
	var need_actions:Dictionary={"hunger":"eat","thirst":"drink","energy":"sleep","hygiene":"wash","bladder":"toilet","fun":"relax","comfort":"relax"}
	for need:String in need_actions:
		var amount:float=float(p.needs[need])
		var score:float=(70-amount)*1.8 if amount<70 else -50
		if amount<20: score+=100
		candidates.append({"action":need_actions[need],"payload":{},"score":score})
	var hour:float=fmod(clock,1440)/60
	if hour>=22 or hour<6: candidates.append({"action":"sleep","payload":{},"score":90 if float(p.needs.energy)<75 else 0})
	if _is_work_time(str(p.profession)): candidates.append({"action":"work","payload":{"profession_id":p.profession},"score":58})
	if float(p.age_years)>=5 and float(p.age_years)<18 and hour>=9 and hour<13 and (_day-1)%7<5: candidates.append({"action":"study","payload":{},"score":76})
	var target:String=_social_partner(id)
	if not target.is_empty():
		var action:String="insult" if p.traits.has("hotheaded") and float(p.mood)<-35 else "socialize"
		candidates.append({"action":action,"payload":{"target_id":target},"score":(70-float(p.needs.social))*1.6})
	var hobby:String=str(p.preferences.get("hobby","relax"))
	if hobby!="socialize": candidates.append({"action":hobby,"payload":{},"score":(80-float(p.needs.fun))*1.1+8})
	for candidate:Dictionary in candidates:
		for trait_id:String in p.traits: candidate.score=float(candidate.score)+float(Catalog.TRAITS.get(trait_id,{}).get("weights",{}).get(candidate.action,0))
		if weather.id in ["rain","storm","snow"] and candidate.action=="relax": candidate.score=float(candidate.score)-20
	candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a.score)>float(b.score))
	for choice:Dictionary in candidates:
		if float(choice.score)<5: continue
		var spec:Dictionary=command_spec(id,choice.action,choice.payload)
		if spec.ok and float(p.blocked.get(spec.venue_id,0))<=clock:
			var claims:Array=reservations.get(spec.venue_id,[])
			var capacity:int=int(venues.get(spec.venue_id,{}).get("capacity",1))
			if claims.size()>=capacity: continue
			return {"action":choice.action,"payload":choice.payload}
	return {}


func _social_partner(id:String)->String:
	var p:Dictionary=residents[id]
	var best:float=INF; var chosen:String=""
	for other:String in residents:
		if other==id or not residents[other].alive or float(residents[other].age_years)<5 or bool(residents[other].get("busy",false)): continue
		if not str(residents[other].get("social_holder","")).is_empty() and residents[other].social_holder!=id: continue
		if not residents[other].current_action.is_empty() and residents[other].current_action.action in ["work","sleep"]: continue
		var distance:float=_distance(position_of(id),position_of(other))
		if distance>180: continue
		if residents[other].household_id==p.household_id: distance*=.6
		if distance<best: best=distance; chosen=other
	return chosen


func advance(minutes:float,absolute_minutes:float=-1)->void:
	if not is_finite(minutes) or minutes<0: return
	var elapsed:float=minutes
	if absolute_minutes>=0:
		if not is_finite(absolute_minutes): return
		elapsed=maxf(0,absolute_minutes-clock)
	# The bridge supplies game-time once. Chunking keeps long offscreen jumps deterministic.
	while elapsed>.00001:
		var step:float=minf(5.0,elapsed)
		clock+=step; elapsed-=step
		var day:int=maxi(1,floori(clock/1440))
		while _day<day: _day+=1; _new_day()
		for id:String in residents.keys():
			var p:Dictionary=residents[id]
			if not p.alive: continue
			if p.external: _sync_hero(id)
			_decay(id,step)
			if not p.external: _advance_resident(id,step)
			_refresh_mood(id)
		_process_calendar()


func _decay(id:String,minutes:float)->void:
	var p:Dictionary=residents[id]
	for need:String in Catalog.NEED_RATES:
		if p.external and need in ["hunger","thirst","energy"]: continue
		var rate:float=float(Catalog.NEED_RATES[need])*_trait_product(p,need+"_rate")
		_change_need(id,need,-rate*minutes)
	if not p.external and (float(p.needs.hunger)<=0 or float(p.needs.thirst)<=0): p.health=maxf(1,float(p.health)-minutes*.05)
	if float(p.age_years)<5 and not domestic_care_enabled:
		# Infants are cared for analytically by their household, with actual pantry cost.
		if float(p.needs.hunger)<45 and not _food_item(p).is_empty():
			var saved:Array=p.position; p.position=_point_array(p.home_id); _execute(id,"eat",{}); p.position=saved
		_change_need(id,"energy",minutes*.09); _change_need(id,"hygiene",minutes*.05); _change_need(id,"bladder",minutes*.09)


func _advance_resident(id:String,minutes:float)->void:
	var p:Dictionary=residents[id]
	if bool(p.get("busy",false)) or not str(p.get("social_holder","")).is_empty(): return
	if p.current_action.is_empty():
		var choice:Dictionary=p.queue.pop_front() if not p.queue.is_empty() else suggest_action(id)
		if choice.is_empty(): return
		var spec:Dictionary=command_spec(id,str(choice.action),choice.get("payload",{}))
		if not spec.ok or not reserve(id,spec.venue_id,choice.action,spec.duration): return
		p.current_action={"action":choice.action,"payload":choice.get("payload",{}).duplicate(true),"target":[spec.target.x,spec.target.y,spec.target.z],"venue_id":spec.venue_id,"remaining":spec.duration,"duration":spec.duration,"animation":spec.animation,"phase":"walking"}
		if not spec.venue_id.begins_with("person:"): p.current_action.payload["venue_id"]=spec.venue_id
	var current:Dictionary=p.current_action
	for claim:Dictionary in reservations.get(current.venue_id,[]):
		if claim.actor_id==id: claim.expires=clock+maxf(120,float(current.remaining)+60)
	var target:Vector3=_vector(current.target)
	if current.payload.has("target_id") and residents.has(str(current.payload.target_id)):
		target=position_of(str(current.payload.target_id)); current.target=[target.x,target.y,target.z]
	var from:Vector3=position_of(id)
	var distance:float=_distance(from,target)
	if distance>1.8:
		current.phase="walking"
		if _external_motion.has(id): return
		var travel:float=minf(distance,minutes*5.0)
		set_position(id,from.move_toward(target,travel))
		if travel<distance: return
		minutes=maxf(0,minutes-distance/5.0)
	current.phase="working"
	current.remaining=maxf(0,float(current.remaining)-minutes)
	# Renew while physically waiting/travelling; no remote work rewards.
	for claim:Dictionary in reservations.get(current.venue_id,[]):
		if claim.actor_id==id: claim.expires=clock+maxf(120,float(current.remaining)+60)
	if float(current.remaining)>0: return
	var action:String=current.action; var payload:Dictionary=current.payload.duplicate(true)
	p.current_action={}; release(id)
	var result:Dictionary=_execute(id,action,payload)
	if not result.ok: p.blocked[str(current.venue_id)]=clock+15


func _refresh_weather()->void:
	var season:int=((_day-1)/7 as int)%4
	var choices:Array=["clear","clear","cloudy","rain","fog","storm"] if season!=3 else ["cloudy","snow","snow","clear","fog"]
	weather={"id":choices[_rng.randi_range(0,choices.size()-1)],"temperature":[14.0,25.0,10.0,-2.0][season]+_rng.randf_range(-4,4),"season":season}


func _new_day()->void:
	_refresh_weather()
	market.services.safety=maxf(20,float(market.services.safety)*.9)
	market.services.community=float(market.services.community)*.95
	for id:String in residents.keys():
		var p:Dictionary=residents[id]
		if not p.alive: continue
		if bool(settings.aging):
			var old_stage:String=p.stage
			p.age_years=float(p.age_years)+1.0/maxf(1,float(settings.days_per_age_year)); p.stage=Catalog.stage(float(p.age_years))
			if p.stage!=old_stage: _remember(id,"birthday","Новый этап жизни: "+Catalog.STAGES[p.stage]); _event("birthday",p.name+" — "+Catalog.STAGES[p.stage],[],[id])
			if float(p.age_years)>=float(p.get("death_age",90)): _die(id); continue
		if p.preferences.get("weather","")==weather.id or p.traits.has("outdoors") and weather.id=="clear": _moodlet(id,"weather","Любимая погода",8,600,"weather")
		var progress:Dictionary=_aspiration_progress(p)
		if not bool(p.aspiration_done) and float(progress.current)>=float(progress.target):
			p.aspiration_done=true; _remember(id,"goal","Достигнута цель: "+str(Catalog.ASPIRATIONS[p.aspiration].name)); _moodlet(id,"goal","Жизненная цель исполнена",30,2880,"goal")
	if bool(settings.family_growth):
		for hid:String in households:
			var home:Dictionary=households[hid]
			if hid=="house_player" or home.members.size()>=5 or int(home.coins)<100 or _day-int(home.last_family_day)<14: continue
			for id:String in home.members:
				var p:Dictionary=residents[id]; var partner:String=str(p.partner_id)
				if not p.alive or float(p.age_years)<25 or float(p.age_years)>50 or float(p.family_plan_due)>=0 or not residents.has(partner) or residents[partner].household_id!=hid: continue
				if p.traits.has("family") and _rng.randf()<.15:
					var due:float=clock+4320; p.family_plan_due=due; residents[partner].family_plan_due=due; home.last_family_day=_day
					_schedule("birth",due,[id,partner],home.home_id,"Пополнение семьи"); break


func _process_calendar()->void:
	for index in range(calendar_events.size()-1,-1,-1):
		if float(calendar_events[index].time)>clock: continue
		var event:Dictionary=calendar_events[index].duplicate(true); calendar_events.remove_at(index)
		match str(event.kind):
			"birth":
				if event.people.size()<2: continue
				var a:String=str(event.people[0]); var b:String=str(event.people[1])
				if residents.has(a) and residents.has(b) and residents[a].alive and residents[b].alive and residents[a].household_id==residents[b].household_id: _new_child(residents[a].household_id,[a,b])
				for id:String in event.people:
					if residents.has(id): residents[id].family_plan_due=-1
			"wedding":
				for id:String in event.people:
					if residents.has(id) and residents[id].alive: residents[id]["married"]=true; _remember(id,"wedding","Свадьба",event.people); _moodlet(id,"wedding","Свадьба",30,2880,event.id)
				_event("wedding","Свадьба в поселении",[],event.people)
			"fair":
				_event("fair","На городской площади открылась ярмарка",["Торговля, встречи и выступления."],[])
				# A visiting caravan purchases exports and replenishes shortages, recording trade.
				for item:String in Catalog.GOODS:
					var target:int=int(Catalog.GOODS[item].stock); var stock:int=int(market.stocks.get(item,0))
					var imported:int=maxi(0,target/3-stock)
					if imported>0 and int(market.treasury)>=imported*int(Catalog.GOODS[item].price): market.stocks[item]=stock+imported; market.treasury=int(market.treasury)-imported*int(Catalog.GOODS[item].price)
				_schedule("fair",clock+10080,[],"life_market","Городская ярмарка")


func _die(id:String)->void:
	var p:Dictionary=residents[id]; p.alive=false; p.current_action={}; release(id)
	var home:Dictionary=households[p.household_id]
	for item:String in p.inventory: home.inventory[item]=int(home.inventory.get(item,0))+int(p.inventory[item])
	p.inventory.clear(); home.coins=int(home.coins)+int(p.personal_coins); p.personal_coins=0; home.members.erase(id)
	for other:String in p.children+([p.partner_id] if not str(p.partner_id).is_empty() else []):
		if residents.has(other): _remember(other,"loss","Ушёл из жизни "+str(p.name),[id]); _moodlet(other,"grief","Утрата близкого",-35,4320,id)
	_event("death","Ушёл из жизни "+str(p.name),["Вещи и средства сохранены в семейном хозяйстве."],[id])


func _aspiration_progress(p:Dictionary)->Dictionary:
	var current:float=0; var goal:String=str(p.aspiration)
	match goal:
		"family":
			for id:String in p.children:
				if residents.has(id) and float(residents[id].education)>=30 and float(_relationship(p.id,id).friendship)>=40: current+=1
		"master": current=float(p.career.level)
		"wealth": current=float(households[p.household_id].coins)
		"scholar": current=float(p.skills.get("reading",0))+float(p.skills.get("literacy",0))
		"community":
			for relation:Dictionary in p.relationships.values():
				if float(relation.friendship)>=40: current+=1
	return {"current":current,"target":float(Catalog.ASPIRATIONS.get(goal,{"target":1}).target)}


func _row(id:String,title:String,details:Array=[],actions:Array=[])->Dictionary:
	return {"id":id,"name":title,"details":details,"actions":actions}


func _ui_action(id:String,action:String,label:String="",payload:Dictionary={},issuer:String="local")->Dictionary:
	var values:Dictionary=payload.duplicate(true); values.actor_id=id
	var spec:Dictionary=command_spec(id,action,values)
	var allowed:bool=_controlled(id,issuer)
	return {"id":action,"label":str(Catalog.ACTIONS.get(action,{}).get("name",action)) if label.is_empty() else label,"payload":values,"enabled":allowed and bool(spec.ok),"reason":str(spec.reason) if allowed else "Можно управлять только своим хозяйством."}


func ui_state(selected_id:String,issuer:String="local")->Dictionary:
	if not residents.has(selected_id): selected_id="brother" if residents.has("brother") else str(residents.keys()[0])
	var p:Dictionary=residents[selected_id]
	var own_id:String=str(controllers.get(issuer,"house_player")); var own:Dictionary=households[own_id]
	var date:String="День %d · %s · %02d:%02d" % [_day,Catalog.WEEKDAYS[(_day-1)%7],floori(fmod(clock,1440)/60),floori(fmod(clock,60))]
	var result:Dictionary={"summary":{"funds":own.coins,"currency":"монет","date":date,"weather":Catalog.WEATHER_NAMES.get(weather.id,weather.id),"temperature":roundi(weather.temperature),"season":Catalog.SEASONS[int(weather.season)],"day":_day,"household":own.name},"selected":{},"people":[],"careers":[],"market":[],"properties":[],"household":[],"calendar":[],"events":[],"catalog":{"need_labels":Catalog.NEED_LABELS.duplicate(),"traits":[],"preferences":Catalog.PREFERENCES.duplicate(true),"aspirations":[],"appearance":Catalog.APPEARANCE.duplicate(true)}}
	var profile:Dictionary={"id":selected_id,"name":p.name,"age":floori(p.age_years),"stage":Catalog.STAGES[p.stage],"gender":p.gender,"profession":professions.get(p.profession,{}).get("name","Без профессии"),"home":venues.get(p.home_id,{}).get("name",p.home_id),"household":households[p.household_id].name,"needs":p.needs.duplicate(),"mood":p.mood,"moodlets":[],"traits":p.traits.duplicate(),"trait_labels":[],"skills":[],"preferences":p.preferences.duplicate(),"aspiration":p.aspiration,"memories":[],"family":[],"appearance":p.appearance.duplicate(),"actions":[],"goals":[],"autonomy":p.autonomy}
	for trait_id:String in p.traits: profile.trait_labels.append(str(Catalog.TRAITS.get(trait_id,{}).get("name",trait_id)))
	for effect:Dictionary in p.moodlets: profile.moodlets.append(_row(effect.id,effect.name,["Настроение %+.0f · ещё %d мин" % [float(effect.strength),maxi(0,ceili(float(effect.expires)-clock))]]))
	for skill:String in p.skills:
		var value:float=float(p.skills[skill]) if not p.skills[skill] is Dictionary else float(p.skills[skill].get("xp",0))
		profile.skills.append(_row(skill,_skill_name(skill),["Уровень %d · опыт %.0f" % [Catalog.skill_level(value),value]]))
	for index in range(p.memories.size()-1,-1,-1):
		var memory:Dictionary=p.memories[index]
		profile.memories.append(_row(memory.id,memory.name,["День %d" % maxi(1,floori(float(memory.time)/1440))]))
	for relative:String in p.parents+p.children+p.get("siblings",[])+([p.partner_id] if not str(p.partner_id).is_empty() else []):
		if not residents.has(relative): continue
		var relation:String="Родитель" if p.parents.has(relative) else ("Ребёнок" if p.children.has(relative) else ("Партнёр" if p.partner_id==relative else "Брат / сестра"))
		profile.family.append(_row(relative,residents[relative].name,[relation,"Возраст: %d · %s" % [floori(residents[relative].age_years),"Живёт в поселении" if residents[relative].alive else "Память семьи"]]))
	var progress:Dictionary=_aspiration_progress(p)
	profile.goals.append(_row(p.aspiration,Catalog.ASPIRATIONS[p.aspiration].name,Catalog.ASPIRATIONS[p.aspiration].details+["Прогресс: %.0f / %.0f%s" % [progress.current,progress.target," · выполнено" if p.aspiration_done else ""]]))
	for action:String in ["eat","drink","wash","toilet","sleep","relax","read","study","train","cook"]: profile.actions.append(_ui_action(selected_id,action,"",{},issuer))
	profile.actions.append(_ui_action(selected_id,"set_autonomy","Самостоятельность: "+("выключить" if p.autonomy else "включить"),{"enabled":not bool(p.autonomy)},issuer))
	result.selected=profile
	for id:String in residents:
		var person:Dictionary=residents[id]
		if not person.alive: continue
		var job:String=str(professions.get(person.profession,{}).get("name","Учится" if float(person.age_years)<18 else "Без профессии"))
		var current:String=Catalog.ACTIONS.get(person.current_action.get("action",""),{}).get("name","Свободен")
		var details:Array=["%d лет · %s · %s" % [floori(person.age_years),Catalog.STAGES[person.stage],job],str(households[person.household_id].name)+" · "+current]
		var actions:Array=[]
		if id!=selected_id:
			var relation:Dictionary=_relationship(selected_id,id)
			details.append("Дружба %.0f · симпатия %.0f" % [relation.friendship,relation.romance])
			for action:String in ["socialize","joke","compliment","apologize","insult","flirt","propose","plan_child","educate","invite_household"]: actions.append(_ui_action(selected_id,action,"",{"target_id":id},issuer))
		result.people.append(_row(id,person.name,details,actions))
	for id:String in professions:
		var job:Dictionary=professions[id]
		var details:Array=["%02d:00–%02d:00 · %d монет за 8 часов · навык: %s" % [job.start,job.end,job.wage,_skill_name(job.skill)],"Место: "+str(venues.get(job.venue_id,{}).get("name",job.venue_id))]
		if not job.outputs.is_empty(): details.append("Производство: "+_goods_text(job.outputs))
		if not job.inputs.is_empty(): details.append("Расход мастерской: "+_goods_text(job.inputs))
		if not str(job.service).is_empty(): details.append("Услуги поселению: "+str({"community":"хозяйство","education":"обучение","safety":"безопасность","culture":"культура"}.get(job.service,job.service)))
		var actions:Array=[_ui_action(selected_id,"apply_job","Устроиться",{"profession_id":id},issuer),_ui_action(selected_id,"work","Работать час",{"profession_id":id},issuer)]
		if p.profession==id: details.append("Ваша профессия · уровень %d · отработано %.1f ч" % [p.career.level,float(p.career.work_minutes)/60]); actions.append(_ui_action(selected_id,"quit_job","Уволиться",{},issuer))
		result.careers.append(_row(id,job.name,details,actions))
	for item:String in Catalog.GOODS:
		var stock:int=int(market.stocks.get(item,0)); var held:int=int(p.inventory.get(item,0))
		result.market.append(_row(item,Catalog.GOODS[item].name,["На рынке %d · в рюкзаке %d" % [stock,held],"Покупка %d · продажа %d монет" % [price(item),price(item,true)]],[_ui_action(selected_id,"buy","Купить 1",{"item_id":item,"quantity":1},issuer),_ui_action(selected_id,"sell","Продать 1",{"item_id":item,"quantity":1},issuer)]))
	for id:String in venues:
		if str(venues[id].get("kind","")) not in ["home","plot"]: continue
		var owner:String=_home_owner(id); var venue:Dictionary=venues[id]
		result.properties.append(_row(id,venue.name,["Владелец: "+str(households.get(owner,{}).get("name","Свободен")),"Цена: %d монет · %s" % [int(venue.get("price",200)),str(venue.get("district","Поселение"))]],[_ui_action(selected_id,"buy_home","Купить",{"home_id":id},issuer),_ui_action(selected_id,"move_home","Переехать сюда",{"home_id":id},issuer)]))
	for id:String in businesses:
		var business:Dictionary=businesses[id]
		var actions:Array=[_ui_action(selected_id,"buy_workshop","Купить предприятие",{"business_id":id},issuer)]
		if business.owner==own_id:
			for markup:float in [.8,1.0,1.2,1.5]: actions.append(_ui_action(selected_id,"set_price","Цены ×%.1f" % markup,{"business_id":id,"markup":markup},issuer))
			var offered:int=0
			var reserved:Dictionary={}
			for worker_id:String in residents:
				var worker:Dictionary=residents[worker_id]
				if not _adult(worker) or worker.external or business.employees.has(worker_id): continue
				var profession:String=_hire_profession(id,worker,reserved)
				if profession.is_empty(): continue
				reserved[profession]=true
				actions.append(_ui_action(selected_id,"hire_worker","Нанять: "+str(worker.name),{"business_id":id,"worker_id":worker_id,"profession_id":profession},issuer)); offered+=1
				if offered>=3: break
		result.properties.append(_row(id,str(venues.get(id,{}).get("name",id))+" · предприятие",["Владелец: "+str(households.get(business.owner,{}).get("name","Городское предприятие")),"Покупка %d монет · работников %d · прибыль %d" % [business.price,business.employees.size(),business.profits],"Цены ×%.2f · завышенная цена снижает спрос" % business.markup],actions))
	for id:String in own.members:
		if not residents.has(id): continue
		var member:Dictionary=residents[id]
		result.household.append(_row(id,member.name,["%d лет · %s" % [floori(member.age_years),str(professions.get(member.profession,{}).get("name","Без профессии"))],"Настроение: %.0f · самостоятельность %s" % [member.mood,"вкл." if member.autonomy else "выкл."]],[{"id":"select_member","label":"Выбрать","payload":{"actor_id":id},"enabled":true,"reason":""}]))
	result.household.append(_row("household_budget","Семейное хозяйство",["Доход: %d · расходы: %d монет" % [own.income,own.expenses],"Кладовая: "+_goods_text(own.inventory)],[_ui_action(selected_id,"create_member","Создать взрослого жителя",{"name":"Новый житель"},issuer),_ui_action(selected_id,"adopt","Принять ребёнка",{},issuer)]))
	for event:Dictionary in calendar_events: result.calendar.append(_row(event.id,event.name,["День %d · %02d:%02d" % [floori(float(event.time)/1440),floori(fmod(float(event.time),1440)/60),floori(fmod(float(event.time),60))],"Место: "+str(venues.get(event.venue_id,{}).get("name",event.venue_id))]))
	for index in range(events.size()-1,-1,-1):
		var event:Dictionary=events[index]; result.events.append(_row(event.id,event.name,["День %d" % floori(float(event.time)/1440)]+event.details))
	for id:String in Catalog.TRAITS: result.catalog.traits.append(_row(id,Catalog.TRAITS[id].name,Catalog.TRAITS[id].details))
	for id:String in Catalog.ASPIRATIONS: result.catalog.aspirations.append(_row(id,Catalog.ASPIRATIONS[id].name,Catalog.ASPIRATIONS[id].details))
	return result


func _goods_text(items:Dictionary)->String:
	var parts:PackedStringArray=[]
	for id:String in items:
		if int(items[id])>0: parts.append(str(Catalog.GOODS.get(id,{}).get("name",id))+" ×"+str(items[id]))
	return ", ".join(parts) if not parts.is_empty() else "пусто"


func _skill_name(id:String)->String:
	return str({"crafting":"Ремесло","farming":"Земледелие","animal_husbandry":"Животноводство","blacksmithing":"Кузнечное дело","carpentry":"Плотницкое дело","tailoring":"Шитьё","leatherworking":"Кожевенное дело","pottery":"Гончарное дело","jewelry":"Ювелирное дело","cooking":"Кулинария","herbalism":"Травничество","reading":"Чтение","literacy":"Грамота","tracking":"Следопытство","research":"Исследования","alchemy":"Алхимия","mining":"Горное дело","woodcutting":"Лесное дело","fishing":"Рыболовство","performance":"Выступления","trade":"Торговля","teaching":"Обучение","combat":"Боевое дело","social":"Общение","athletics":"Атлетика"}.get(id,id))


func snapshot()->Dictionary:
	for id:String in _bindings: _sync_hero(id)
	return {"version":1,"clock":clock,"day":_day,"residents":residents.duplicate(true),"households":households.duplicate(true),"market":market.duplicate(true),"businesses":businesses.duplicate(true),"weather":weather.duplicate(true),"settings":settings.duplicate(true),"events":events.duplicate(true),"calendar_events":calendar_events.duplicate(true),"next_person":_next_person,"next_event":_next_event,"rng_state":str(_rng.state),"requests":_requests.duplicate(true)}


func valid_snapshot(data:Dictionary)->bool:
	if int(data.get("version",0))!=1 or not data.get("residents") is Dictionary or not data.get("households") is Dictionary or not data.get("market") is Dictionary: return false
	if not _finite_tree(data): return false
	for key:String in ["clock","day","next_person","next_event"]:
		if not _numeric(data.get(key)) or float(data[key])<0: return false
	if not data.get("settings") is Dictionary or not data.get("requests",{}) is Dictionary: return false
	for key:String in ["days_per_age_year","population_limit"]:
		if not _numeric(data.settings.get(key)) or float(data.settings[key])<=0: return false
	if data.residents.is_empty() or data.residents.size()>256 or not data.households.has("house_player"): return false
	for id:String in data.residents:
		if not data.residents[id] is Dictionary: return false
		var p:Dictionary=data.residents[id]
		for key:String in ["id","name","gender","age_years","stage","household_id","home_id","profession","position","needs","traits","inventory","skills","career","relationships","moodlets","memories","appearance","preferences","parents","partner_id","children","alive","external","autonomy","current_action","queue","blocked","health","education","family_plan_due","aspiration","aspiration_done"]:
			if not p.has(key): return false
		if p.id!=id or not data.households.has(str(p.household_id)) or not p.position is Array or p.position.size()!=3: return false
		for component in p.position:
			if not _numeric(component): return false
		for key:String in ["age_years","health","education","family_plan_due"]:
			if not _numeric(p[key]): return false
		if not p.needs is Dictionary or not p.inventory is Dictionary or not p.skills is Dictionary or not p.career is Dictionary or not p.relationships is Dictionary or not p.current_action is Dictionary or not p.blocked is Dictionary: return false
		for key:String in Catalog.NEED_LABELS:
			if not p.needs.has(key) or not _numeric(p.needs[key]) or float(p.needs[key])<0 or float(p.needs[key])>100: return false
		for key:String in ["traits","parents","children","queue","moodlets","memories"]:
			if not p[key] is Array: return false
		for key:String in ["level","performance","work_minutes","earned"]:
			if not _numeric(p.career.get(key)): return false
		for item in p.inventory.values():
			if not _numeric(item) or float(item)<0: return false
		for value in p.skills.values():
			if not _numeric(value) or float(value)<0: return false
		for relationship in p.relationships.values():
			if not relationship is Dictionary or not _numeric(relationship.get("friendship")) or not _numeric(relationship.get("romance")): return false
		for effect in p.moodlets:
			if not effect is Dictionary or not _numeric(effect.get("expires")) or not _numeric(effect.get("strength")) or not effect.get("id") is String or not effect.get("source") is String or not effect.get("name") is String: return false
		for memory in p.memories:
			if not memory is Dictionary or not _numeric(memory.get("time")) or not memory.get("id") is String or not memory.get("name") is String: return false
		for order in p.queue:
			if not order is Dictionary or not Catalog.ACTIONS.has(str(order.get("action",""))) or not order.get("payload",{}) is Dictionary: return false
		if not Catalog.STAGES.has(str(p.stage)) or not Catalog.ASPIRATIONS.has(str(p.aspiration)) or not _profile_error({"traits":p.traits,"appearance":p.appearance,"preferences":p.preferences}).is_empty(): return false
		if not str(p.profession).is_empty() and not professions.has(str(p.profession)): return false
		if not p.current_action.is_empty():
			for key:String in ["action","payload","target","venue_id","remaining","duration","animation","phase"]:
				if not p.current_action.has(key): return false
			if not Catalog.ACTIONS.has(str(p.current_action.action)) or not p.current_action.payload is Dictionary or not p.current_action.target is Array or p.current_action.target.size()!=3: return false
			if not _numeric(p.current_action.remaining) or not _numeric(p.current_action.duration) or float(p.current_action.remaining)<0: return false
			for component in p.current_action.target:
				if not _numeric(component): return false
	for id:String in data.households:
		if not data.households[id] is Dictionary: return false
		var h:Dictionary=data.households[id]
		for key:String in ["id","name","members","home_id","properties","coins","inventory","income","expenses","last_family_day"]:
			if not h.has(key): return false
		if not h.members is Array or not h.properties is Array or not h.inventory is Dictionary or not _numeric(h.coins) or float(h.coins)<0: return false
		for key:String in ["income","expenses","last_family_day"]:
			if not _numeric(h[key]): return false
		for amount in h.inventory.values():
			if not _numeric(amount) or float(amount)<0: return false
		for member in h.members:
			if not data.residents.has(str(member)) or data.residents[member].household_id!=id: return false
	for key:String in ["stocks","treasury","turnover","production","consumed","services"]:
		if not data.market.has(key): return false
	for key:String in ["stocks","production","consumed","services"]:
		if not data.market[key] is Dictionary: return false
		for amount in data.market[key].values():
			if not _numeric(amount) or float(amount)<0: return false
	for key:String in ["treasury","turnover"]:
		if not _numeric(data.market[key]) or float(data.market[key])<0: return false
	for key:String in ["events","calendar_events"]:
		if not data.get(key) is Array: return false
		for event in data[key]:
			if not event is Dictionary or not _numeric(event.get("time")) or not event.get("id") is String or not event.get("name") is String or not event.get("people") is Array: return false
			if key=="calendar_events" and (not event.get("venue_id") is String or not event.get("kind") is String): return false
	if not data.get("weather") is Dictionary or not Catalog.WEATHER_NAMES.has(str(data.weather.get("id",""))): return false
	if not _numeric(data.weather.get("temperature")) or not _numeric(data.weather.get("season")) or int(data.weather.season)<0 or int(data.weather.season)>3: return false
	if not data.get("businesses",{}) is Dictionary: return false
	for business in data.get("businesses",{}).values():
		if not business is Dictionary or not business.get("id") is String or not business.get("owner") is String or not business.get("employees") is Array: return false
		for key:String in ["price","markup","profits"]:
			if not _numeric(business.get(key)) or float(business[key])<0: return false
		if not str(business.owner).is_empty() and not data.households.has(str(business.owner)): return false
	return true


func _numeric(value:Variant)->bool:
	return value is int or value is float


func _finite_tree(value:Variant)->bool:
	if value is float: return is_finite(value)
	if value is Dictionary:
		for child in value.values():
			if not _finite_tree(child): return false
	elif value is Array:
		for child in value:
			if not _finite_tree(child): return false
	elif not (value is int or value is String or value is bool or value==null): return false
	return true


func restore(data:Dictionary)->bool:
	if not valid_snapshot(data): return false
	# Scene-derived furniture is rebuilt by the bridge after loading. Keeping a
	# prior save's dynamic venues here would allow using demolished invisible props.
	venues=_base_venues.duplicate(true)
	residents=data.residents.duplicate(true); households=data.households.duplicate(true); market=data.market.duplicate(true)
	for item in Catalog.GOODS:
		if not market.stocks.has(item): market.stocks[item]=int(Catalog.GOODS[item].get("stock",0))
		if not market.production.has(item): market.production[item]=0
		if not market.consumed.has(item): market.consumed[item]=0
	if data.has("businesses"): businesses=data.businesses.duplicate(true)
	# JSON decodes all numbers as floats; counts and money retain integer semantics.
	for key:String in ["stocks","production","consumed"]:
		for item:String in market[key]: market[key][item]=int(market[key][item])
	for key:String in ["treasury","turnover"]: market[key]=int(market[key])
	for p:Dictionary in residents.values():
		for item:String in p.inventory: p.inventory[item]=int(p.inventory[item])
	for h:Dictionary in households.values():
		for key:String in ["coins","income","expenses"]: h[key]=int(h[key])
		for item:String in h.inventory: h.inventory[item]=int(h.inventory[item])
	weather=data.weather.duplicate(true); settings=data.get("settings",settings).duplicate(true)
	events.assign(data.events.duplicate(true)); calendar_events.assign(data.calendar_events.duplicate(true))
	clock=float(data.clock); _day=int(data.day); _next_person=int(data.next_person); _next_event=int(data.next_event)
	_rng.state=int(str(data.get("rng_state","1"))); _requests=data.get("requests",{}).duplicate(true)
	_bindings.clear(); _external_motion.clear(); reservations.clear()
	for id:String in residents:
		var p:Dictionary=residents[id]; p["busy"]=false; p["social_holder"]=""
		if not p.current_action.is_empty(): reserve(id,p.current_action.venue_id,p.current_action.action,float(p.current_action.remaining))
	return true
