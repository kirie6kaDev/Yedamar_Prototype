extends Node3D
## Local gameplay extensions share the existing queues, clock and save transaction.
const Civic=preload("res://scripts/civic_life.gd")
const Domestic=preload("res://scripts/domestic_life.gd")
const Activities=preload("res://scripts/activities.gd")
const Builder=preload("res://scripts/build_editor.gd")
var game
var civic
var domestic
var activities
var builder
var conversations:Dictionary={}

func configure(owner_game)->void:
	game=owner_game
	civic=Civic.new(); civic.configure(game.life.sim,{"legacy":false})
	domestic=Domestic.new(); add_child(domestic); domestic.configure(game)
	activities=Activities.new(); add_child(activities); activities.configure(game)
	builder=Builder.new(); builder.configure(game)
	_bind()

func _bind()->void:
	game.life.sim.domestic_care_enabled=true
	if game.state.flags.get("farmer",false):
		civic.grant_build_license("brother","marta_farm",game._ground(Vector2(4020,4420)),Vector2(100,100),game.settlement.BLUEPRINTS.keys(),"Разрешение Марты на хозяйственные постройки у фермы")
	game.life.sim.command_policy=Callable(self,"_policy")
	game.life.sim.command_observer=Callable(self,"_observed")
	for id in domestic.get_venues(): game.life.sim.venues[id]=domestic.get_venues()[id]
	for id in activities.sites:
		var obj:Dictionary=game.world.objects[id]
		game.life.sim.venues[id]={"id":id,"name":obj.name,"kind":"activity","position":game._vector(obj.approach),"capacity":1,"safe":false}
	# V4 snapshots did not know these lots. They are added without changing old deeds.
	for id in game.city.get_venues():
		if not game.life.sim.venues.has(id): game.life.sim.venues[id]=game.city.get_venues()[id].duplicate(true)

func _policy(role:String,action:String,payload:Dictionary,specification:Dictionary)->String:
	var reason:String=civic.before_action(role,action,payload)
	if not reason.is_empty(): return reason
	return domestic.before_use(role,str(specification.get("venue_id","")),action)

func _observed(role:String,action:String,payload:Dictionary,result:Dictionary,specification:Dictionary)->void:
	civic.after_action(role,action,payload,result)
	domestic.record_use(role,str(specification.get("venue_id","")),action)

func owns_action(action:String)->bool:
	return action.begins_with("civic:") or action.begins_with("home:") or action.begins_with("activity:") or action.begins_with("build:")

func spec(role:String,action:String,payload:Dictionary)->Dictionary:
	if action.begins_with("civic:"): return civic.command_spec(role,action.trim_prefix("civic:"),payload)
	if action.begins_with("home:"): return domestic.spec(role,action.trim_prefix("home:"),payload)
	if action.begins_with("activity:"): return activities.spec(role,action.trim_prefix("activity:"),payload)
	return builder.spec(role,action.trim_prefix("build:"),payload)

func execute(role:String,action:String,payload:Dictionary)->Dictionary:
	var result:Dictionary
	if action.begins_with("civic:"): result=civic.command(role,action.trim_prefix("civic:"),payload)
	elif action.begins_with("home:"): result=domestic.complete(role,action.trim_prefix("home:"),payload)
	elif action.begins_with("activity:"): result=activities.complete(role,action.trim_prefix("activity:"),payload)
	else: result=builder.complete(role,action.trim_prefix("build:"),payload)
	if result.get("ok",false) and not result.get("replayed",false):
		if float(result.get("xp",0))>0: game._award_xp(role,str(result.get("skill","crafting")),float(result.xp))
		if not action.begins_with("civic:"): civic.after_action(role,action,payload,result)
	return result

func reserve(role:String,action:String,id:String,duration:float)->bool:
	if action.begins_with("home:"): return domestic.reserve(role,id,duration)
	if action.begins_with("activity:"): return activities.reserve(role,id,duration)
	return true

func release(role:String)->void:
	domestic.release(role); activities.release(role)

func context_actions(id:String,role:String)->Array:
	var rows:Array=[]
	if domestic.owns(id) or id=="life_clinic": rows.append_array(domestic.context_actions(id,role))
	if activities.owns(id): rows.append_array(activities.actions(id,role))
	if builder.owns(id): rows.append_array(builder.actions(id,role))
	if game.life.sim.venues.has(id) and game.life.sim.venues[id].get("buyable",false):
		var venue:Dictionary=game.life.sim.venues[id]
		var permit:Dictionary=civic.command_spec(role,"permit",{"property_id":id})
		rows.append({"id":"civic:permit","label":"Оформить разрешение в ратуше","payload":{"property_id":id},"enabled":permit.ok,"reason":permit.reason})
		if str(venue.kind)=="plot":
			var purchase:Dictionary=game.life.sim.command_spec(role,"buy_home",{"home_id":id})
			rows.append({"id":"buy_home","label":"Купить участок","enabled":purchase.ok,"reason":purchase.reason})
	if game.state.characters.has(id) and id!=role:
		var reason:String=_chat_reason(role,id)
		rows.append({"id":"parallel_chat","label":"Беседовать, продолжая отдых или еду","payload":{"target_id":id},"enabled":reason.is_empty(),"reason":reason})
	return rows

func context_request(action:String,id:String)->bool:
	if action=="parallel_chat": start_chat(str(game.active.role),id); return true
	if not owns_action(action): return false
	for row in context_actions(id,str(game.active.role)):
		if row.id==action:
			var payload:Dictionary=row.get("payload",{"target_id":id})
			if not request(action,payload): game.life._queue_command(str(game.active.role),action,payload,false)
			return true
	return false

func request(action:String,payload:Dictionary)->bool:
	var role:String=str(payload.get("actor_id",game.active.role))
	if action=="parallel_chat": start_chat(role,str(payload.get("target_id",""))); return true
	if action=="parallel_stop": conversations.erase(role); game.hud.toast("Беседа закончена."); return true
	if action=="activity:focus":
		game.life.focus_site(str(payload.get("target_id",""))); game.hud._close_windows(); return true
	if action=="build:move":
		builder.begin_move(str(payload.get("target_id",""))); return true
	return false

func tick(delta:float)->void:
	var unsafe:Array=[]; var threats:Array=[]
	for role in game._roles():
		if game._role_in_combat(role): threats.append(role)
		if not game.life.is_safe(game._hero(role).position): unsafe.append(role)
	civic.sync({"night":game.caravan.is_night(),"unsafe_actors":unsafe,"threat_actors":threats})
	civic.advance(delta); domestic.tick(delta); activities.tick(delta)
	for role in conversations.keys():
		var chat:Dictionary=conversations[role]
		if not _chat_reason(role,str(chat.target),false).is_empty(): conversations.erase(role); continue
		chat.remaining=float(chat.remaining)-delta
		if float(chat.remaining)<=0:
			game.life.sim._social(role,str(chat.target),"socialize")
			civic.after_action(role,"socialize",{"target_id":chat.target,"request_id":chat.request_id},{"ok":true})
			conversations.erase(role)
			game.hud.toast("Беседа завершилась; основное занятие продолжилось.")

func _compatible(role:String)->bool:
	if game._role_in_combat(role) or game._hero(role).is_moving() or game.state.characters[role].get("sleeping",false): return false
	var queue:Array=game.orders[role]
	if queue.is_empty(): return true
	return str(queue[0].phase)=="working" and str(queue[0].action) in ["rest","life:eat","life:drink","life:relax","life:read","life:home:eat"]

func _chat_reason(role:String,other:String,check_busy:bool=true)->String:
	if not game.state.characters.has(role) or not game.state.characters.has(other) or role==other: return "Выберите другого домочадца."
	if game._flat_distance(game._hero(role).position,game._hero(other).position)>3.2: return "Для совместной беседы подойдите ближе."
	if not _compatible(role) or not _compatible(other): return "Беседа совместима с едой, чтением, отдыхом или бездействием."
	if check_busy:
		for id in conversations:
			if id in [role,other] or conversations[id].target in [role,other]: return "Один из собеседников уже беседует."
	return ""

func start_chat(role:String,other:String)->void:
	var reason:String=_chat_reason(role,other)
	if not reason.is_empty(): game.hud.toast(reason); return
	conversations[role]={"target":other,"remaining":12.0,"request_id":"parallel_"+str(game.life.next_command)}
	game.life.next_command+=1
	game.hud.toast("Беседа началась одновременно с текущим занятием.")

func is_conversing(role:String)->bool:
	for speaker in conversations:
		if speaker==role or str(conversations[speaker].target)==role: return true
	return false

func merge_ui(data:Dictionary,role:String)->void:
	var civic_rows:Dictionary=civic.ui_rows(role)
	for key in ["civic","wishes","fears","sentiments","guilds","emotions"]: data[key]=civic_rows.get(key,[])
	data.summary["status"]=civic_rows.get("summary",{})
	var activities_rows:Dictionary=activities.ui_rows(role)
	for key in activities_rows: data[key]=activities_rows[key]
	var home:Dictionary=domestic.ui_state(role)
	data["domestic"]=home.get("objects",[])+home.get("meals",[])+home.get("care",[])
	data["buildings"]=builder.ui_rows(role)
	for row in data.get("household",[]):
		var other:String=str(row.get("id",""))
		if game.state.characters.has(other) and other!=role:
			var reason:String=_chat_reason(role,other)
			row.get_or_add("actions",[]).append({"id":"parallel_chat","label":"Беседовать параллельно отдыху / еде","payload":{"actor_id":role,"target_id":other},"enabled":reason.is_empty(),"reason":reason})
	if conversations.has(role): data.get_or_add("emotions",[]).push_front({"id":"parallel","name":"Совместная беседа","details":["Осталось: %d мин."%int(conversations[role].remaining)],"actions":[{"id":"parallel_stop","label":"Закончить беседу","payload":{"actor_id":role},"enabled":true}]})
	for row in data.get("properties",[]):
		var id:String=str(row.id)
		if civic.can_use_shelter(role,id): row.get_or_add("details",[]).append("Временный приют. Пользование разрешено; права собственности нет.")

func snapshot()->Dictionary:
	return {"version":1,"civic":civic.snapshot(),"domestic":domestic.snapshot(),"activities":activities.snapshot(),"builder":builder.snapshot(),"conversations":conversations.duplicate(true)}

func valid_snapshot(data:Variant)->bool:
	if not data is Dictionary or int(data.get("version",0))!=1: return false
	if not data.get("conversations",{}) is Dictionary: return false
	for role in data.get("conversations",{}):
		var chat=data.conversations[role]
		if not chat is Dictionary or not chat.get("target") is String or not chat.get("request_id") is String or not game._number(chat.get("remaining")) or float(chat.remaining)<0 or float(chat.remaining)>12: return false
	return civic.valid_snapshot(data.get("civic",{})) and domestic.valid_snapshot(data.get("domestic",{})) and activities.valid_snapshot(data.get("activities",{})) and builder.valid_snapshot(data.get("builder",{}))

func restore(data:Dictionary,legacy:bool)->void:
	civic=Civic.new()
	civic.configure(game.life.sim,{"legacy":legacy or not data.is_empty()})
	if not data.is_empty(): civic.restore(data.civic)
	domestic.restore(data.get("domestic",{})); activities.restore(data.get("activities",{})); builder.restore(data.get("builder",{}))
	conversations=data.get("conversations",{}).duplicate(true)
	_bind()
