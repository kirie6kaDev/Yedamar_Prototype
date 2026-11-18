extends Node3D
## Connects the scene and the serializable life simulation. One record per resident;
## near residents use real navigation, distant residents use the same timed rules.
const LifeSim = preload("res://scripts/life_sim.gd")
const Catalog = preload("res://scripts/life_catalog.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Layout = preload("res://scripts/city_world.gd")
const ACTIVE_RADIUS := 240.0
const ACTIVE_LIMIT := 28
var game
var city
var sim
var citizens:Dictionary={}
var proxies:Dictionary={}
var motion_targets:Dictionary={}
var motion_attempts:Dictionary={}
var social_locks:Dictionary={}
var house_stores:Dictionary={}
var speed:=1.0
var auto_speed:=false
var next_command:=1
var _elapsed:=0.0
var _population_tick:=0.0
var _autonomy_tick:=0.0
var _weather_tick:=0.0
var _last_weather:=""
var _rain:GPUParticles3D
var _simulation_ready:=false

func configure(owner_game,city_node)->void:
	game=owner_game
	city=city_node
	sim=LifeSim.new()
	sim.configure({"venues":city.get_venues(),"workplaces":city.get_workplaces(),"seed":782941,"absolute_minutes":_clock()})
	_register_facilities()
	for role in game._roles(): sim.register_player(str(role),game.state.characters[role])
	ensure_actors()
	for role in game._roles(): sim.sync_player(str(role),game.state.characters[role],game._hero(role).position)
	game.hud.life_requested.connect(request)
	_simulation_ready=true
	_sync_family()
	_update_population()

func _clock()->float:
	return float(game.caravan.day_number)*1440.0+float(game.caravan.day_time)

func _vec(value)->Vector3:
	if value is Vector3: return value
	if value is Array and value.size()==3: return Vector3(float(value[0]),float(value[1]),float(value[2]))
	return Vector3.ZERO

func _register_facilities()->void:
	for id in city.get_objects():
		if not game.world.objects.has(id): continue
		var info:Dictionary=city.get_object(id)
		var obj:Dictionary=game.world.objects[id]
		var parent_id:String=str(info.get("venue_id",""))
		var parent:Dictionary=sim.venues.get(parent_id,{})
		if sim.venues.has(id): continue
		var record:Dictionary=parent.duplicate(true)
		record.merge({"id":str(id),"name":str(obj.name),"position":game._vector(obj.get("approach",obj.position)),"approach":game._vector(obj.get("approach",obj.position)),"kind":str(info.get("prop",info.get("kind",obj.type))),"parent":parent_id,"capacity":1,"safe":true,"professions":[],"workstations":[],"buyable":false},true)
		sim.venues[str(id)]=record
	for id in game.settlement.buildings:
		_register_building(str(id))

func _register_building(id:String)->void:
	if not game.world.objects.has(id): return
	var obj:Dictionary=game.world.objects[id]
	var kind:String=str(obj.type)
	var mapped:String={"shelter":"home","bed":"bed","storage":"pantry","bath":"bath","latrine":"latrine","hearth":"hearth","bench":"bench","bookshelf":"bookshelf","training":"training","dining":"dining"}.get(kind,kind)
	sim.venues[id]={"id":id,"name":str(obj.name),"position":game._vector(obj.get("approach",obj.position)),"approach":game._vector(obj.get("approach",obj.position)),"kind":mapped,"capacity":1,"safe":true,"owner":"house_player","professions":[],"buyable":false}
	for home in sim.households.get("house_player",{}).get("properties",[]):
		if not sim.venues.has(home): continue
		var venue:Dictionary=sim.venues[home]
		var center:Vector3=_vec(venue.get("center",venue.position))
		var size:Array=venue.get("size",[40,40])
		if absf(obj.position.x-center.x)<=float(size[0])*.5 and absf(obj.position.z-center.z)<=float(size[1])*.5:
			sim.venues[id]["parent"]=home
			break

func ensure_actors()->void:
	for id in game.extra_actors.keys():
		if game.state.characters.has(id): continue
		var old=game.extra_actors[id]
		if is_instance_valid(old): old.selected=false; old.queue_free()
		game.world.objects.erase(id)
		game.extra_actors.erase(id)
	for id in game._roles():
		if id in ["brother","sister"]: continue
		if not game.extra_actors.has(id):
			var point:Vector3=game._ground(game.FARM_START+Vector2(4,4))
			if game.state.get("positions",{}).has(id): point=game._decode_position(game.state.positions[id])
			var actor=citizens.get(id)
			if not is_instance_valid(actor): actor=_create_actor(str(id),str(game.state.characters[id].get("name","Домочадец")),point)
			game.extra_actors[id]=actor
			actor.health=float(game.state.characters[id].get("health",100))
			citizens.erase(id)
			if not actor.movement_failed.is_connected(game._movement_failed.bind(str(id))): actor.movement_failed.connect(game._movement_failed.bind(str(id)))
		if not game.orders.has(id): game.orders[id]=[]

func _sync_family()->void:
	for id in sim.residents:
		var record:Dictionary=sim.residents[id]
		if str(record.get("household_id",""))!="house_player" or not record.get("alive",true): continue
		if game.state.characters.has(id): continue
		var person:Dictionary=game.Campaign.character_state(record.get("inventory",{}),float(record.get("health",100)))
		person["name"]=record.name
		person.skills=record.get("skills",{}).duplicate(true)
		for need in record.get("needs",{}): person["sleep" if need=="energy" else need]=record.needs[need]
		game.state.characters[str(id)]=person
		game.orders[str(id)]=[]
		game.state.get_or_add("positions",{})[str(id)]=record.position.duplicate()
		ensure_actors()
		sim.register_player(str(id),person)
		game._hero(str(id)).position=sim.position_of(str(id))
	for id in game._roles().duplicate():
		if id in ["brother","sister"]: continue
		if not sim.residents.has(id) or str(sim.residents[id].get("household_id",""))!="house_player" or not sim.residents[id].get("alive",true):
			cancel(str(id))
			if game.active.role==id: game._select_character("brother")
			if game.extra_actors.has(id): citizens[id]=game.extra_actors[id]; game.extra_actors.erase(id)
			game.state.characters.erase(id)
			game.orders.erase(id)
			if sim.residents.has(id): sim.residents[id].external=false

func _create_actor(id:String,title:String,point:Vector3):
	var actor=game._actor("enemy",title,point)
	actor.role=id
	actor.set_meta("object_id",id)
	actor.collision_layer=2
	actor.move_speed=5.0
	actor.movement_failed.connect(_npc_unreachable.bind(id))
	if proxies.has(id): proxies[id].queue_free(); proxies.erase(id)
	game.world.objects[id]={"id":id,"type":"life_person","name":title,"description":"Житель со своим домом, семьёй, делами и распорядком.","position":point,"approach":point,"node":actor}
	return actor

func _npc_unreachable(id:String)->void:
	if game.state.characters.has(id): return
	if game.v5 and not game.v5.domestic.npc_target(id).is_empty():
		if game.v5.domestic.has_method("report_unreachable"): game.v5.domestic.report_unreachable(id)
		motion_targets.erase(id)
		return
	var target:Dictionary=sim.next_target(id)
	if not target.is_empty(): sim.report_unreachable(id,str(target.get("id","")))
	motion_targets.erase(id)

func tick(delta:float)->void:
	if not _simulation_ready: return
	for role in game._roles():
		sim.sync_player(str(role),game.state.characters[role],game._hero(role).position)
		sim.set_busy(str(role),not game.orders[role].is_empty() and str(game.orders[role][0].get("phase",""))=="working")
	for id in citizens:
		if is_instance_valid(citizens[id]): sim.set_position(str(id),citizens[id].position)
	_elapsed+=delta
	if _elapsed>=.5:
		sim.advance(_elapsed,_clock())
		_elapsed=0.0
	_population_tick-=delta
	if _population_tick<=0:
		_population_tick=.7
		_sync_family()
		_update_population()
	_autonomy_tick-=delta
	if _autonomy_tick<=0:
		_autonomy_tick=3.0
		_autonomy()
	_weather_tick-=delta
	if _weather_tick<=0:
		_weather_tick=3.0
		_weather()
	if game.in_combat and Engine.time_scale>1:
		speed=1.0
		auto_speed=false
		Engine.time_scale=1.0
	var all_asleep:bool=not game._roles().is_empty()
	for role in game._roles():
		if not game.state.characters[role].get("sleeping",false): all_asleep=false
	if all_asleep and not game.in_combat:
		Engine.time_scale=maxf(speed,6.0)
		auto_speed=true
	elif auto_speed:
		Engine.time_scale=speed
		auto_speed=false
	if city.has_method("tick"): city.tick(delta,game.caravan.is_night())

func _update_population()->void:
	var center:Vector3=game.camera_rig._focus
	var nearby:Array=[]
	for id in sim.residents:
		var record:Dictionary=sim.residents[id]
		if game.state.characters.has(id): continue
		var point:Vector3=sim.position_of(str(id))
		if record.get("alive",true) and point.distance_to(center)<ACTIVE_RADIUS:
			nearby.append({"id":str(id),"distance":point.distance_to(center)})
		if not game.world.objects.has(id):
			var proxy:=Node3D.new()
			add_child(proxy)
			proxy.visible=false
			proxy.position=point
			proxies[id]=proxy
			game.world.objects[id]={"id":id,"type":"life_person","name":record.name,"description":"Житель: дом, профессия, семья и личные отношения.","position":point,"approach":point,"node":proxy}
		game.world.objects[id].position=point
		game.world.objects[id].approach=point
	nearby.sort_custom(func(a,b):return a.distance<b.distance)
	var wanted:Array=[]
	for row in nearby.slice(0,ACTIVE_LIMIT): wanted.append(row.id)
	for id in social_locks:
		if not wanted.has(id): wanted.append(id)
	for id in citizens.keys():
		if wanted.has(id): continue
		var actor=citizens[id]
		sim.set_position(str(id),actor.position)
		sim.set_external_motion(str(id),false)
		game.world.objects.erase(id)
		actor.queue_free()
		citizens.erase(id)
		motion_targets.erase(id)
		motion_attempts.erase(id)
	for id in wanted:
		if not sim.residents.has(id) or game.state.characters.has(id): continue
		var record:Dictionary=sim.residents[id]
		if not citizens.has(id):
			citizens[id]=_create_actor(str(id),str(record.name),sim.position_of(str(id)))
			sim.set_external_motion(str(id),true)
		var actor=citizens[id]
		_present(actor,record)
		game.world.objects[id].position=actor.position
		game.world.objects[id].approach=actor.position
		if social_locks.has(id):
			actor.stop_moving()
			continue
		var target:Dictionary=game.v5.domestic.npc_target(str(id)) if game.v5 else {}
		if target.is_empty(): target=sim.next_target(str(id))
		if target.is_empty():
			if not actor._work_clip.is_empty(): actor.end_work()
			continue
		var point:Vector3=_vec(target.position)
		var target_key:String=str(target.get("id",""))+":"+str(target.get("action",""))
		if str(target.get("phase","walking"))=="working":
			if game._flat_distance(actor.position,point)>1.8: continue
			var animation:String=str(target.get("animation","interact"))
			if actor._work_clip.is_empty(): actor.begin_work(animation)
		else:
			if not actor._work_clip.is_empty(): actor.end_work()
			if game._flat_distance(actor.position,point)>1.5 and (motion_targets.get(id,"")!=target_key or not actor.is_moving()):
				var retry:bool=motion_targets.get(id,"")==target_key
				motion_targets[id]=target_key
				motion_attempts[id]=int(motion_attempts.get(id,0))+1 if retry else 1
				# Give up on a target the route cannot get close to instead of
				# re-planning it every population tick forever (stuck, A* spam).
				if int(motion_attempts[id])>3 or not actor.navigate_to(point) or actor.path_gap>1.5:
					motion_attempts.erase(id)
					motion_targets.erase(id)
					sim.report_unreachable(str(id),str(target.get("id","")))
	for role in game._roles():
		if sim.residents.has(role): _present(game._hero(role),sim.residents[role])

func _present(actor,record:Dictionary)->void:
	actor.display_name=str(record.name)
	if is_instance_valid(actor._label): actor._label.text=actor.display_name
	if actor.has_method("apply_appearance"):
		var appearance:Dictionary=record.get("appearance",{}).duplicate(true)
		appearance["gender"]=record.get("gender","male")
		actor.apply_appearance(appearance,str(record.get("stage","adult")))

func _autonomy()->void:
	for role in game._roles():
		if not bool(sim.residents.get(role,{}).get("autonomy",false)): continue
		if game.v5 and game.v5.is_conversing(str(role)): continue
		if game._role_in_combat(str(role)): continue
		if game._ranch_busy(str(role)): continue
		if not game.orders[role].is_empty() or not str(game.state.characters[role].get("work_mode","")).is_empty() or game._caravan_busy(str(role)): continue
		var suggestion:Dictionary=game.v5.domestic.suggest_action(str(role)) if game.v5 else {}
		if suggestion.is_empty(): suggestion=sim.suggest_action(str(role))
		if suggestion.is_empty(): continue
		_queue_command(str(role),str(suggestion.get("action","")),suggestion.get("payload",{}),true)

func request(action:String,payload:Dictionary={})->void:
	if game.v5 and game.v5.request(action,payload): return
	var role:String=str(payload.get("actor_id",game.active.role))
	if not game.state.characters.has(role): role=str(game.active.role)
	if action.begins_with("ranch_"):
		game._on_action(action,str(payload.get("target_id","")))
		return
	if action=="focus_animal":
		var id:String=str(payload.get("target_id",""))
		if game.ranch and game.ranch.owns(id):
			game.camera_rig.focus_point(game.ranch.get_animal_position(id))
			game.hud._close_windows()
		return
	if action=="set_speed":
		var value:float=clampf(float(payload.get("value",1)),0,3)
		if value<=0: game._pause()
		else:
			speed=value
			Engine.time_scale=value
			auto_speed=false
			if game.get_tree().paused: game._resume()
		update_ui()
		return
	if action in ["select_member","select"]:
		var id:String=str(payload.get("target_id",payload.get("id",payload.get("actor_id",""))))
		if game.state.characters.has(id): game._select_character(id); game.camera_rig.focus_on(game._hero(id)); game.hud._close_windows()
		return
	if action in ["focus_person","focus","view_person"]:
		var id:String=str(payload.get("target_id",payload.get("id",role)))
		if sim.residents.has(id): game.camera_rig.focus_point(sim.position_of(id)); game.hud._close_windows()
		return
	if action in ["focus_home","focus_venue"]:
		focus_site(str(payload.get("home_id",payload.get("venue_id",""))))
		game.hud._close_windows()
		return
	if action=="go_home":
		var home:String=str(sim.residents.get(role,{}).get("home_id",""))
		if sim.venues.has(home): game._enqueue(role,{"action":"move","position":_vec(sim.venues[home].position),"phase":"waiting"})
		game.hud._close_windows()
		return
	if action=="cutaway":
		city.set_cutaway(bool(payload.get("enabled",true)))
		for id in game.settlement.buildings:
			if game.settlement.buildings[id].kind=="roof" and game.world.objects.has(id): game.world.objects[id].node.visible=not bool(payload.get("enabled",true))
		return
	_queue_command(role,action,payload,false)

func request_context(verb:String,id:String)->void:
	if game.v5 and game.v5.context_request(verb,id): return
	var payload:Dictionary={"actor_id":str(game.active.role)}
	if verb=="visit":
		if game.world.objects.has(id): game._enqueue(str(game.active.role),{"action":"move","position":game.world.objects[id].get("approach",game.world.objects[id].position),"phase":"waiting"})
		return
	if city.owns(id):
		for row in city.actions(id,game.state.characters[game.active.role]):
			if row.id=="life:"+verb and not str(row.get("target_id","")).is_empty():
				id=str(row.target_id)
				break
	if sim.residents.has(id): payload.target_id=id
	else:
		payload.venue_id=id
		if city.owns(id):
			var info:Dictionary=city.get_object(id)
			if info.has("profession"): payload.profession_id=info.profession
	if verb=="buy_home": payload.home_id=str(city.get_object(id).get("venue_id",id))
	if verb in ["stash_put","stash_take"]: payload.home_id=str(city.get_object(id).get("venue_id",id))
	if verb=="social":
		var closest:=""
		var distance:=70.0
		for person_id in sim.residents:
			if person_id==game.active.role: continue
			var d:float=game._flat_distance(game.active.position,sim.position_of(str(person_id)))
			if d<distance: closest=str(person_id); distance=d
		payload.target_id=closest
	if verb in ["shop","profile","career"]:
		if game.hud.has_method("show_life"): game.hud.show_life("market" if verb=="shop" else ("careers" if verb=="career" else "people"))
		return
	var translated:String={"rest":"relax","play":"relax","social":"socialize","pray":"relax","study":"study","cook":"cook"}.get(verb,verb)
	_queue_command(str(game.active.role),translated,payload,false)

func _queue_command(role:String,action:String,payload:Dictionary,automatic:bool)->void:
	if action.is_empty() or game._role_in_combat(role) or game._caravan_busy(role): return
	sim.sync_player(role,game.state.characters[role],game._hero(role).position)
	var clean:Dictionary=payload.duplicate(true)
	clean.actor_id=role
	var spec:Dictionary=_spec(role,action,clean)
	if not spec.get("ok",false):
		if not automatic: game.hud.toast(str(spec.get("reason","Действие недоступно.")))
		return
	clean.request_id=role+"_"+str(next_command)
	next_command+=1
	if not str(spec.get("venue_id","")).is_empty() and not str(spec.venue_id).begins_with("person:"): clean.venue_id=str(spec.venue_id)
	if float(spec.get("duration",0))<=0 and spec.get("portable",false):
		var result:Dictionary=_execute(role,action,clean)
		if not automatic: game.hud.toast(str(result.get("message","")))
		_sync_family()
		update_ui()
		return
	var label:String=str(spec.get("label",_action_name(action)))
	game._enqueue(role,{"action":"life:"+action,"payload":clean,"position":spec.get("target",game._hero(role).position),"id":str(spec.get("venue_id","")),"duration":float(spec.get("duration",10)),"remaining":0.0,"phase":"waiting","automatic":automatic,"label":label})

func run_order(role:String,delta:float)->void:
	var queue:Array=game.orders[role]
	if queue.is_empty(): return
	var order:Dictionary=queue[0]
	var actor=game._hero(role)
	var action:String=str(order.action).trim_prefix("life:")
	var payload:Dictionary=order.get("payload",{})
	sim.sync_player(role,game.state.characters[role],actor.position)
	var spec:Dictionary=_spec(role,action,payload)
	if not spec.get("ok",false):
		_finish_order(role,str(spec.get("reason","Действие больше недоступно.")))
		return
	var target:Vector3=spec.get("target",actor.position)
	var portable:bool=bool(spec.get("portable",false))
	var venue_id:String=str(spec.get("venue_id",""))
	if str(order.phase)=="waiting":
		order.phase="walking"
		actor.end_work()
		if not portable and game._flat_distance(actor.position,target)>1.6 and not actor.navigate_to(target):
			_finish_order(role,"Не удалось найти подход.")
			return
	if str(order.phase)=="walking":
		if not portable and game._flat_distance(actor.position,target)>1.7:
			if not actor.is_moving():
				# Arrived as close as the route allows but still too far: re-planning
				# every frame used to loop forever (per-frame A* = lag, stuck hero).
				order["repaths"]=int(order.get("repaths",0))+1
				if int(order.repaths)>3 or not actor.navigate_to(target) or actor.path_gap>1.7:
					_finish_order(role,"Путь к месту закрыт.")
			return
		actor.stop_moving()
		if not venue_id.is_empty() and not sim.reserve(role,venue_id,action,float(spec.get("duration",10))+30):
			order["waited"]=float(order.get("waited",0))+delta
			if float(order.waited)>120: _finish_order(role,"Место занято слишком долго. Действие отменено.")
			return
		if game.v5 and not game.v5.reserve(role,action,venue_id,float(spec.get("duration",10))+30):
			sim.release(role)
			order["waited"]=float(order.get("waited",0))+delta
			if float(order.waited)>120: _finish_order(role,"Предмет всё ещё занят. Действие отменено.")
			return
		order.phase="working"
		if float(order.get("remaining",0))<=0: order.remaining=float(spec.get("duration",10))
		order.duration=float(spec.get("duration",10))
		actor.begin_work(str(spec.get("animation","interact")))
		if action=="sleep": game.state.characters[role].sleeping=true
		var other:String=str(payload.get("target_id",""))
		if sim.residents.has(other):
			social_locks[other]=role
			sim.set_social_hold(other,role)
			if citizens.has(other): citizens[other].stop_moving()
	if str(order.phase)=="working":
		if not portable and game._flat_distance(actor.position,target)>2:
			cancel(role)
			order.phase="waiting"
			return
		if not venue_id.is_empty(): sim.reserve(role,venue_id,action,float(order.remaining)+30)
		if game.v5: game.v5.reserve(role,action,venue_id,float(order.remaining)+30)
		order.remaining=float(order.remaining)-delta
		if float(order.remaining)<=0:
			var result:Dictionary=_execute(role,action,payload)
			_finish_order(role,str(result.get("message","")),not order.get("automatic",false) or not result.get("ok",false))
			_sync_family()
			game._update_ui()

func _finish_order(role:String,message:String,notify:bool=true)->void:
	cancel(role)
	game._hero(role).stop_moving()
	game._hero(role).end_work()
	if not game.orders[role].is_empty(): game.orders[role].pop_front()
	if notify and not message.is_empty(): game.hud.toast(message)

func cancel(role:String)->void:
	if sim: sim.release(role)
	if game.v5: game.v5.release(role)
	for id in social_locks.keys():
		if social_locks[id]==role:
			sim.set_social_hold(str(id),"")
			social_locks.erase(id)
	if game.state.characters.has(role): game.state.characters[role].sleeping=false

func context_actions(id:String,role:String)->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	if game.v5:
		for row in game.v5.context_actions(id,role):
			var converted:Dictionary=row.duplicate(true)
			converted.id="life:"+str(converted.id)
			rows.append(converted)
	if sim.residents.has(id):
		for action in ["socialize","joke","compliment","apologize","insult","flirt","invite_household"]:
			var spec:Dictionary=sim.command_spec(role,action,{"target_id":id})
			rows.append({"id":"life:"+action,"label":_action_name(action),"enabled":bool(spec.get("ok",false)),"reason":str(spec.get("reason",""))})
		return rows
	if city.owns(id):
		rows.append_array(city.actions(id,game.state.characters[role]))
		var profession:String=str(city.get_object(id).get("profession",""))
		if not profession.is_empty(): rows.append({"id":"life:apply_job","label":"Поступить на работу","enabled":true,"reason":""})
		var info:Dictionary=city.get_object(id)
		if info.get("prop","")=="pantry":
			for action in ["stash_put","stash_take"]:
				var spec:Dictionary=_spec(role,action,{"home_id":info.get("venue_id","")})
				rows.append({"id":"life:"+action,"label":"Сложить вещи в кладовую" if action=="stash_put" else "Забрать вещи из кладовой","enabled":spec.get("ok",false),"reason":spec.get("reason","")})
		return rows
	if game.settlement.buildings.has(id):
		_register_building(id)
		var kind:String=str(game.world.objects[id].type)
		var actions:Array={"bath":["wash"],"latrine":["toilet"],"hearth":["cook","relax"],"bench":["relax","read"],"bookshelf":["read"],"training":["train"],"dining":["eat"]}.get(kind,[])
		for action in actions:
			var spec:Dictionary=sim.command_spec(role,action,{"venue_id":id})
			rows.append({"id":"life:"+action,"label":_action_name(action),"enabled":bool(spec.get("ok",false)),"reason":str(spec.get("reason",""))})
	return rows

func _action_name(action:String)->String:
	return str({"eat":"Поесть","drink":"Попить","wash":"Искупаться / умыться","toilet":"Посетить отхожее место","sleep":"Поспать","relax":"Отдохнуть и развлечься","read":"Почитать","train":"Тренироваться","cook":"Приготовить еду","socialize":"Поговорить","joke":"Пошутить","compliment":"Похвалить","apologize":"Извиниться","insult":"Поссориться","flirt":"Флиртовать","propose":"Предложить брак","plan_child":"Планировать ребёнка","invite_household":"Предложить жить вместе","educate":"Учиться","work":"Работать","apply_job":"Устроиться на работу","buy":"Купить","sell":"Продать","move_home":"Переехать","buy_home":"Купить дом"}.get(action,action))

var _ui_next_ms:=0

## force=false is the periodic 0.2 s HUD refresh. Building the full life-book
## model (sim.ui_state + civic/domestic rows) costs ~45 ms, so while the life
## window is closed it is rebuilt at most every 1.5 s (was a 5 Hz frame hitch).
func update_ui(force:bool=true)->void:
	if not _simulation_ready or not game.hud.has_method("update_life"): return
	var open:bool=game.hud._life_ui!=null and game.hud._life_ui.panel.visible
	var now:=Time.get_ticks_msec()
	if not force and not open and now<_ui_next_ms: return
	_ui_next_ms=now+1500
	var data:Dictionary=sim.ui_state(str(game.active.role))
	data.summary.speed=0 if game.get_tree().paused else Engine.time_scale
	data.summary.speed_actions=[]
	for value in [0,1,2,3]: data.summary.speed_actions.append({"id":"set_speed","label":"Ⅱ" if value==0 else str(value)+"×","payload":{"value":value},"enabled":true,"reason":""})
	data.summary["cutaway_actions"]=[{"id":"cutaway","label":"Скрыть крыши","payload":{"enabled":true},"enabled":true},{"id":"cutaway","label":"Показать крыши","payload":{"enabled":false},"enabled":true}]
	for row in data.get("household",[]):
		if not row is Dictionary: continue
		var id:String=str(row.get("id",""))
		if game.state.characters.has(id):
			var present:=false
			for action in row.get("actions",[]):
				if action.get("id","")=="select_member": present=true
			if not present: row.get_or_add("actions",[]).append({"id":"select_member","label":"Управлять","payload":{"target_id":id},"enabled":true})
	for row in data.get("properties",[]):
		var home:String=str(row.get("id",""))
		if sim.households.get("house_player",{}).get("properties",[]).has(home):
			row.get_or_add("details",[]).append("Кладовая: "+str(_store(home)))
			for action in ["stash_put","stash_take"]: row.get_or_add("actions",[]).append({"id":action,"label":"Отнести вещи в кладовую" if action=="stash_put" else "Забрать вещи из кладовой","payload":{"home_id":home},"enabled":true})
	data["animals"]=[]
	if game.ranch:
		for id in game.ranch.get_animals():
			var a:Dictionary=game.ranch.animals[id]
			var details:Array=[str(game.ranch.SPECIES[a.species].name)+" · "+("Принадлежит семье" if a.owner=="house_player" else "Ищет хозяина" if str(a.owner).is_empty() else "Можно купить"),"Здоровье %d · силы %d · корм %d · вода %d"%[a.health,a.stamina,a.food,a.water],str(a.status)]
			if not str(a.produce).is_empty(): details.append("Готово: %d · %s"%[int(a.stock),str(Campaign.ITEMS.get(a.produce,a.produce))])
			if float(a.gestation)>0: details.append("Ожидается потомство")
			var actions:Array=game.ranch.actions(id,game._person(str(game.active.role)))
			for entry in actions: entry.payload={"target_id":id}
			actions.push_front({"id":"focus_animal","label":"Показать на карте","payload":{"target_id":id},"enabled":true})
			data.animals.append({"id":id,"name":a.name,"details":details,"actions":actions})
	if game.v5: game.v5.merge_ui(data,str(game.active.role))
	game.hud.update_life(data)

func map_sites()->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	for id in city.get_venues():
		var venue:Dictionary=sim.venues.get(id,{})
		if venue.is_empty() or str(venue.get("kind",""))=="home": continue
		rows.append({"id":str(id),"name":str(venue.name),"position":_vec(venue.position)})
	for id in sim.households.get("house_player",{}).get("properties",[]):
		if sim.venues.has(id): rows.append({"id":str(id),"name":str(sim.venues[id].name),"position":_vec(sim.venues[id].position)})
	return rows

func focus_site(id:String)->bool:
	if not sim.venues.has(id): return false
	game.camera_rig.focus_point(_vec(sim.venues[id].position))
	return true

func travel_site(id:String)->bool:
	if not sim.venues.has(id): return false
	if game.in_combat: game.hud.toast("Сначала выйдите из боя."); return true
	game._prepare_trip()
	if not game.caravan.travel_to_animal(_vec(sim.venues[id].position)): game.hud.toast("Повозка не может пройти. Можно отправить героя пешком через список домов.")
	else: game.hud.toast("Собираемся в путь · "+str(sim.venues[id].name))
	return true

func can_build(point:Vector3,role:String="",kind:String="")->String:
	if game.v5: return game.v5.civic.can_build(str(game.active.role) if role.is_empty() else role,point,kind)
	if not Layout.CITY_RECT.has_point(Vector2(point.x,point.z)): return ""
	for id in sim.households.get("house_player",{}).get("properties",[]):
		if sim.venues.has(id) and game._flat_distance(point,_vec(sim.venues[id].position))<17: return ""
	return "В городе строить можно на принадлежащем семье участке. Дома продаются в разделе «Жизнь → Дом»."

func is_safe(point:Vector3)->bool:
	var p:=Vector2(point.x,point.z)
	return Layout.CITY_RECT.has_point(p) or p.distance_to(Layout.SECOND_CENTER)<110 or p.distance_to(Vector2(4030,4385))<95

func _weather()->void:
	var weather:String=str(Catalog.WEATHER_NAMES.get(sim.weather.get("id","clear"),"Ясно"))
	_last_weather=weather
	var wet:bool="дожд" in weather.to_lower() or "гроза" in weather.to_lower() or "rain" in weather or "storm" in weather
	var snowy:bool="снег" in weather.to_lower() or "snow" in weather
	if wet:
		for id in game.farm.plots: game.farm.plots[id].water=minf(100,float(game.farm.plots[id].water)+2)
		for id in game.farm.trees: game.farm.trees[id].water=minf(100,float(game.farm.trees[id].water)+2)
	if game.caravan._environment:
		game.caravan._environment.fog_density=.00065 if wet or snowy else .00025
	if not is_instance_valid(_rain): _make_weather()
	if is_instance_valid(_rain):
		_rain.position=game.active.position+Vector3.UP*16
		_rain.emitting=wet or snowy
		var material:ParticleProcessMaterial=_rain.process_material
		material.gravity=Vector3(1,-1.5,0) if snowy else Vector3(3,-19,0)
		material.color=Color(1,1,1,.8) if snowy else Color(.65,.8,.95,.45)

func _make_weather()->void:
	_rain=GPUParticles3D.new()
	_rain.amount=500
	_rain.lifetime=2.0
	_rain.visibility_aabb=AABB(Vector3(-40,-25,-40),Vector3(80,55,80))
	var mat:=ParticleProcessMaterial.new()
	mat.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents=Vector3(26,1,26)
	mat.direction=Vector3.DOWN
	mat.initial_velocity_min=8
	mat.initial_velocity_max=12
	_rain.process_material=mat
	var mesh:=BoxMesh.new()
	mesh.size=Vector3(.035,.45,.035)
	var visible_mat:=StandardMaterial3D.new()
	visible_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	visible_mat.vertex_color_use_as_albedo=true
	visible_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material=visible_mat
	_rain.draw_pass_1=mesh
	_rain.emitting=false
	add_child(_rain)

func snapshot()->Dictionary:
	for role in game._roles(): sim.sync_player(str(role),game.state.characters[role],game._hero(role).position)
	for id in citizens:
		if is_instance_valid(citizens[id]): sim.set_position(str(id),citizens[id].position)
	return {"version":1,"simulation":sim.snapshot(),"city":city.snapshot(),"speed":speed,"next_command":next_command,"house_stores":house_stores.duplicate(true)}

func valid_snapshot(data:Dictionary)->bool:
	if not data.get("house_stores",{}) is Dictionary: return false
	for contents in data.get("house_stores",{}).values():
		if not game._valid_counts(contents): return false
	return int(data.get("version",0))==1 and data.get("simulation") is Dictionary and sim.valid_snapshot(data.simulation) and data.get("city",{}) is Dictionary and city.valid_snapshot(data.get("city",{})) and game._number(data.get("speed",1)) and float(data.get("speed",1))>=1 and float(data.get("speed",1))<=3 and game._number(data.get("next_command",1))

func restore(data:Dictionary)->void:
	for role in game._roles(): cancel(str(role))
	social_locks.clear()
	motion_targets.clear()
	for id in citizens.keys():
		if is_instance_valid(citizens[id]): citizens[id].queue_free()
		game.world.objects.erase(id)
	citizens.clear()
	for id in proxies:
		if is_instance_valid(proxies[id]): proxies[id].queue_free()
		game.world.objects.erase(id)
	proxies.clear()
	if data.is_empty():
		sim=LifeSim.new()
		var saved_clock:Dictionary=game.state.get("caravan",{})
		var restored_minutes:float=float(saved_clock.get("day_number",game.caravan.day_number))*1440+float(saved_clock.get("day_time",game.caravan.day_time))
		sim.configure({"venues":city.get_venues(),"workplaces":city.get_workplaces(),"seed":782941,"absolute_minutes":restored_minutes})
	else:
		sim.restore(data.simulation)
		city.restore(data.get("city",{}))
		speed=clampf(float(data.get("speed",1)),1,3)
		next_command=maxi(1,int(data.get("next_command",1)))
	house_stores=data.get("house_stores",{}).duplicate(true)
	_register_facilities()
	for role in game._roles(): sim.register_player(str(role),game.state.characters[role])
	_sync_family()
	Engine.time_scale=speed
	auto_speed=false
	_elapsed=0
	_population_tick=0
	_autonomy_tick=1

func _store(home:String)->Dictionary:
	var family:Dictionary=sim.households.get("house_player",{})
	if str(family.get("home_id",""))==home: return family.get_or_add("inventory",{})
	return house_stores.get_or_add(home,{})

func _spec(role:String,action:String,payload:Dictionary)->Dictionary:
	if game.v5 and game.v5.owns_action(action): return game.v5.spec(role,action,payload)
	if action not in ["stash_put","stash_take"]: return sim.command_spec(role,action,payload)
	var home:String=str(payload.get("home_id",""))
	if not sim.households.get("house_player",{}).get("properties",[]).has(home) and not (game.v5 and game.v5.civic.can_use_shelter(role,home)): return {"ok":false,"reason":"Эта кладовая принадлежит другому хозяйству."}
	var venue:String=home
	for id in city.get_objects():
		var obj:Dictionary=city.get_object(id)
		if obj.get("venue_id","")==home and obj.get("prop","")=="pantry": venue=str(id); break
	return {"ok":true,"reason":"","target":_vec(sim.venues[venue].position),"venue_id":venue,"duration":8.0,"animation":"interact","portable":false,"label":"Перенести вещи в кладовую" if action=="stash_put" else "Забрать вещи из кладовой"}

func _execute(role:String,action:String,payload:Dictionary)->Dictionary:
	if game.v5 and game.v5.owns_action(action): return game.v5.execute(role,action,payload)
	if action=="move_home":
		var family:Dictionary=sim.households["house_player"]
		var old_home:String=str(family.home_id)
		var old_contents:Dictionary=family.inventory.duplicate(true)
		var result:Dictionary=sim.command(role,action,payload)
		if result.get("ok",false) and str(family.home_id)!=old_home:
			house_stores[old_home]=old_contents
			family.inventory=house_stores.get(str(family.home_id),{}).duplicate(true)
			house_stores.erase(str(family.home_id))
			result.message="Новый дом выбран. Вещи остались в прежней кладовой: перевезите их в рюкзаках или телеге."
		return result
	if action not in ["stash_put","stash_take"]: return sim.command(role,action,payload)
	var spec:Dictionary=_spec(role,action,payload)
	if not spec.ok: return {"ok":false,"message":spec.reason}
	if game._flat_distance(game._hero(role).position,spec.target)>2.2: return {"ok":false,"message":"Подойдите к кладовой."}
	var store:Dictionary=_store(str(payload.home_id))
	var inv:Dictionary=game._inventory(role)
	var source:Dictionary=inv if action=="stash_put" else store
	var destination:Dictionary=store if action=="stash_put" else inv
	var count:=0
	for item in source.keys():
		var amount:int=int(source[item])
		if amount<=0: continue
		if action=="stash_put" and game.Campaign.EQUIPMENT.has(item): continue
		destination[item]=int(destination.get(item,0))+amount
		source[item]=0
		count+=amount
	return {"ok":true,"message":"Перенесено вещей: "+str(count)+". Содержимое этой кладовой остаётся в доме."}
