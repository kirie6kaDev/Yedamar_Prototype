extends Node3D

const Campaign = preload("res://scripts/campaign.gd")
const Actor = preload("res://scripts/actor.gd")
const Navigation = preload("res://scripts/navigation.gd")
const World = preload("res://scripts/world.gd")
const CameraRig = preload("res://scripts/camera_rig.gd")
const HUD = preload("res://scripts/hud.gd")
const Sound = preload("res://scripts/sound.gd")
const Caravan = preload("res://scripts/caravan.gd")
const SaveStore = preload("res://scripts/save_store.gd")
const Farm = preload("res://scripts/farm.gd")
const Industry = preload("res://scripts/industry.gd")
const Settlement = preload("res://scripts/settlement.gd")
const City = preload("res://scripts/city.gd")
const LifeBridge = preload("res://scripts/life_bridge.gd")
const SceneBatcher = preload("res://scripts/scene_batcher.gd")
const CityDressing = preload("res://scripts/city_dressing.gd")
const Ranch = preload("res://scripts/ranch.gd")
const V5Bridge = preload("res://scripts/v5_bridge.gd")
const FARM_START := Vector2(4019,4399)
const REACH := 1.4
const SITES := {
	"farm": {"name":"Ферма Марты","xz":Vector2(4031,4385)},
	"herbalist":{"name":"Травница","xz":Vector2(3920,4300)},
	"courier":{"name":"Дорожный смотритель","xz":Vector2(3850,4230)},
	"woodcutter":{"name":"Сломанная рукоять","xz":Vector2(3710,4080)},
	"town":{"name":"Арденхольм","xz":Vector2(3510,3698)},
	"forest_helper":{"name":"Ученик травницы","xz":Vector2(4110,3890)},
	"forest":{"name":"Лес Эйвар","xz":Vector2(4562,3740)},
	"road_warden":{"name":"Лесник у перепутья","xz":Vector2(4040,4070)},
	"cartwright":{"name":"Сломанная ось","xz":Vector2(3595,4200)},
	"mine_traveler":{"name":"Шахтёр на привале","xz":Vector2(3190,4260)},
	"mine":{"name":"Старая штольня","xz":Vector2(2771,4354)}
}

var world
var navigation
var camera_rig
var hud
var brother
var sister
var active
var caravan
var sound
var saves = SaveStore.new()
var state:Dictionary = Campaign.new_state()
var orders:Dictionary = {"brother":[],"sister":[]}
var enemies:Dictionary = {}
var in_combat := false
var attack_timer := 0.0
var retreat_until := 0.0
var pulse := 0.0
var follower_tick := 0.0
var realtime_tick := 0.0
var slot_cache:Array[Dictionary] = []
var movement_mark:MeshInstance3D
var mark_left := 0.0
var dialogue_queue:Array[Dictionary] = []
var current_dialogue:Dictionary = {}
var recent_region := ""
var hover_label:Label3D
var object_labels:Dictionary = {}
var hover_tick := 0.0
var loading_state := false
var saved_status := ""
var farm
var industry
var settlement
var initial_farm:Dictionary={}
var initial_industry:Dictionary={}
var initial_settlement:Dictionary={}
var build_kind:=""
var build_rotation:=0.0
var build_ghost:MeshInstance3D
var build_point:=Vector3.ZERO
var build_valid:=false
var work_tick:=0.0
var city
var life
var extra_actors:Dictionary={}
var ranch
var initial_ranch:Dictionary={}
var v5
var build_move_id:=""

func _ready() -> void:
	get_tree().auto_accept_quit=false
	DisplayServer.window_set_title("Noctis Live — Йедамар · V5")
	world = World.new()
	add_child(world)
	_add_sidequests()
	farm=Farm.new()
	farm.configure(world)
	add_child(farm)
	industry=Industry.new()
	industry.configure(world)
	add_child(industry)
	city=City.new()
	city.configure(world)
	add_child(city)
	CityDressing.new().configure(city,world)
	SceneBatcher.bake(city,city._roofs+city._full_walls)
	navigation = Navigation.new()
	var base_obstacles:Array=world.obstacles.filter(func(o):return not o.has("industry_id") and not o.has("farm_id") and not o.has("settlement_id"))
	navigation.configure(Callable(world,"sample_height"),world.bounds,base_obstacles)
	brother = _actor("brother","Брат",_ground(FARM_START))
	sister = _actor("sister","Сестра",_ground(FARM_START+Vector2(2.5,2)))
	sister.max_health = 80
	sister.health = 80
	active = brother
	brother.selected = true
	camera_rig = CameraRig.new()
	add_child(camera_rig)
	camera_rig.focus_on(brother)
	caravan = Caravan.new()
	caravan.configure(world,navigation,brother,sister)
	add_child(caravan)
	settlement=Settlement.new()
	settlement.configure(self)
	add_child(settlement)
	industry.navigation_changed.connect(_sync_navigation)
	_sync_navigation()
	initial_farm=farm.snapshot()
	initial_industry=industry.snapshot()
	initial_settlement=settlement.snapshot()
	hud = HUD.new()
	add_child(hud)
	hud.action_requested.connect(_on_action)
	hud.character_requested.connect(_select_character)
	hud.craft_requested.connect(_craft)
	hud.item_requested.connect(_use_item)
	hud.save_requested.connect(_pause)
	hud.load_requested.connect(_pause)
	hud.map_requested.connect(_show_map)
	hud.dialogue_next.connect(_next_dialogue)
	hud.pause_requested.connect(_pause)
	hud.resume_requested.connect(_resume)
	hud.quit_requested.connect(_quit_game)
	hud.queue_cancel_requested.connect(_cancel_order)
	hud.queue_clear_requested.connect(_clear_orders)
	hud.hotbar_requested.connect(_hotbar)
	hud.hotbar_assign_requested.connect(_assign_hotbar)
	hud.transfer_requested.connect(_transfer)
	hud.slot_save_requested.connect(_save_slot)
	hud.slot_load_requested.connect(_load_slot)
	hud.travel_requested.connect(_travel_site)
	hud.work_requested.connect(_work_requested)
	hud.new_plots_toggled.connect(_allow_new_plots)
	hud.follow_toggled.connect(_follow_toggle)
	hud.build_requested.connect(_begin_build)
	hud.map_visibility_changed.connect(_map_visibility)
	hud.bind_map_world(get_world_3d(),world.bounds)
	caravan.notice.connect(func(text:String):hud.toast(text))
	caravan.arrived.connect(_caravan_arrived)
	brother.movement_failed.connect(_movement_failed.bind("brother"))
	sister.movement_failed.connect(_movement_failed.bind("sister"))
	_spawn_enemies()
	_make_marker()
	_make_hover_labels()
	sound = Sound.new()
	add_child(sound)
	life=LifeBridge.new()
	life.configure(self,city)
	add_child(life)
	ranch=Ranch.new()
	ranch.configure(self)
	add_child(ranch)
	ranch.notice.connect(func(message:String):hud.toast(message))
	ranch.mounted_changed.connect(_mounted_changed)
	initial_ranch=ranch.snapshot()
	v5=V5Bridge.new()
	add_child(v5)
	v5.configure(self)
	slot_cache = saves.list_slots()
	if not saves.read_slot("realtime").is_empty():
		_load_slot("realtime")
	elif FileAccess.file_exists("user://liora_save.json"):
		var old = JSON.parse_string(FileAccess.get_file_as_string("user://liora_save.json"))
		if old is Dictionary and int(old.get("version",0)) == 1:
			var migrated:=_migrate(old)
			if _valid(migrated):
				_restore(migrated)
				hud.toast("Прогресс первой версии перенесён. Общий рюкзак передан брату.")
	if current_dialogue.is_empty() and not state.flags.get("intro_v2",false):
		state.flags.intro_v2 = true
		_say("Сестра","Пойдём к Марте. А потом заглянем к травнице по дороге. Теперь у каждого свой рюкзак — не забудь передать мне немного воды.")
	if not state.flags.get("intro_v3",false):
		state.flags.intro_v3=true
		_say("Марта","У меня есть семена и работа в саду — подойдите поговорить. G открывает рабочий день, K — навыки, B — строительство. Ночью держитесь стражи и не забывайте спать.")
	if not state.flags.get("intro_v4",false):
		state.flags.intro_v4=true
		_say("Марта","За садом вас ждёт временный приют: кровати, кухня, купальная бочка и кладовая. L открывает жизнь семьи, работу, рынок и жильё. В Арденхольме нужны работники. Домочадцы могут заботиться о себе, пока вы путешествуете.")
	if not state.flags.get("intro_v5",false):
		state.flags.intro_v5=true
		_say("Марта","Свою землю получают с разрешения ратуши. Начните с работы и поручений: в книге жизни L есть «Статус», домашние дела и занятия. А в моём саду можно работать и ставить хозяйственные постройки после нашего разговора.")
	_update_ui()

func _actor(role:String,title:String,at:Vector3):
	var actor = Actor.new()
	actor.configure(role,title,Callable(world,"sample_height"),navigation)
	add_child(actor)
	actor.position = at
	return actor

func _ground(xz:Vector2)->Vector3:
	return Vector3(xz.x,world.sample_height(xz.x,xz.y),xz.y)

func _hero(role:String):
	if role=="sister": return sister
	if role=="brother": return brother
	return extra_actors.get(role,brother)

func _roles()->Array:
	return state.characters.keys()

func _role_in_combat(role:String)->bool:
	return in_combat and (role=="brother" or _flat_distance(_hero(role).position,brother.position)<55)

func _caravan_busy(role:String)->bool:
	return caravan.is_controlled(role) or (caravan.mode=="boarding" and role in ["brother","sister"])

func _ranch_busy(role:String)->bool:
	return ranch!=null and ranch.is_mounted(role)

func _mounted_changed(role:String,mounted:bool)->void:
	if not state.characters.has(role): return
	if mounted:
		if life: life.cancel(role)
		state.characters[role].sleeping=false
	else:
		for order in orders.get(role,[]): order.phase="waiting"
	if not loading_state: _update_ui()

func _garden_expansion_allowed()->bool:
	if not state.flags.get("garden_quest",false): return false
	for role in _roles():
		if state.characters[role].get("allow_new_plots",false): return true
	return false

func _inventory(role:String)->Dictionary:
	return state.characters[role].inventory

func _all_inventories()->Dictionary:
	var result:Dictionary={}
	for role in _roles(): result[role]=_inventory(role)
	return result

func _add_sidequests()->void:
	for info in [
		["courier","Дорожный смотритель",Vector2(3850,4230),"Ждёт посылку с фермы. Помощь ему приблизит семью к городу."],
		["woodcutter","Лесоруб Ивар",Vector2(3710,4080),"Сломал рукоять инструмента. Ему пригодятся три прочные ветки."],
		["forest_helper","Ученик травницы",Vector2(4110,3890),"Собирает травы на дороге к Эйвару. Просит принести два пучка лечебных листьев."],
		["road_warden","Лесник у перепутья",Vector2(4040,4070),"Ждёт вестей о мародёрах. Здесь можно получить припасы перед дорогой к штольне."],
		["cartwright","Тележник Эрик",Vector2(3595,4200),"Чинит ось возле дороги. Два полена помогут ему закончить работу."],
		["mine_traveler","Шахтёр на привале",Vector2(3190,4260),"Делает передышку по пути к штольне. У него закончилась дорожная еда."]
	]:
		world.spawn_interactable(info[0],"npc",info[1],_ground(info[2]),info[3])
	for i in range(2):
		world.spawn_interactable("cartwright_branch_"+str(i),"branch","Сухая ветка",_ground(Vector2(3601+i*3,4206)),"Рядом с привалом. Подойдёт для инструмента и даст немного древесины.")

func _unhandled_input(event:InputEvent)->void:
	if hud.is_modal_open():
		return
	if not build_kind.is_empty():
		if event is InputEventKey and event.pressed and event.physical_keycode==KEY_R:
			build_rotation+=PI/2
			return
		if event is InputEventMouseButton and event.pressed:
			if event.button_index==MOUSE_BUTTON_RIGHT:
				_cancel_build()
				return
			if event.button_index==MOUSE_BUTTON_LEFT:
				_place_build_order()
				return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cam:Camera3D = camera_rig.camera
		var start := cam.project_ray_origin(event.position)
		var query := PhysicsRayQueryParameters3D.create(start,start+cam.project_ray_normal(event.position)*10000,3)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			hud.hide_context()
			return
		var collider:Node = hit.collider
		var id := ""
		while collider:
			if collider.has_meta("object_id"):
				id = str(collider.get_meta("object_id"))
				break
			collider = collider.get_parent()
		if world.objects.has(id):
			_context(id,event.position)
		else:
			hud.hide_context()
			_order_move(hit.position)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_TAB: _select_character(str(_roles()[(_roles().find(active.role)+1)%_roles().size()]))
			KEY_F5: _save_slot("manual_1")
			KEY_F9: _pause()

func _context(id:String,at:Vector2)->void:
	var obj:Dictionary = world.objects[id]
	var actions:Array[Dictionary] = [_action("inspect","Изучить",true,"")]
	var kind := str(obj.type)
	var free := not _role_in_combat(str(active.role))
	var inv := _inventory(active.role)
	var person:=_person(active.role)
	if life: actions.append_array(life.context_actions(id,active.role))
	if ranch and ranch.owns(id): actions.append_array(ranch.actions(id,person))
	if farm.owns(id): actions.append_array(farm.actions(id,person))
	if industry.owns(id): actions.append_array(industry.actions(id,person))
	if kind=="bed": actions.append(_action("sleep","Спать до утра / вздремнуть",free,"Сначала завершите бой"))
	if kind=="companion":
		var companion:Dictionary=settlement.companions[id]
		if not companion.recruited: actions.append(_action("recruit","Пригласить в отряд",free,"Сейчас идёт бой"))
		else:
			for option in [["assign_guard","Охранять место"],["assign_garden","Работать в саду"],["assign_follow","Сопровождать"],["dismiss","Отпустить"]]: actions.append(_action(option[0],option[1],true,""))
	if kind=="zombie": actions.append(_action("attack_zombie","Атаковать мертвеца",active==brother,"Сестра не сражается"))
	if kind=="storage": actions.append(_action("store_all","Сложить материалы",true,"")); actions.append(_action("take_all","Забрать припасы",true,""))
	if kind in ["branch","stone","herb","berry","wood","mint","lavender","hay","carrot"]:
		actions.append(_action("gather","Собрать",free,"Сейчас идёт бой"))
	elif kind == "ore":
		var tool:bool = int(inv.get("pickaxe",0))>0
		actions.append(_action("mine","Добыть руду",free and tool,"Нужна кирка в рюкзаке выбранного героя" if not tool else "Сейчас идёт бой"))
	elif kind == "npc":
		actions.append(_action("talk","Поговорить",free,"Сейчас идёт бой"))
	elif kind == "well":
		actions.append(_action("drink","Попить",free,"Сейчас идёт бой"))
		actions.append(_action("fill","Набрать воду",free,"Сейчас идёт бой"))
	elif kind == "campfire":
		actions.append(_action("rest","Отдохнуть",free,"Сейчас идёт бой"))
		actions.append(_action("cook","Готовить",free,"Сейчас идёт бой"))
	elif kind == "cauldron":
		var taught:bool = state.flags.get("alchemy_learned",false)
		actions.append(_action("brew","Зельеварение",free and taught,"Сначала попросите травницу научить вас" if not taught else "Сейчас идёт бой"))
	elif kind in ["bush","barrel"]:
		actions.append(_action("hide","Спрятаться",active == sister and free,"Укрытие для сестры"))
	elif kind == "crate":
		actions.append(_action("search","Осмотреть припасы",free,"Сейчас идёт бой"))
	elif kind == "enemy":
		actions.append(_action("attack","Атаковать",active == brother,"Сестра не сражается"))
	elif kind == "cart":
		actions.append(_action("cart_storage","Открыть склад",true,""))
		actions.append(_action("pull_cart","Взять телегу",free,"Сейчас идёт бой"))
		actions.append(_action("ride_cart","Сесть и ехать",free,"Сейчас идёт бой"))
		actions.append(_action("disembark","Остановиться и выйти",true,""))
	elif kind == "animal":
		actions.append(_action("feed","Накормить",free,"Сейчас идёт бой"))
		actions.append(_action("water_animal","Напоить",free and int(inv.get("water",0))>0,"Нужна вода в рюкзаке"))
	hud.show_context(at,id,str(obj.name),actions)

func _action(id:String,label:String,enabled:bool,reason:String)->Dictionary:
	return {"id":id,"label":label,"enabled":enabled,"reason":reason}

func _on_action(action:String,id:String)->void:
	if action=="ranch_unmount" and ranch and ranch.is_mounted(str(active.role)):
		var result:Dictionary=ranch.complete(action,id,_person(str(active.role)))
		hud.toast(str(result.get("message","")))
		_update_ui()
		return
	if action.begins_with("life:") and life:
		life.request_context(action.trim_prefix("life:"),id)
		return
	if action.begins_with("craft:"):
		_craft(action.trim_prefix("craft:"),id)
		return
	if action.begins_with("assign_") or action=="dismiss":
		settlement.command(action,id)
		return
	if action=="attack_zombie" and active==brother and settlement.zombies.has(id):
		settlement.focus_zombie=id
		_begin_combat()
		return
	if action == "view_site":
		if life and life.focus_site(id): return
		if SITES.has(id):
			camera_rig.focus_point(_ground(SITES[id].xz))
		return
	if action == "cart_take":
		_take_cart(id)
		return
	if action == "focus_selected":
		camera_rig.focus_on(active)
		return
	if not world.objects.has(id):
		return
	if action == "inspect":
		_say(world.objects[id].name,world.objects[id].description)
		if id in ["waypost_1","waypost_2","forest_waypost","mine_waypost"]:
			state.flags["read_"+id] = true
		return
	if action == "cart_storage":
		hud.show_cart_storage()
		return
	if action == "disembark":
		caravan.stop()
		caravan.disembark()
		return
	if action == "pull_cart":
		if not in_combat:
			_prepare_trip()
			caravan.pull_by_brother()
		return
	if action == "ride_cart":
		_show_map()
		return
	if _role_in_combat(str(active.role)):
		hud.toast("Сначала завершите бой. Лечение доступно через хотбар.")
		return
	if caravan.is_controlled(active.role):
		hud.toast("Сначала остановите телегу и выйдите.")
		return
	if state.depleted.has(id) or state.defeated.has(id):
		hud.toast("Этот объект уже использован.")
		return
	if action == "mine" and int(_inventory(active.role).get("pickaxe",0))<1:
		hud.toast("Кирка должна быть в рюкзаке этого героя.")
		return
	if action == "attack" and active != brother:
		hud.toast("Сестра не участвует в бою.")
		return
	if action == "hide" and active != sister:
		return
	if action == "brew" and not state.flags.get("alchemy_learned",false):
		hud.toast("Сначала нужно обучение у травницы.")
		return
	_enqueue(active.role,{"action":action,"id":id,"phase":"waiting","remaining":0.0})

func _enqueue(role:String,order:Dictionary)->void:
	if orders[role].size()>=12:
		hud.toast("В очереди уже 12 действий.")
		return
	orders[role].append(order)
	_update_ui()

func _order_move(point:Vector3)->void:
	if _ranch_busy(str(active.role)):
		if not ranch.move_target(point): hud.toast("Лошадь не может пройти сюда. Выберите свободное место.")
		return
	if caravan.is_controlled(str(active.role)) and (caravan.is_travelling() or caravan.mode == "hand"):
		if caravan.mode == "hand":
			caravan.manual_target(point)
		else:
			caravan.travel_to_animal(point)
		return
	if caravan.is_controlled(active.role):
		caravan.travel_to_animal(point)
		return
	if _role_in_combat(str(active.role)):
		brother.navigate_to(point)
		retreat_until = float(state.elapsed)+10
		return
	# RTS convention: a plain ground click replaces the current queue (the hero
	# reacts immediately); Shift+click appends the move to the end of the queue.
	if not Input.is_key_pressed(KEY_SHIFT) and not orders[active.role].is_empty():
		_end_job(active.role)
		orders[active.role].clear()
		state.characters[active.role].work_mode=""
	_enqueue(active.role,{"action":"move","position":point,"phase":"waiting"})
	movement_mark.position=point+Vector3(0,.3,0)
	movement_mark.show()
	mark_left=1.5

func _cancel_order(index:int)->void:
	var queue:Array=orders[active.role]
	if index<0 or index>=queue.size():
		return
	if index==0:
		_end_job(active.role)
		active.stop_moving()
		active.play_action("idle")
	queue.remove_at(index)
	_update_ui()

func _clear_orders()->void:
	state.characters[active.role].work_mode=""
	_end_job(active.role)
	orders[active.role].clear()
	active.stop_moving()
	active.play_action("idle")
	_update_ui()

func _movement_failed(role:String)->void:
	if orders.has(role) and not orders[role].is_empty() and not _role_in_combat(role) and not _caravan_busy(role):
		if life: life.cancel(role)
		orders[role].pop_front()
		hud.toast("Не удалось подойти. Остальные действия остались в очереди.")

func _select_character(role:String)->void:
	if not state.characters.has(role):
		return
	if _role_in_combat(role) and role=="sister":
		hud.toast("Сестра прячется до конца боя.")
		return
	active=_hero(role)
	for member in _roles(): _hero(member).selected=member==role
	state.selected=role
	farm.set_new_plots_allowed(_garden_expansion_allowed())
	camera_rig.select_target(active)
	if sound: sound.effect("select")
	_update_ui()

func _process(delta:float)->void:
	if hud==null or loading_state:
		return
	state.elapsed=float(state.elapsed)+delta
	farm.tick(delta,delta)
	settlement.tick(delta)
	if ranch: ranch.tick(delta)
	_update_build_ghost()
	camera_rig.set_controls_enabled(not hud.is_modal_open())
	sound.movement(delta,active.is_moving() and not caravan.is_passenger(active.role))
	sound.set_night(caravan.is_night())
	_needs(delta)
	if life: life.tick(delta)
	if v5: v5.tick(delta)
	for role in _roles():
		if not _role_in_combat(str(role)) and not _caravan_busy(str(role)) and not _ranch_busy(str(role)):
			_run_order(role,delta)
	_combat(delta)
	follower_tick-=delta
	if follower_tick<=0:
		follower_tick=.7
		_follow()
		_location_events()
	work_tick-=delta
	if work_tick<=0:
		work_tick=2.0
		_plan_workdays()
	pulse-=delta
	if pulse<=0:
		pulse=.2
		_advance()
		_update_ui()
	hover_tick-=delta
	if hover_tick<=0:
		hover_tick=.12
		_update_hover()
	mark_left-=delta
	if mark_left<=0:
		movement_mark.hide()
	if current_dialogue.is_empty() and not dialogue_queue.is_empty():
		_display_next()
	realtime_tick+=delta/maxf(.01,Engine.time_scale)
	if realtime_tick>=10:
		realtime_tick=0
		_save_slot("realtime",false)
	state.auto_elapsed=float(state.auto_elapsed)+delta/maxf(.01,Engine.time_scale)
	if float(state.auto_elapsed)>=600:
		state.auto_elapsed=float(state.auto_elapsed)-600
		var slot:="auto_"+str(int(state.auto_index)%6)
		state.auto_index=(int(state.auto_index)+1)%6
		_save_slot(slot,false)
		hud.toast("Создана отдельная ячейка автосохранения.")

func _needs(delta:float)->void:
	for role in _roles():
		var data:Dictionary=state.characters[role]
		var actor=_hero(role)
		var sleeping:bool=data.get("sleeping",false)
		data.hunger=maxf(0,float(data.hunger)-delta*.018)
		data.thirst=maxf(0,float(data.thirst)-delta*.028)
		data.sleep=clampf(float(data.sleep)+delta*(.4 if sleeping else -.075),0,100)
		var resting:bool=caravan.is_passenger(role) or sleeping
		if caravan.is_passenger(role) and caravan.is_night(): data.sleep=minf(100,float(data.sleep)+delta*.35)
		var pulling:bool=role=="brother" and caravan.mode=="hand" and caravan.is_travelling()
		var working:bool=not orders[role].is_empty() and orders[role][0].get("phase","")=="working" and not sleeping
		var effort:bool=(actor.is_moving() and not resting) or pulling or working
		data.stamina=clampf(float(data.stamina)+delta*(1.6 if resting else (-.5 if pulling else (-.23 if effort else .65))),0,100)
		if in_combat and role=="brother": data.stamina=maxf(0,float(data.stamina)-delta*.35)
		if float(data.hunger)<=0 or float(data.thirst)<=0: actor.health=maxf(1,actor.health-delta*.05)
		if resting: actor.health=minf(actor.max_health,actor.health+delta*.08)
		actor.move_speed=6.0 if float(data.stamina)>12 and float(data.thirst)>10 and float(data.sleep)>15 else 3.0
		data.health=actor.health


func _run_order(role:String,delta:float)->void:
	var queue:Array=orders[role]
	if queue.is_empty(): return
	var order:Dictionary=queue[0]
	if str(order.action).begins_with("ranch_") and ranch:
		_run_ranch_order(role,delta)
		return
	if str(order.action).begins_with("life:") and life:
		life.run_order(role,delta)
		return
	var actor=_hero(role)
	var action:=str(order.action)
	var id:=str(order.get("id",""))
	var portable:bool=action in ["move","construct"] or (action.begins_with("craft:") and id.is_empty())
	if not portable and (not world.objects.has(id) or state.depleted.has(id) or state.defeated.has(id)):
		_end_job(role)
		queue.pop_front()
		return
	if action=="attack" and not enemies.has(id):
		queue.pop_front()
		return
	var target:Vector3=order.get("position",actor.position) if portable else world.objects[id].get("approach",world.objects[id].position)
	if action=="attack": target=enemies[id].actor.position
	var reach:=.9 if action=="move" else (14.0 if action=="attack" else REACH)
	if order.phase=="waiting":
		actor.end_work()
		actor.set_hidden_in_cover(false)
		order.phase="walking"
		if _flat_distance(actor.position,target)>reach and not actor.navigate_to(target):
			if not queue.is_empty() and is_same(queue[0],order):
				if life: life.cancel(role)
				queue.pop_front()
				hud.toast("Не удалось проложить путь. Остальные действия остались в очереди.")
			return
	if order.phase=="walking":
		if _flat_distance(actor.position,target)>reach:
			if not actor.is_moving():
				queue.pop_front()
				# A ground click on a blocked spot (wall, tree, water edge) ends at the
				# nearest reachable point: that is a successful move, not an error.
				if action!="move": hud.toast("Подход закрыт. Выберите другое место рядом.")
			return
		actor.stop_moving()
		if action=="move":
			queue.pop_front()
			return
		if action=="attack":
			queue.pop_front()
			enemies[id].aggro=true
			_begin_combat()
			return
		var person:=_person(role)
		var reason:=""
		var duration:=5.0 if action=="rest" else 1.2
		var skill:="crafting"
		if action.begins_with("craft:") or action=="chop":
			reason=industry.validate(action,id,person)
			duration=industry.duration(action,id)
			skill="woodcutting" if action=="chop" else str(Campaign.RECIPES[action.trim_prefix("craft:")].skill)
		elif action.begins_with("farm_"):
			reason=farm.validate(action,id,person)
			duration=farm.duration(action,id)
			skill="farming"
		elif action=="mine":
			reason="Кирка нужна в личном рюкзаке." if int(person.inventory.get("pickaxe",0))<1 else ""
			duration=15
			skill="mining"
		elif action=="construct":
			reason=settlement.can_place(order.kind,order.build_position,role)
			duration=settlement.BLUEPRINTS[order.kind].duration
			skill="carpentry"
		elif action=="sleep":
			if v5: reason=v5.domestic.before_use(role,id,"sleep")
			var minute:float=caravan.day_time
			duration=(1440-minute+360) if minute>=1200 else (360-minute if minute<360 else 240.0)
			if reason.is_empty() and life and not life.sim.reserve(role,id,"sleep",duration+30): reason="Эта кровать уже занята."
			if reason.is_empty() and v5 and not v5.domestic.reserve(role,id,duration+30): reason="Эту кровать обслуживает другой житель."
			if reason.is_empty():
				person.sleeping=true
				actor.position=world.objects[id].position
		if not reason.is_empty():
			if life: life.cancel(role)
			queue.pop_front()
			hud.toast(reason)
			return
		var level:int=Campaign.skill_level(person,skill)
		order.duration=duration if action=="sleep" else duration/maxf(1,1+minf(5,level)*.08)
		order.skill=skill
		if float(order.get("remaining",0))<=0: order.remaining=order.duration
		order.phase="working"
		var animation:="interact"
		if action=="sleep": animation="Lie_Idle"
		elif action in ["mine","chop"]: animation=action
		elif action=="farm_till": animation="dig"
		elif action in ["craft:plank_saw","craft:plank_mill"]: animation="saw_work"
		elif action.begins_with("craft:") and str(Campaign.RECIPES[action.trim_prefix("craft:")].station)=="anvil": animation="forge_work"
		actor.begin_work(animation)
		if action in ["mine","chop"]: sound.effect("mine")
	if order.phase=="working":
		if action=="sleep" and life:
			if not life.sim.reserve(role,id,"sleep",float(order.remaining)+30) or (v5 and not v5.domestic.reserve(role,id,float(order.remaining)+30)):
				_end_job(role); queue.pop_front(); hud.toast("Кровать недоступна. Сон прерван."); return
		if action!="sleep" and _flat_distance(actor.position,target)>reach+.25:
			actor.end_work()
			order.phase="waiting"
			return
		order.remaining=float(order.remaining)-delta
		if float(order.remaining)<=0:
			_end_job(role)
			queue.pop_front()
			var person:=_person(role)
			var result:Dictionary={}
			if action.begins_with("craft:") or action=="chop":
				result=industry.complete(action,id,person)
				if result.get("ok",false) and action.begins_with("craft:"):
					var recipe_id:=action.trim_prefix("craft:")
					state.flags["crafted_"+recipe_id]=true
					if result.get("item","") in ["sword","iron_sword"] and role=="brother":
						person.equipped=result.item
						brother.set_weapon_equipped(true)
					sound.effect("alchemy" if result.get("skill","")=="alchemy" else "craft")
			elif action.begins_with("farm_"): result=farm.complete(action,id,person)
			elif action=="construct": result=settlement.build(order.kind,order.build_position,order.rotation,person)
			elif action=="sleep": hud.toast(actor.display_name+" проснулся.")
			elif action=="recruit": settlement.command(action,id)
			elif action in ["store_all","take_all"]: _building_storage(action,id,role)
			else:
				_finish_action(action,id,role)
			if not result.is_empty():
				hud.toast(str(result.get("message","")))
				if result.get("ok",false):
					_award_xp(role,str(result.get("skill","crafting")),float(result.get("xp",0)))
					if v5:
						v5.civic.after_action(role,action,{"target_id":id},result)
						if action=="construct": v5.domestic.sync_objects()
			if action=="sleep" and v5: v5.domestic.record_use(role,id,"sleep")
			_advance()
			_update_ui()


func _run_ranch_order(role:String,delta:float)->void:
	var queue:Array=orders[role]
	var order:Dictionary=queue[0]
	var id:String=str(order.get("id",""))
	var actor=_hero(role)
	if not ranch.owns(id):
		_end_job(role)
		queue.pop_front()
		return
	var target:Vector3=world.objects[id].approach
	var distance:float=_flat_distance(actor.position,target)
	if order.phase in ["waiting","walking"]:
		if order.phase=="waiting":
			var candidate:Dictionary=_person(role).duplicate(false)
			candidate.erase("position")
			var reason:String=ranch.validate(order.action,id,candidate)
			if not reason.is_empty():
				queue.pop_front()
				hud.toast(reason)
				return
			actor.end_work()
			order.phase="walking"
			order.repath=0.0
		order.repath=float(order.get("repath",0))-delta
		if distance>REACH:
			if distance<20: ranch.hold(id,4)
			if float(order.repath)<=0:
				order.repath=2.0
				if not actor.navigate_to(target):
					if not queue.is_empty() and is_same(queue[0],order):
						queue.pop_front()
						hud.toast("Не удалось подойти к животному.")
			return
		actor.stop_moving()
		var reason:String=ranch.validate(order.action,id,_person(role))
		if not reason.is_empty():
			queue.pop_front()
			hud.toast(reason)
			return
		order.duration=ranch.duration(order.action,id)
		if float(order.get("remaining",0))<=0: order.remaining=order.duration
		order.phase="working"
		ranch.hold(id,float(order.remaining)+2)
		actor.begin_work("interact")
	if order.phase=="working":
		if distance>3.0:
			actor.end_work()
			order.phase="waiting"
			return
		order.remaining=float(order.remaining)-delta
		if float(order.remaining)<=0:
			_end_job(role)
			queue.pop_front()
			var result:Dictionary=ranch.complete(order.action,id,_person(role))
			hud.toast(str(result.get("message","")))
			if result.get("ok",false): _award_xp(role,str(result.get("skill","animal_husbandry")),float(result.get("xp",0)))
			_update_ui()


func _finish_action(action:String,id:String,role:String)->void:
	if not world.objects.has(id):
		return
	if state.depleted.has(id):
		return
	var obj:Dictionary=world.objects[id]
	var inv:=_inventory(role)
	var actor=_hero(role)
	var data:Dictionary=state.characters[role]
	match action:
		"gather":
			var item:=str(obj.type)
			_add_item(role,item,2 if item in ["branch","stone","berry","herb","mint","lavender","hay","carrot"] else 1)
			if item=="branch":
				_add_item(role,"wood",1,false)
			if item=="herb":
				state.flags.herbs_found=true
			_deplete(id)
		"mine":
			if int(inv.get("pickaxe",0))<1:
				return
			_add_item(role,"ore",3)
			state.gathered_ore=int(state.gathered_ore)+3
			data.stamina=maxf(0,float(data.stamina)-5)
			_deplete(id)
			_award_xp(role,"mining",12)
		"talk": _talk(id,role)
		"drink":
			data.thirst=100.0
			hud.toast("Жажда утолена · "+actor.display_name)
		"fill":
			inv.water=mini(20,int(inv.get("water",0))+3)
			hud.toast("Вода добавлена в личный рюкзак.")
		"rest":
			actor.health=actor.max_health
			data.stamina=100.0
			hud.toast(actor.display_name+" отдохнул у огня.")
		"cook","brew":
			if role==active.role:
				hud.show_crafting()
			else:
				hud.toast(actor.display_name+" подошёл к месту ремесла. Выберите его для крафта.")
		"hide":
			actor.set_hidden_in_cover(true)
		"search":
			_add_item(role,"ration",1)
			_add_item(role,"herb",2)
			_deplete(id)
		"feed":
			_feed(role)
		"water_animal":
			if int(inv.get("water",0))>0 and caravan.water():
				inv.water=int(inv.water)-1
				_award_xp(role,"animal_husbandry",6)
	if v5 and action in ["gather","mine"]: v5.civic.after_action(role,action,{"target_id":id},{"ok":true})
	_advance()
	_update_ui()

func _deplete(id:String)->void:
	if not state.depleted.has(id):
		state.depleted.append(id)
	if world.objects.has(id):
		world.objects[id].node.hide()
		_disable_clicks(world.objects[id].node,false)

func _disable_clicks(node:Node,enabled:bool)->void:
	if node is CollisionObject3D:
		node.collision_layer=2 if enabled else 0
	for child in node.get_children():
		_disable_clicks(child,enabled)

func _add_item(role:String,id:String,count:int,notify:bool=true)->void:
	var inv:=_inventory(role)
	inv[id]=int(inv.get(id,0))+count
	if notify:
		hud.toast("+%d %s · %s" % [count,Campaign.ITEMS.get(id,id),_hero(role).display_name])
		sound.effect("gather")

func _craft(id:String,target_id:String="")->void:
	if _role_in_combat(str(active.role)) or not Campaign.RECIPES.has(id):
		hud.toast("Сейчас это ремесло недоступно.")
		return
	if caravan.is_controlled(active.role):
		hud.toast("Сначала выйдите из телеги.")
		return
	var recipe:Dictionary=Campaign.RECIPES[id]
	var person:=_person(active.role)
	if str(recipe.station)=="cauldron" and not person.alchemy_learned:
		hud.toast("Сначала нужен урок травницы.")
		return
	if target_id.is_empty(): target_id=industry.find_station(id,active.position)
	if not str(recipe.station).is_empty() and target_id.is_empty():
		hud.toast("Сначала найдите или постройте подходящий станок.")
		return
	var order:Dictionary={"action":"craft:"+id,"id":target_id,"phase":"waiting","remaining":0.0}
	if target_id.is_empty(): order.position=active.position
	_enqueue(active.role,order)
	hud.toast("В очереди: "+str(recipe.name)+" · примерно "+str(int(recipe.duration))+" с.")


func _use_item(id:String)->void:
	var role:=str(active.role)
	var inv:=_inventory(role)
	if int(inv.get(id,0))<=0:
		hud.toast("Предмета нет в рюкзаке этого героя.")
		return
	var data:Dictionary=state.characters[role]
	if id=="iron_armor":
		data["armor_equipped"]=not bool(data.get("armor_equipped",false))
		if active.has_method("set_armor_equipped"): active.set_armor_equipped(data.armor_equipped)
		hud.toast("Доспех надет." if data.armor_equipped else "Доспех снят.")
		_update_ui()
		return
	if id in Campaign.EQUIPMENT:
		data.equipped=id
		if role=="brother":
			brother.set_weapon_equipped(id in ["sword","iron_sword"])
		hud.toast("Выбрано · "+str(Campaign.ITEMS[id]))
		_update_ui()
		return
	if id in ["hay","carrot"]:
		if _flat_distance(active.position,caravan.get_animal_position())>3.5 and not caravan.is_passenger(role):
			hud.toast("Подойдите к животному, чтобы покормить его.")
			return
		if caravan.feed(id):
			inv[id]=int(inv[id])-1
			_award_xp(role,"animal_husbandry",6)
			hud.toast("Животное накормлено.")
		_update_ui()
		return
	match id:
		"bread","meal","fish","meat","milk","egg":
			data.hunger=minf(100,float(data.hunger)+float({"bread":40,"meal":65,"fish":45,"meat":45,"milk":22,"egg":16}[id]))
		"bandage","healing_potion","remedy":
			if active.health>=active.max_health:
				hud.toast("Здоровье уже полное.")
				return
			active.health=minf(active.max_health,active.health+(65 if id=="healing_potion" else 45))
		"stamina_potion","tonic": data.stamina=minf(100,float(data.stamina)+65)
		"ration":
			data.hunger=minf(100,float(data.hunger)+45)
			active.health=minf(active.max_health,active.health+8)
		"berry":
			data.hunger=minf(100,float(data.hunger)+8)
			data.thirst=minf(100,float(data.thirst)+3)
		"apple","carrot":
			data.hunger=minf(100,float(data.hunger)+12)
			data.thirst=minf(100,float(data.thirst)+5)
		"water": data.thirst=minf(100,float(data.thirst)+45)
		_:
			hud.toast("Материал для ремесла или поручения.")
			return
	inv[id]=int(inv[id])-1
	sound.effect("gather")
	_update_ui()

func _hotbar(slot:int)->void:
	var bar:Array=state.characters[active.role].hotbar
	if slot>=0 and slot<bar.size() and not str(bar[slot]).is_empty():
		_use_item(str(bar[slot]))

func _assign_hotbar(slot:int,item:String)->void:
	if slot>=0 and slot<6 and Campaign.ITEMS.has(item):
		state.characters[active.role].hotbar[slot]=item
		_update_ui()

func _transfer(item:String,destination:String,count:int)->void:
	if destination==active.role or (not state.characters.has(destination) and destination!="cart"):
		return
	var source:=_inventory(active.role)
	var available:=int(source.get(item,0))
	var amount:=mini(available,available if count<=0 else count)
	if amount<=0:
		return
	var target:Dictionary
	if destination=="cart":
		if _flat_distance(active.position,caravan.get_cart_position())>4 and not caravan.is_passenger(active.role):
			hud.toast("Подойдите к телеге, чтобы сложить вещи.")
			return
		target=caravan.storage
	else:
		if _flat_distance(active.position,_hero(destination).position)>4:
			hud.toast("Для передачи персонажи должны стоять рядом.")
			return
		target=_inventory(destination)
	source[item]=available-amount
	target[item]=int(target.get(item,0))+amount
	if int(source[item])==0:
		if item==state.characters[active.role].equipped:
			state.characters[active.role].equipped=""
			active.set_weapon_equipped(false)
		if item=="iron_armor":
			state.characters[active.role].armor_equipped=false
			active.set_armor_equipped(false)
	hud.toast("Передано · "+str(Campaign.ITEMS.get(item,item)))
	_update_ui()

func _take_cart(item:String)->void:
	if _flat_distance(active.position,caravan.get_cart_position())>4 and not caravan.is_passenger(active.role):
		hud.toast("Подойдите к телеге.")
		return
	if int(caravan.storage.get(item,0))>0:
		caravan.storage[item]=int(caravan.storage[item])-1
		_add_item(active.role,item,1)
		_update_ui()

func _feed(role:String)->void:
	var inv:=_inventory(role)
	for item in ["hay","carrot","berry"]:
		if int(inv.get(item,0))>0 and caravan.feed(item):
			inv[item]=int(inv[item])-1
			_award_xp(role,"animal_husbandry",6)
			hud.toast("Животное накормлено.")
			return
	hud.toast("Животному нужны сено или морковь.")

func _prepare_trip()->void:
	if ranch and ranch.is_mounted() and ranch.mounted_role() in ["brother","sister"]: ranch.dismount_all()
	for role in ["brother","sister"]:
		_end_job(role)
		_hero(role).stop_moving()
		for order in orders[role]:
			order.phase="waiting"
	hud.toast("Очереди приостановлены на время поездки.")

func _travel_site(id:String)->void:
	if life and life.travel_site(id): return
	if not SITES.has(id):
		return
	if in_combat:
		hud.toast("Сначала завершите бой.")
		return
	_prepare_trip()
	if not caravan.travel_to_animal(_ground(SITES[id].xz)):
		hud.toast("Пока не удалось построить маршрут для телеги.")
	else:
		hud.toast("Собираемся у телеги · "+str(SITES[id].name))
	hud.hide_context()

func _caravan_arrived()->void:
	hud.toast("Приехали. Можно отдохнуть или выйти из телеги.")
	_update_ui()

func _follow()->void:
	if caravan.is_travelling() or caravan.is_controlled("brother") or caravan.is_controlled("sister"): return
	if in_combat:
		if not sister.hidden_in_cover and not sister.is_moving(): _hide_sister()
		return
	for role in _roles():
		var follower=_hero(role)
		if _ranch_busy(str(role)): continue
		var leader=_hero("sister" if role=="brother" else "brother")
		if not state.characters[role].follow or not orders[role].is_empty() or state.characters[role].get("sleeping",false): continue
		if follower.hidden_in_cover: continue
		var distance:=_flat_distance(follower.position,leader.position)
		if distance>7 and not follower.is_moving(): follower.navigate_to(leader.position+(follower.position-leader.position).normalized()*3)
		elif distance<3: follower.stop_moving()


func _nearest_type(kind:String,from:Vector3,limit:float)->String:
	var found:=""
	var best:=limit
	for id in world.objects:
		var obj:Dictionary=world.objects[id]
		if obj.type!=kind or state.depleted.has(id):
			continue
		var d:=_flat_distance(from,obj.position)
		if d<best:
			found=id
			best=d
	return found

func _hide_sister()->void:
	if _flat_distance(sister.position,brother.position)>55: return
	var cover:=_nearest_type("bush",sister.position,75)
	var barrel:=_nearest_type("barrel",sister.position,75)
	if not barrel.is_empty() and (cover.is_empty() or _flat_distance(sister.position,world.objects[barrel].position)<_flat_distance(sister.position,world.objects[cover].position)):
		cover=barrel
	if cover.is_empty():
		sister.navigate_to(brother.position+Vector3(0,0,12))
		return
	var target:Vector3=world.objects[cover].get("approach",world.objects[cover].position)
	if _flat_distance(sister.position,target)<=1.6:
		sister.stop_moving()
		sister.set_hidden_in_cover(true)
	else:
		sister.navigate_to(target)

func _begin_combat()->void:
	if in_combat:
		return
	if ranch and ranch.is_mounted() and _flat_distance(_hero(ranch.mounted_role()).position,brother.position)<55: ranch.dismount_all()
	caravan.stop()
	caravan.disembark()
	in_combat=true
	for role in _roles():
		if not _role_in_combat(str(role)): continue
		_end_job(role)
		_hero(role).stop_moving()
		for order in orders[role]:
			order.phase="waiting"
	if _role_in_combat(str(active.role)):
		active=brother
		state.selected="brother"
		for role in _roles(): _hero(role).selected=role=="brother"
	sister.set_hidden_in_cover(false)
	_hide_sister()
	_say("Сестра","Я спрячусь рядом. Осторожнее!")
	hud.toast("Автобой. Клик по земле — отступить. Очереди продолжатся после боя.")

func _combat(delta:float)->void:
	var living:Array[String]=[]
	for id in enemies:
		if state.defeated.has(id):
			continue
		var enemy:Dictionary=enemies[id]
		var actor=enemy.actor
		var distance:=_flat_distance(actor.position,brother.position)
		if distance<(16 if id=="boss" else 12):
			enemy.aggro=true
		if enemy.aggro:
			if _flat_distance(actor.position,enemy.home)>65 or distance>80:
				enemy.aggro=false
				actor.navigate_to(enemy.home)
				continue
			living.append(id)
	if not living.is_empty():
		_begin_combat()
	elif in_combat and not settlement.hero_threat():
		in_combat=false
		brother.stop_moving()
		sister.set_hidden_in_cover(false)
		attack_timer=0
		return
	if not in_combat:
		return
	if brother.health<=0:
		_defeat()
		return
	attack_timer-=delta
	var closest:=""
	var near:=INF
	for id in living:
		var enemy:Dictionary=enemies[id]
		var actor=enemy.actor
		var distance:=_flat_distance(actor.position,brother.position)
		if distance<near:
			near=distance
			closest=id
		enemy.cooldown=float(enemy.cooldown)-delta
		if float(enemy.telegraph)>0:
			enemy.telegraph=float(enemy.telegraph)-delta
			actor.stop_moving()
			if float(enemy.telegraph)<=0 and distance<5:
				brother.health-=18*(.6 if state.characters.brother.get("armor_equipped",false) and int(_inventory("brother").get("iron_armor",0))>0 else 1.0)*(v5.activities.damage_multiplier("brother") if v5 else 1.0)
				actor.play_action("attack")
				hud.toast("Тяжёлый удар! −18 здоровья.")
		elif distance>2.6:
			if not actor.is_moving() or float(enemy.cooldown)<=0:
				actor.navigate_to(brother.position)
				enemy.cooldown=.6
		elif float(enemy.cooldown)<=0:
			actor.stop_moving()
			enemy.hits=int(enemy.hits)+1
			if id=="boss" and int(enemy.hits)%3==0:
				enemy.telegraph=2.2
				hud.toast("Страж готовит тяжёлый удар!")
			else:
				actor.play_action("attack")
				brother.health-=float(enemy.damage)*(.6 if state.characters.brother.get("armor_equipped",false) and int(_inventory("brother").get("iron_armor",0))>0 else 1.0)*(v5.activities.damage_multiplier("brother") if v5 else 1.0)
				sound.effect("hit")
			enemy.cooldown=2.4
	if closest.is_empty() or float(state.elapsed)<retreat_until:
		return
	var target=enemies[closest].actor
	var bow_ready:bool=state.characters.brother.equipped=="bow" and int(_inventory("brother").get("bow",0))>0 and int(_inventory("brother").get("arrow",0))>0
	if near>(26.0 if bow_ready else 3.1):
		if not brother.is_moving() or attack_timer<=-.8:
			brother.navigate_to(target.position)
			attack_timer=0
	else:
		brother.stop_moving()
		if attack_timer<=0:
			attack_timer=1.1 if float(state.characters.brother.stamina)>10 else 1.8
			brother.play_action("2H_Ranged_Shoot" if bow_ready else "attack")
			var weapon:String=str(state.characters.brother.equipped)
			var equipped:bool=weapon in ["sword","iron_sword"] and int(_inventory("brother").get(weapon,0))>0
			if bow_ready:
				target.health-=18
				_inventory("brother").arrow=int(_inventory("brother").arrow)-1
				settlement._projectile(brother.position+Vector3.UP*1.4,target.position+Vector3.UP)
			else: target.health-=(30 if weapon=="iron_sword" else 20) if equipped else 9
			state.characters.brother.stamina=maxf(0,float(state.characters.brother.stamina)-1.4)
			sound.effect("hit")
			if target.health<=0:
				_enemy_defeated(closest)

func _enemy_defeated(id:String)->void:
	var actor=enemies[id].actor
	actor.health=0
	actor.stop_moving()
	actor.play_action("death")
	state.defeated.append(id)
	enemies[id].aggro=false
	_disable_clicks(actor,false)
	_add_item("brother","herb",2,false)
	if id=="boss":
		state.flags.boss_defeated=true
		_add_item("brother","ration",2,false)
		_say("Сестра","Он больше не двигается. Давай вернёмся на ферму.")
	hud.toast("Противник побеждён.")
	_advance()

func _defeat()->void:
	var affected:Array=[]
	for role in _roles():
		if role=="brother" or _flat_distance(_hero(role).position,brother.position)<55: affected.append(role)
	in_combat=false
	caravan.stop()
	caravan.disembark()
	for role in affected:
		_end_job(role)
		orders[role].clear()
		_hero(role).stop_moving()
		_hero(role).position=_ground(FARM_START+Vector2(3,2) if role=="sister" else FARM_START)
		_hero(role).health=_hero(role).max_health
	sister.set_hidden_in_cover(false)
	for id in enemies:
		if not state.defeated.has(id):
			var enemy:Dictionary=enemies[id]
			enemy.aggro=false
			enemy.actor.stop_moving()
			enemy.actor.position=enemy.home
			enemy.actor.health=enemy.actor.max_health
			enemy.cooldown=2
			enemy.telegraph=0
	camera_rig.focus_on(brother)
	_say("Марта","Вас привели на ферму. Отдохните. Перед возвращением запаситесь повязками.")

func _talk(id:String,role:String)->void:
	if id=="farmer" and v5:
		v5.civic.grant_build_license(role,"marta_farm",_ground(Vector2(4020,4420)),Vector2(100,100),settlement.BLUEPRINTS.keys(),"Разрешение Марты на хозяйственные постройки у фермы")
	var inv:=_inventory(role)
	if id=="farmer" and not state.flags.get("garden_quest",false):
		state.flags.garden_quest=true
		_add_item(role,"seeds_carrot",8)
		_add_item(role,"seeds_herb",4)
		_add_item(role,"apple_sapling",1)
		_say("Марта","У южных полей четыре грядки и яблони. Сделайте мотыгу. Можно ухаживать за садом одним обходом или весь день через G. Урожай складывайте в садовый ящик.")
		_say("Марта","Ещё прошу разбить три грядки на отмеченных местах. Включите звёздочку в плане работ только если берётесь за расширение. Без неё работник сохранит размеры огорода.")
	match id:
		"farmer":
			if state.flags.get("boss_defeated",false) and int(state.gathered_ore)>=3:
				if not state.flags.get("completed",false):
					state.flags.completed=true
					_add_item(role,"ration",4)
					_add_item(role,"bandage",2)
					_say("Марта","Вы вернулись! Штольня снова открыта. Забирайте припасы и отдыхайте у огня.")
					_say("Сестра","А следующее путешествие будет ещё дальше?")
			elif not state.flags.get("farmer",false):
				state.flags.farmer=true
				_add_item(role,"parcel",1)
				_say("Марта","Сначала сделайте кирку из трёх камней и двух веток. Рядом с дорогой живёт травница — загляните к ней, а потом отнесите эту посылку смотрителю.")
				_say("Марта","Лошадь и небольшая телега готовы. Сено и морковь рядом с полем. В телегу складывайте тяжёлую поклажу, а сами сможете отдохнуть в дороге.")
			else:
				_say("Марта","Проверьте воду и корм. Дальше по дороге вас ждут люди, которым тоже нужна помощь.")
		"herbalist":
			if not state.flags.get("alchemy_learned",false):
				state.flags.alchemy_learned=true
				_add_item(role,"herb",2)
				_add_item(role,"mint",1)
				_add_item(role,"water",1)
				_say("Травница","Для лечебного зелья нужны два пучка лечебной травы, мята и вода. Подойди к котелку — на ходу такое не сваришь.")
				_say("Травница","Лаванда с ягодами и водой восстанавливает силы. Я показала вам обоим рецепты. Ингредиенты должны быть в рюкзаке того, кто варит.")
			else:
				_say("Травница","Котелок готов. Лечебные листья с мятой лечат раны, лаванда с ягодами возвращает бодрость.")
		"courier":
			if not state.flags.get("delivery",false) and int(inv.get("parcel",0))>0:
				inv.parcel=int(inv.parcel)-1
				state.flags.delivery=true
				_add_item(role,"carrot",4)
				_add_item(role,"water",2)
				_say("Смотритель","Посылка от Марты! Спасибо. Морковь для вашей лошади. Дальше Ивар чинит инструмент — загляните к нему по пути в город.")
			else:
				_say("Смотритель","Жду посылку с фермы. Если она у другого героя, поговорите со мной им или передайте её.")
		"woodcutter":
			if not state.flags.get("woodcutter_helped",false) and int(inv.get("branch",0))>=3:
				inv.branch=int(inv.branch)-3
				state.flags.woodcutter_helped=true
				_add_item(role,"bandage",2)
				_say("Ивар","Три крепкие ветки — хватит для новой рукояти. Берите повязки. Стражник Ролан ждёт у площади Арденхольма.")
			else:
				_say("Ивар","Нужны три ветки для рукояти. Взамен дам повязки и покажу дорогу к городу.")
		"guard":
			state.flags.guard=true
			_say("Ролан","За восточным поворотом встретите ученика травницы. Помогите ему с листьями, потом идите к поляне Эйвара. Осторожно, у опушки мародёры.")
		"forest_helper":
			if not state.flags.get("student_helped",false) and int(inv.get("herb",0))>=2:
				inv.herb=int(inv.herb)-2
				state.flags.student_helped=true
				_add_item(role,"lavender",3)
				_add_item(role,"water",2)
				_say("Ученик","Спасибо! Здесь лаванда для бодрости. Поляна совсем дальше по тропе. К лесным чужакам лучше идти с оружием.")
			else:
				_say("Ученик","Принесите два пучка лечебных листьев. Они растут возле тропы. Потом покажу путь на поляну.")
		"mine_traveler":
			if not state.flags.get("traveler_helped",false) and int(inv.get("ration",0))>0:
				inv.ration=int(inv.ration)-1
				state.flags.traveler_helped=true
				_add_item(role,"bandage",1)
				_say("Шахтёр","За паёк спасибо. Борен впереди, у штольни. Руду добывайте снаружи, а к Стражу подходите осторожно.")
			else:
				_say("Шахтёр","Выручите дорожной едой? Подскажу, где остановиться перед выработкой.")
		"road_warden":
			if state.flags.get("road_report",false):
				_say("Лесник","Эрик чинит ось у западной дороги. Потом встретите шахтёра на привале.")
			elif state.defeated.has("forest_1") and state.defeated.has("forest_2"):
				state.flags.road_report=true
				_add_item(role,"ration",2)
				_add_item(role,"water",2)
				_say("Лесник","Значит, поляна свободна. Спасибо! Припасы для вас. Идите по западной дороге: тележнику Эрику нужна древесина для ремонта.")
			else:
				_say("Лесник","На поляне Эйвара появились мародёры. Узнайте, безопасно ли там, и возвращайтесь за припасами.")
		"cartwright":
			if state.flags.get("cartwright_helped",false):
				_say("Эрик","Ось держится. Следующая остановка — шахтёр на привале, дальше на запад.")
			elif int(inv.get("wood",0))>=2:
				inv.wood=int(inv.wood)-2
				state.flags.cartwright_helped=true
				_add_item(role,"hay",3)
				_add_item(role,"bandage",1)
				_say("Эрик","Эти два полена выручат. Возьмите сено и повязку. На следующем привале шахтёр просил поделиться едой.")
			else:
				_say("Эрик","Поможете с двумя поленьями? Подбирая ветки, вы найдёте и древесину. До шахтёрского привала уже недалеко.")
		"miner":
			state.flags.miner=true
			_say("Борен","Руда рядом со входом. Три куска хватит Марте. Страж наносит тяжёлый удар после замаха — отведите брата в сторону.")
		_:
			_say(world.objects[id].name,"Доброго пути. Держитесь дороги и берегите припасы.")
	_advance()

func _objective()->String:
	var f:Dictionary=state.flags
	if f.get("completed",false): return "Первое путешествие завершено. Можно исследовать Лиору и заниматься ремеслом."
	if not f.get("farmer",false): return "Поговорите с Мартой возле колодца."
	if not f.get("crafted_stone_pickaxe",false): return "Соберите 3 камня и 2 ветки у фермы. Сделайте кирку в личном рюкзаке."
	if not f.get("alchemy_learned",false): return "Загляните к травнице возле дороги — примерно 130 м от фермы."
	if not f.get("crafted_healing_potion",false): return "Подойдите к котелку и сварите лечебное зелье из выданных трав."
	if not f.get("delivery",false): return "Отнесите посылку Марты дорожному смотрителю. Следующая остановка — около 100 м."
	if not f.get("woodcutter_helped",false): return "Помогите лесорубу дальше по дороге. Ему нужны 3 ветки."
	if not f.get("guard",false): return "Доберитесь до площади Арденхольма и поговорите со стражником. Можно ехать в телеге."
	if not f.get("student_helped",false): return "По дороге в Эйвар отдайте ученику травницы 2 лечебные травы."
	if not (state.defeated.has("forest_1") and state.defeated.has("forest_2")): return "Продолжайте к Эйвару и разберитесь с мародёрами у поляны."
	if not f.get("road_report",false): return "Расскажите леснику у перепутья, что поляна Эйвара освобождена. Он даст припасы в дорогу."
	if not f.get("cartwright_helped",false): return "По западной дороге помогите Эрику починить телегу: нужны 2 полена."
	if not f.get("traveler_helped",false): return "На пути к штольне поделитесь пайком с шахтёром на привале."
	if not f.get("miner",false) or int(state.gathered_ore)<3: return "Поговорите с Бореном у штольни. Добудьте 3 куска руды с киркой."
	if not f.get("boss_defeated",false): return "Победите Стража выработки. Подготовьте оружие и лечебные зелья."
	return "Вернитесь к Марте с вестями о штольне."

func _advance()->void:
	var f:Dictionary=state.flags
	if f.get("garden_quest",false) and not f.get("garden_extension_done",false):
		var created:=0
		for plot in farm.plots.values():
			if plot.get("quest_required",false) and plot.get("created",false): created+=1
		if created>=3:
			f.garden_extension_done=true
			_add_item(active.role,"seeds_carrot",6)
			_say("Марта","Три новые грядки готовы. Спасибо! Ещё семена для следующего посева. Теперь достаточно обычного ухода.")
	var stage:=0
	if f.get("farmer",false): stage=1
	if f.get("crafted_stone_pickaxe",false): stage=2
	if f.get("guard",false): stage=3
	if state.defeated.has("forest_1") and state.defeated.has("forest_2"): stage=4
	if f.get("miner",false) and int(state.gathered_ore)>=3: stage=5
	if f.get("boss_defeated",false): stage=6
	if f.get("completed",false): stage=7
	state.stage=maxi(stage,int(state.stage))

func _location_events()->void:
	recent_region="Равнины Лиора"
	var best:=130.0
	for id in SITES:
		var d:=_flat_distance(active.position,_ground(SITES[id].xz))
		if d<best:
			best=d
			recent_region=SITES[id].name

func _say(speaker:String,text:String)->void:
	# Dialogue advances only through the HUD's explicit Next signal.
	dialogue_queue.append({"speaker":speaker,"text":text})
	if current_dialogue.is_empty():
		_display_next()

func _display_next()->void:
	if dialogue_queue.is_empty():
		return
	current_dialogue=dialogue_queue.pop_front()
	hud.show_dialogue(current_dialogue.speaker,current_dialogue.text)

func _next_dialogue()->void:
	current_dialogue={}
	if dialogue_queue.is_empty():
		hud.hide_dialogue()
	else:
		_display_next()

func _queue_label(order:Dictionary)->String:
	if str(order.action).begins_with("ranch_"): return str(Ranch.LABELS.get(order.action,"Уход"))+" · "+str(world.objects.get(order.get("id",""),{}).get("name",""))
	if str(order.action).begins_with("life:"): return str(order.get("label","Дело"))
	if order.action=="move": return "Идти"
	if order.action.begins_with("craft:"): return "Создать · "+str(Campaign.RECIPES.get(order.action.trim_prefix("craft:"),{}).get("name","Предмет"))
	if order.action=="construct": return "Построить · "+str(settlement.BLUEPRINTS[order.kind].name)
	var names:={"gather":"Собрать","mine":"Добыть","talk":"Поговорить","rest":"Отдохнуть","sleep":"Спать","drink":"Попить","fill":"Набрать воду","attack":"Атаковать","hide":"Спрятаться","brew":"К котелку","cook":"К костру","feed":"Накормить","water_animal":"Напоить","search":"Осмотреть","chop":"Рубить","farm_till":"Вскопать","farm_water":"Полить","farm_tend":"Ухаживать","farm_harvest":"Собрать урожай","farm_plant_carrot":"Посадить морковь","farm_plant_herb":"Посеять травы","farm_plant_apple":"Посадить яблоню","farm_store":"Отнести урожай","farm_take_supplies":"Взять семена","farm_take_produce":"Взять продукты","recruit":"Пригласить","store_all":"Сложить вещи","take_all":"Забрать вещи"}
	return str(names.get(order.action,order.action))+" · "+str(world.objects.get(order.get("id",""),{}).get("name",""))

func _update_ui()->void:
	if hud==null: return
	var selected:Dictionary=state.characters[active.role]
	var skills:Dictionary={}
	for skill in Campaign.SKILLS:
		skills[skill]={"name":Campaign.SKILLS[skill],"level":Campaign.skill_level(selected,skill),"xp":float(selected.skills.get(skill,0))}
	var map_characters:Array[Dictionary]=[]
	for role in _roles():
		map_characters.append({"id":role,"name":_hero(role).display_name,"position":_hero(role).position,"selected":active.role==role})
	for id in settlement.companions:
		var c:Dictionary=settlement.companions[id]
		if c.recruited: map_characters.append({"id":id,"name":c.name,"position":c.actor.position,"selected":false})
	var queue:Array[Dictionary]=[]
	for order in orders[active.role]:
		var progress:=0.0
		if order.get("phase","")=="working":
			progress=1-float(order.get("remaining",0))/maxf(.1,float(order.get("duration",1)))
		queue.append({"label":_queue_label(order),"id":order.get("id",""),"progress":progress,"status":"Пауза" if _role_in_combat(str(active.role)) or _caravan_busy(str(active.role)) or _ranch_busy(str(active.role)) else str(order.get("phase","waiting"))})
	var animal:Dictionary=caravan.animal_stats.duplicate(true)
	animal["name"]=animal.get("name","Лошадь")
	animal["food_description"]="Сено, морковь, ягоды"
	if _ranch_busy(str(active.role)):
		var mount:Dictionary=ranch.animals[ranch.mount_id()]
		animal={"name":mount.name,"health":mount.health,"stamina":mount.stamina,"hunger":mount.food,"thirst":mount.water,"status":mount.status,"food_description":"Сено, морковь, яблоки"}
	var journal:="ДОРОГА ЧЕРЕЗ ЛИОРУ\n\n"+_objective()+"\n\nПоручения по дороге\nФерма → травница → смотритель → лесоруб → Арденхольм → ученик травницы → Эйвар → лесник → тележник → шахтёр на привале → штольня.\n\nКликайте по предметам, чтобы добавлять действия в очередь выбранного героя. Переключение сохраняет команды. В рюкзаке можно передавать вещи, назначать хотбар и складывать груз в телегу.\n\nКарта позволяет выбрать остановку и отправиться туда автоматически. Семья подойдёт к телеге и сядет в неё. На месте можно выйти через меню телеги.\n\nESC — пауза и ячейки сохранения. Alt — подписи предметов. WASD — свободная камера, пробел — привязать к герою."
	hud.update_state({"selected":active.role,"inventory":selected.inventory.duplicate(true),"selected_inventory":selected.inventory,
		"sleep":selected.sleep,"brother_sleep":state.characters.brother.sleep,"sister_sleep":state.characters.sister.sleep,
		"skills":skills,"work_mode":selected.work_mode,"allow_new_plots":selected.allow_new_plots,"follow_enabled":selected.follow,
		"map_characters":map_characters,"cart_position":caravan.get_cart_position(),"companions":settlement.ui_companions(),"build_options":settlement.build_options(selected),
			"character_inventories":_all_inventories(),
		"hotbar":selected.hotbar,"selected_item":selected.equipped,"queue":queue,
		"brother_health":brother.health,"sister_health":sister.health,"brother_stamina":state.characters.brother.stamina,"sister_stamina":state.characters.sister.stamina,
		"brother_hunger":state.characters.brother.hunger,"sister_hunger":state.characters.sister.hunger,"brother_thirst":state.characters.brother.thirst,"sister_thirst":state.characters.sister.thirst,
		"hunger":selected.hunger,"thirst":selected.thirst,"in_combat":_role_in_combat(str(active.role)),"quest":"Дорога через Лиору","objective":_objective(),
		"action_text":"Автобой · сестра прячется" if _role_in_combat(str(active.role)) else ("Верхом · очередь ждёт спешивания" if _ranch_busy(str(active.role)) else ("В пути" if _caravan_busy(str(active.role)) else "")),
		"region":recent_region,"game_time":caravan.get_clock_text(),"night":caravan.is_night(),"stage":state.stage,
		"animal":animal,"cart":{"mode":caravan.mode,"storage":caravan.storage.duplicate(true),"driver":"brother" if caravan.mode=="hand" else "animal","passengers":caravan.passengers.duplicate(),"available":true},
		"save_slots":slot_cache,"alchemy_learned":state.flags.get("alchemy_learned",false),"near_cauldron":not _nearest_type("cauldron",active.position,2.5).is_empty(),
		"dialogue_more":not dialogue_queue.is_empty(),"journal_text":journal})
	if life: life.update_ui()

func _show_map()->void:
	var points:Array[Dictionary]=[]
	for id in SITES:
		points.append({"id":id,"name":SITES[id].name,"position":_ground(SITES[id].xz)})
	if life: points.append_array(life.map_sites())
	hud.show_map(points)

func _pause()->void:
	camera_rig.set_controls_enabled(false)
	get_tree().paused=true
	slot_cache=saves.list_slots()
	hud.show_pause(slot_cache)

func _resume()->void:
	hud.hide_pause()
	get_tree().paused=false
	camera_rig.set_controls_enabled(not hud.is_modal_open())

func _quit_game()->void:
	_save_slot("realtime",false)
	get_tree().paused=false
	get_tree().quit()

func _notification(what:int)->void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and hud!=null and not loading_state:
		_quit_game()

func _vector(v:Vector3)->Array:
	return [v.x,v.y,v.z]

func _snapshot()->Dictionary:
	var data:=state.duplicate(true)
	data.version=2
	for role in _roles():
		for key in ["position","role","alchemy_learned","wallet","stage"]: data.characters[role].erase(key)
	data["positions"]={}
	data["orders"]={}
	for role in _roles():
		data.characters[role].health=_hero(role).health
		data.positions[role]=_vector(_hero(role).position)
		data.orders[role]=[]
	for role in _roles():
		for order in orders[role]:
			var saved:Dictionary=order.duplicate(true)
			if saved.has("position"): saved.position=_vector(saved.position)
			if saved.has("build_position"): saved.build_position=_vector(saved.build_position)
			data.orders[role].append(saved)
	data["caravan"]=caravan.snapshot()
	data["farm"]=farm.snapshot()
	data["industry"]=industry.snapshot()
	data["settlement"]=settlement.snapshot()
	if life: data["life"]=life.snapshot()
	if ranch: data["ranch"]=ranch.snapshot()
	if v5: data["v5"]=v5.snapshot()
	data["enemies"]={}
	for id in enemies:
		var e:Dictionary=enemies[id]
		data.enemies[id]={"position":_vector(e.actor.position),"health":e.actor.health,"aggro":e.aggro,"cooldown":e.cooldown,"telegraph":e.telegraph,"hits":e.hits}
	data["dialogue_queue"]=dialogue_queue.duplicate(true)
	data["current_dialogue"]=current_dialogue.duplicate(true)
	return data

func _save_slot(id:String,notify:bool=true)->void:
	var error:Error=saves.write_slot(id,_snapshot())
	slot_cache=saves.list_slots()
	if notify:
		hud.toast("Сохранено в отдельную ячейку." if error==OK else "Ошибка записи сохранения.")
	if get_tree().paused:
		hud.show_pause(slot_cache)

func _load_slot(id:String)->void:
	var data:=saves.read_slot(id,Callable(self,"_valid"))
	if data.is_empty() or not _valid(data):
		hud.toast("Эта ячейка пуста или повреждена.")
		return
	_restore(data)
	_resume()
	hud.toast("Сохранение загружено.")

func _valid(data:Dictionary)->bool:
	if int(data.get("version",0))!=2 or not data.get("characters") is Dictionary:
		return false
	if not data.characters.has("brother") or not data.characters.has("sister") or data.characters.size()>12: return false
	for role in data.characters:
		var person = data.characters.get(role)
		if not role is String or not person is Dictionary or not person.get("inventory") is Dictionary or not person.get("hotbar") is Array:
			return false
		for key in ["health","stamina","hunger","thirst"]:
			if not _number(person.get(key)): return false
		for count in person.inventory.values():
			if not _number(count) or float(count)<0: return false
		if person.hotbar.size()!=6: return false
		for item in person.hotbar:
			if not item is String: return false
		if not person.get("equipped","") is String: return false
	if not data.get("flags") is Dictionary or not data.get("depleted") is Array or not data.get("defeated") is Array:
		return false
	if not data.get("positions") is Dictionary: return false
	for role in data.characters:
		if not _valid_vector(data.positions.get(role)): return false
	for key in ["elapsed","stage","gathered_ore","auto_elapsed","auto_index"]:
		if not _number(data.get(key,0)): return false
	if not data.characters.has(data.get("selected","brother")): return false
	var saved_orders=data.get("orders",{})
	if not saved_orders is Dictionary: return false
	for role in data.characters:
		var queue=saved_orders.get(role,[])
		if not queue is Array or queue.size()>12: return false
		for order in queue:
			if not order is Dictionary: return false
			var action:String=str(order.get("action",""))
			if not action.begins_with("craft:") and not action.begins_with("farm_") and not action.begins_with("life:") and not Ranch.LABELS.has(action) and action not in ["move","gather","mine","talk","drink","fill","rest","cook","brew","hide","search","feed","water_animal","attack","chop","construct","sleep","recruit","store_all","take_all"]: return false
			if action.begins_with("life:") and (not order.get("payload",{}) is Dictionary or not _valid_vector(order.get("position"))): return false
			if action.begins_with("craft:") and not Campaign.RECIPES.has(action.trim_prefix("craft:")): return false
			if action=="move" or action=="construct" or (action.begins_with("craft:") and str(order.get("id","")).is_empty()):
				if not _valid_vector(order.get("position")): return false
			elif not order.get("id") is String: return false
			if action=="construct" and (not settlement.BLUEPRINTS.has(order.get("kind","")) or not _valid_vector(order.get("build_position")) or not _number(order.get("rotation",0))): return false
			if order.action=="attack" and not enemies.has(order.id): return false
			for key in ["remaining","duration"]:
				if not _number(order.get(key,0)): return false
	var saved_enemies=data.get("enemies",{})
	if not saved_enemies is Dictionary: return false
	for enemy in saved_enemies.values():
		if not enemy is Dictionary: return false
		if not _valid_vector(enemy.get("position")): return false
		for key in ["health","cooldown","telegraph","hits"]:
			if not _number(enemy.get(key,0)): return false
	var lines=data.get("dialogue_queue",[])
	if not lines is Array or not data.get("current_dialogue",{}) is Dictionary: return false
	var all_lines:Array=lines.duplicate()
	if not data.get("current_dialogue",{}).is_empty(): all_lines.append(data.current_dialogue)
	for line in all_lines:
		if not line is Dictionary or not line.get("speaker") is String or not line.get("text") is String: return false
	if data.has("caravan"):
		var cart=data.caravan
		if not cart is Dictionary or not cart.get("storage",{}) is Dictionary or not cart.get("animal_stats",{}) is Dictionary: return false
		for key in ["position","animal_position","target"]:
			if not _valid_vector(cart.get(key)): return false
		for key in ["day_time","day_number","heading","wheel_angle"]:
			if not _number(cart.get(key,0)): return false
		for key in ["health","stamina","hunger","thirst"]:
			if not _number(cart.animal_stats.get(key,100)): return false
		for count in cart.storage.values():
			if not _number(count) or float(count)<0: return false
		if not cart.get("passengers",[]) is Array: return false
		if cart.get("mode","idle") not in ["idle","boarding","animal","hand"]: return false
	for key in ["farm","industry","settlement"]:
		if data.has(key) and not data[key] is Dictionary: return false
	if not _valid_extended(data): return false
	if data.has("life") and (not data.life is Dictionary or (life and not life.valid_snapshot(data.life))): return false
	if data.has("v5") and (not data.v5 is Dictionary or (v5 and not v5.valid_snapshot(data.v5))): return false
	if data.has("ranch") and (not data.ranch is Dictionary or (ranch and not ranch.valid_snapshot(data.ranch))): return false
	if data.has("ranch"):
		var rider:String=str(data.ranch.get("rider",""))
		if not rider.is_empty() and (not data.characters.has(rider) or data.get("caravan",{}).get("passengers",[]).has(rider)): return false
		for animal in data.ranch.get("animals",{}).values():
			if not str(animal.get("follow_role","")).is_empty() and not data.characters.has(animal.follow_role): return false
	if data.has("farm") and not farm.valid_snapshot(data.farm): return false
	for role in data.characters:
		var person:Dictionary=data.characters[role]
		if not _number(person.get("sleep",100)) or not person.get("skills",{}) is Dictionary: return false
		for xp in person.get("skills",{}).values():
			if not _number(xp) or float(xp)<0: return false
	return true

func _number(value:Variant)->bool:
	return (value is int or value is float) and is_finite(float(value))

func _valid_counts(value:Variant)->bool:
	if not value is Dictionary: return false
	for key in value:
		if not key is String or not _number(value[key]) or float(value[key])<0: return false
	return true

func _valid_extended(data:Dictionary)->bool:
	var station_ids:Dictionary={}
	if data.has("industry"):
		var module:Dictionary=data.industry
		if not module.get("objects") is Dictionary: return false
		for id in module.objects:
			var record=module.objects[id]
			if not id is String or not record is Dictionary: return false
			if not industry.TITLES.has(record.get("kind","")) or not _valid_vector(record.get("position")) or not _number(record.get("rotation",0)): return false
			if bool(record.get("placed",false)):
				if not id.begins_with("built_") or not industry.BLUEPRINTS.has(record.kind): return false
				station_ids[id]=true
			elif not initial_industry.get("objects",{}).has(id): return false
	if data.has("settlement"):
		var module:Dictionary=data.settlement
		for key in ["buildings","companions","zombies"]:
			if not module.get(key,{}) is Dictionary: return false
		for id in module.get("buildings",{}):
			var record=module.buildings[id]
			if not id is String or not record is Dictionary: return false
			if station_ids.has(id) or (not id.begins_with("built_") and id not in ["settlement_bed_0","settlement_bed_1"]): return false
			if not settlement.BLUEPRINTS.has(record.get("kind","")) or industry.BLUEPRINTS.has(record.get("kind","")): return false
			if not _valid_vector(record.get("position")) or not _number(record.get("rotation",0)) or not _number(record.get("health",100)): return false
			if not _valid_counts(record.get("storage",{})): return false
		for id in module.get("companions",{}):
			var record=module.companions[id]
			if not settlement.companions.has(id) or not record is Dictionary: return false
			if not _valid_vector(record.get("position")) or not _valid_vector(record.get("home")) or not _number(record.get("health",100)): return false
			if record.get("task","") not in ["garden","guard","follow"]: return false
			var person=record.get("person")
			if not person is Dictionary or not _valid_counts(person.get("inventory")) or not _valid_counts(person.get("skills",{})): return false
			if not _number(person.get("sleep",100)): return false
		for id in module.get("zombies",{}):
			var record=module.zombies[id]
			if not id is String or not id.begins_with("zombie_") or not record is Dictionary: return false
			if not _valid_vector(record.get("position")) or not _number(record.get("health",52)): return false
		for key in ["last_raid_day","next_build","next_zombie","hero_attack"]:
			if not _number(module.get(key,0)) or float(module.get(key,0))<0: return false
		if not module.get("focus_zombie","") is String: return false
	return true

func _valid_vector(value:Variant)->bool:
	return value is Array and value.size()==3 and _number(value[0]) and _number(value[1]) and _number(value[2])

func _decode_position(value:Array)->Vector3:
	return _ground(Vector2(clampf(float(value[0]),world.bounds.position.x+2,world.bounds.end.x-2),clampf(float(value[2]),world.bounds.position.y+2,world.bounds.end.y-2)))

func _restore(data:Dictionary)->void:
	loading_state=true
	if ranch: ranch.dismount_all()
	caravan.stop()
	caravan.disembark()
	state=data.duplicate(true)
	if life: life.ensure_actors()
	for role in _roles():
		var person:Dictionary=state.characters[role]
		var defaults:Dictionary=Campaign.character_state({},100)
		for key in defaults:
			if not person.has(key): person[key]=defaults[key]
		person.sleep=clampf(float(person.sleep),0,100)
		person.sleeping=false
		_hero(role).end_work()
	settlement.clear_buildings()
	industry.clear_placed()
	industry.restore(state.get("industry",initial_industry))
	farm.restore(state.get("farm",initial_farm))
	settlement.restore(state.get("settlement",initial_settlement))
	if life: life.restore(state.get("life",{}))
	_sync_navigation()
	state.auto_elapsed=float(state.get("auto_elapsed",0))
	state.auto_index=int(state.get("auto_index",0))
	orders={}
	for role in _roles(): orders[role]=[]
	for role in _roles():
		var actor=_hero(role)
		actor.stop_moving()
		actor.position=_decode_position(state.positions[role])
		actor.health=clampf(float(state.characters[role].health),1,actor.max_health)
		actor.set_hidden_in_cover(false)
		var person:Dictionary=state.characters[role]
		person.stamina=clampf(float(person.stamina),0,100)
		person.hunger=clampf(float(person.hunger),0,100)
		person.thirst=clampf(float(person.thirst),0,100)
		while person.hotbar.size()<6: person.hotbar.append("")
		person.equipped=person.get("equipped","")
		for saved in state.get("orders",{}).get(role,[]):
			if not saved is Dictionary: continue
			var order:Dictionary=saved.duplicate(true)
			if order.has("position"):
				if not _valid_vector(order.get("position")): continue
				order.position=_decode_position(order.position)
			elif not world.objects.has(str(order.get("id",""))) and not (str(order.get("action","")).begins_with("ranch_") and state.get("ranch",{}).get("animals",{}).has(str(order.get("id","")))): continue
			if order.has("build_position"): order.build_position=_decode_position(order.build_position)
			order.phase="waiting"
			if order.action=="sleep" and saved.get("phase","")=="working" and orders[role].is_empty():
				order.phase="working"
				person.sleeping=true
				actor.position=world.objects[order.id].position
				actor.begin_work("Lie_Idle")
			orders[role].append(order)
	for id in world.objects:
		var obj:Dictionary=world.objects[id]
		if obj.type in ["enemy","cart","animal","companion","zombie"] or farm.owns(id) or industry.owns(id) or settlement.buildings.has(id): continue
		var visible:bool=not state.depleted.has(id)
		obj.node.visible=visible
		_disable_clicks(obj.node,visible)
	in_combat=false
	for id in enemies:
		var enemy:Dictionary=enemies[id]
		var saved:Dictionary=state.get("enemies",{}).get(id,{})
		enemy.actor.stop_moving()
		enemy.actor.position=_decode_position(saved.position) if _valid_vector(saved.get("position")) else enemy.home
		enemy.actor.health=0 if state.defeated.has(id) else float(saved.get("health",enemy.actor.max_health))
		enemy.actor.visible=not state.defeated.has(id)
		_disable_clicks(enemy.actor,not state.defeated.has(id))
		enemy.aggro=bool(saved.get("aggro",false)) and not state.defeated.has(id)
		enemy.cooldown=float(saved.get("cooldown",2))
		enemy.telegraph=float(saved.get("telegraph",0))
		enemy.hits=int(saved.get("hits",0))
	brother.set_weapon_equipped(state.characters.brother.equipped in ["sword","iron_sword"] and int(_inventory("brother").get(state.characters.brother.equipped,0))>0)
	for role in _roles():
		if _hero(role).has_method("set_armor_equipped"): _hero(role).set_armor_equipped(bool(state.characters[role].get("armor_equipped",false)) and int(_inventory(role).get("iron_armor",0))>0)
	if state.get("caravan") is Dictionary:
		caravan.restore(state.caravan)
	if ranch: ranch.restore(state.get("ranch",initial_ranch))
	if v5: v5.restore(state.get("v5",{}),not state.has("v5"))
	dialogue_queue.clear()
	for line in state.get("dialogue_queue",[]):
		if line is Dictionary and line.has("speaker") and line.has("text"): dialogue_queue.append(line)
	current_dialogue=state.get("current_dialogue",{})
	if current_dialogue.has("speaker") and current_dialogue.has("text"):
		hud.show_dialogue(current_dialogue.speaker,current_dialogue.text)
	else:
		current_dialogue={}
		hud.hide_dialogue()
	active=_hero(str(state.get("selected","brother")))
	brother.selected=active==brother
	sister.selected=active==sister
	camera_rig.focus_on(active)
	realtime_tick=0
	loading_state=false
	_update_ui()

func _migrate(old:Dictionary)->Dictionary:
	var data:=Campaign.new_state()
	for key in ["flags","stage","gathered_ore","depleted","defeated","elapsed","selected"]:
		if old.has(key): data[key]=old[key]
	data.characters.brother.inventory=old.inventory.duplicate(true) if old.get("inventory") is Dictionary else {}
	if data.flags is Dictionary and data.flags.get("farmer",false) and int(data.characters.brother.inventory.get("parcel",0))<1:
		data.characters.brother.inventory.parcel=1
	data.characters.sister.inventory={}
	data.characters.brother.health=old.get("brother_health",100)
	data.characters.sister.health=old.get("sister_health",80)
	data.characters.brother.hunger=old.get("hunger",100)
	data.characters.brother.thirst=old.get("thirst",100)
	data.characters.brother.equipped="sword" if int(data.characters.brother.inventory.get("sword",0))>0 else ""
	data["positions"]={"brother":old.get("brother_position",_vector(_ground(FARM_START))),"sister":old.get("sister_position",_vector(_ground(FARM_START+Vector2(3,2))))}
	return data

func _spawn_enemies() -> void:
	var definitions := [
		["road_1", "Дорожный мародёр", Vector2(3610, 4120), "enemy", 42.0, 6.0],
		["forest_1", "Лесной мародёр", Vector2(4510, 3820), "enemy", 42.0, 6.0],
		["forest_2", "Лесной мародёр", Vector2(4520, 3829), "enemy", 38.0, 5.0],
		["mine_1", "Охранник выработки", Vector2(2820, 4370), "enemy", 48.0, 7.0],
		["boss", "Страж выработки", Vector2(2735, 4320), "boss", 160.0, 10.0]
	]
	for entry in definitions:
		var id: String = entry[0]
		var actor = _actor(entry[3], entry[1], _ground(entry[2]))
		actor.max_health = entry[4]
		actor.health = entry[4]
		actor.move_speed = 4.0 if id == "boss" else 4.8
		enemies[id] = {"actor": actor, "home": actor.position, "cooldown": 1.6, "damage": entry[5], "aggro": false, "hits": 0, "telegraph": 0.0}
		var hit := StaticBody3D.new()
		hit.collision_layer = 2
		hit.collision_mask = 0
		hit.set_meta("object_id", id)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2, 3.5 if id == "boss" else 2.4, 2)
		shape.shape = box
		shape.position.y = box.size.y / 2
		hit.add_child(shape)
		actor.add_child(hit)
		world.objects[id] = {"id": id, "type": "enemy", "name": entry[1], "description": "Чужак у старой выработки. Брат вступит в бой при приближении. Сестра ищет укрытие.", "position": actor.position, "node": actor}


func _make_marker() -> void:
	movement_mark = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.75
	torus.rings = 16
	torus.ring_segments = 8
	movement_mark.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#ead498")
	movement_mark.material_override = mat
	add_child(movement_mark)
	movement_mark.hide()


func _make_hover_labels() -> void:
	hover_label = Label3D.new()
	hover_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hover_label.font_size = 44
	hover_label.pixel_size = 0.008
	hover_label.modulate = Color("#fff0bd")
	hover_label.outline_size = 12
	hover_label.no_depth_test = true
	add_child(hover_label)
	hover_label.hide()
	for id in world.objects:
		var object: Dictionary = world.objects[id]
		if object.type == "enemy":
			continue
		var label := Label3D.new()
		label.text = object.name
		label.font_size = 36
		label.pixel_size = 0.007
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 10
		label.no_depth_test = true
		label.position = object.position + Vector3(0, 2.5, 0)
		add_child(label)
		label.hide()
		object_labels[id] = label


func _update_hover() -> void:
	var show_labels := Input.is_physical_key_pressed(KEY_ALT)
	for id in object_labels:
		object_labels[id].visible = show_labels and not state.depleted.has(id) and _flat_distance(active.position, world.objects[id].position) < 65
	hover_label.hide()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if get_viewport().gui_get_hovered_control() != null:
		return
	var camera: Camera3D = camera_rig.camera
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(mouse) * 10000, 3)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return
	var hit: Node = result.collider
	if hit.has_meta("object_id"):
		var id := str(hit.get_meta("object_id"))
		if world.objects.has(id):
			var object: Dictionary = world.objects[id]
			hover_label.position = object.node.global_position + Vector3(0, 3.5, 0)
			hover_label.text = object.name
			hover_label.show()
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _person(role:String)->Dictionary:
	var person:Dictionary=state.characters[role]
	person["position"]=_hero(role).position
	person["role"]=role
	if life and life.sim.households.has("house_player"):
		person["wallet"]=life.sim.households.house_player
		person["stage"]=str(life.sim.residents.get(role,{}).get("stage","adult"))
	person["alchemy_learned"]=state.flags.get("alchemy_learned",false)
	person["allow_new_plots"]=bool(person.get("allow_new_plots",false)) and state.flags.get("garden_quest",false)
	return person


func _sync_navigation()->void:
	if navigation==null: return
	var dynamic:Array=world.obstacles.filter(func(o):return o.has("industry_id") or o.has("settlement_id") or o.has("farm_id"))
	navigation.set_dynamic_obstacles(dynamic)
	if caravan!=null and caravan._wagon_nav!=null:
		var expanded:Array=[]
		for o in dynamic: expanded.append({"position":o.position,"radius":float(o.radius)+.5})
		caravan._wagon_nav.set_dynamic_obstacles(expanded)


func _map_visibility(enabled:bool)->void:
	for node in find_children("*","GeometryInstance3D",true,false):
		if node is Label3D: continue
		if enabled:
			if not node.has_meta("original_range_end"): node.set_meta("original_range_end",node.visibility_range_end)
			node.visibility_range_end=0.0
		elif node.has_meta("original_range_end"):
			node.visibility_range_end=float(node.get_meta("original_range_end"))


func _end_job(role:String)->void:
	var actor=_hero(role)
	if state.characters[role].get("sleeping",false):
		if not orders[role].is_empty():
			var id:String=orders[role][0].get("id","")
			if world.objects.has(id): actor.position=world.objects[id].approach
	if life: life.cancel(role)
	state.characters[role]["sleeping"]=false
	actor.end_work()
	actor.stop_moving()


func _award_xp(role:String,skill:String,amount:float)->void:
	if amount<=0: return
	var person:Dictionary=state.characters[role]
	var old_level:int=Campaign.skill_level(person,skill)
	person.skills[skill]=float(person.skills.get(skill,0))+amount
	if skill=="alchemy": person.skills.potion_brewing=float(person.skills.get("potion_brewing",0))+amount
	if skill in ["weapon_smith","armor_smith"]: person.skills.blacksmithing=float(person.skills.get("blacksmithing",0))+amount*.25
	if Campaign.skill_level(person,skill)>old_level:
		hud.toast(_hero(role).display_name+" · "+str(Campaign.SKILLS.get(skill,skill))+" · уровень "+str(Campaign.skill_level(person,skill)))


func _work_requested(mode:String)->void:
	if mode=="stop":
		_clear_orders()
		return
	if _role_in_combat(str(active.role)) or _caravan_busy(str(active.role)) or _ranch_busy(str(active.role)):
		hud.toast("Сначала завершите бой или выйдите из телеги.")
		return
	var person:=_person(active.role)
	person.work_mode=mode
	person["work_end"]=(int(caravan.day_number)*1440+1080)
	if caravan.day_time>=1080: person.work_end+=1440
	_plan_workdays()
	hud.toast("Рабочий день до 18:00." if mode=="garden_day" else "Назначен обход сада.")


func _plan_workdays()->void:
	for role in _roles():
		var person:=_person(role)
		if str(person.work_mode).is_empty(): continue
		if str(person.work_mode)=="garden_day" and (caravan.day_time>=1200 or int(caravan.day_number)*1440+caravan.day_time>=float(person.get("work_end",INF))):
			person.work_mode=""
			for i in range(orders[role].size()-1,0,-1):
				if orders[role][i].get("automatic",false): orders[role].remove_at(i)
			hud.toast(_hero(role).display_name+" заканчивает рабочий день.")
			continue
		if not orders[role].is_empty(): continue
		if _role_in_combat(str(role)) or _caravan_busy(str(role)) or _ranch_busy(str(role)) or person.get("sleeping",false): continue
		if float(person.sleep)<12 or float(person.stamina)<8 or float(person.hunger)<5 or float(person.thirst)<5:
			person.work_mode=""
			hud.toast(_hero(role).display_name+" прекращает работу: нужны отдых и припасы.")
			continue
		if str(person.work_mode)=="garden_day" and (caravan.day_time>=1200 or int(caravan.day_number)*1440+caravan.day_time>=float(person.get("work_end",INF))):
			person.work_mode=""
			hud.toast(_hero(role).display_name+" завершил рабочий день.")
			continue
		var plan:Array=farm.plan_work(person,bool(person.allow_new_plots))
		for job in plan:
			if orders[role].size()>=12: break
			# Avoid assigning an already claimed plot to another worker.
			var claimed:bool=false
			for other_role in _roles():
				if other_role==role: continue
				for other in orders[other_role]:
					if other.get("id","")==job.id and other.get("action","")==job.action: claimed=true
			if claimed: continue
			job.phase="waiting"
			job.remaining=0.0
			job.automatic=true
			orders[role].append(job)
		if plan.is_empty() and str(person.work_mode)=="garden_once":
			person.work_mode=""
			hud.toast(_hero(role).display_name+" завершил текущий уход за садом.")


func _allow_new_plots(value:bool)->void:
	if value and not state.flags.get("garden_quest",false):
		hud.toast("Сначала поговорите с Мартой о работе в саду.")
		_update_ui()
		return
	state.characters[active.role].allow_new_plots=value
	farm.set_new_plots_allowed(_garden_expansion_allowed())
	_update_ui()


func _follow_toggle(value:bool)->void:
	state.characters[active.role].follow=value
	hud.toast("Этот герой будет следовать за вторым." if value else "Герой действует самостоятельно.")


func _begin_build(kind:String)->void:
	if not settlement.BLUEPRINTS.has(kind) or _role_in_combat(str(active.role)): return
	hud.dismiss_all()
	_cancel_build()
	build_kind=kind
	build_rotation=0
	build_ghost=MeshInstance3D.new()
	var mesh:=BoxMesh.new()
	var radius:float=settlement.BLUEPRINTS[kind].radius
	mesh.size=Vector3(radius*2,.15,radius*2)
	build_ghost.mesh=mesh
	var mat:=StandardMaterial3D.new()
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	build_ghost.material_override=mat
	add_child(build_ghost)
	hud.toast("ЛКМ — разместить заказ; R — повернуть; ПКМ — отменить.")


func _update_build_ghost()->void:
	if build_kind.is_empty() or not is_instance_valid(build_ghost): return
	var mouse:=get_viewport().get_mouse_position()
	var cam:Camera3D=camera_rig.camera
	var ray:=cam.project_ray_origin(mouse)
	var query:=PhysicsRayQueryParameters3D.create(ray,ray+cam.project_ray_normal(mouse)*10000,1)
	var hit:=get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		build_ghost.hide()
		build_valid=false
		return
	build_point=_ground(Vector2(roundf(hit.position.x/2)*2,roundf(hit.position.z/2)*2))
	build_ghost.position=build_point+Vector3(0,.2,0)
	build_ghost.rotation.y=build_rotation
	build_ghost.show()
	build_valid=settlement.can_place(build_kind,build_point,str(active.role),build_move_id).is_empty()
	build_ghost.material_override.albedo_color=Color(0.25,.8,.5,.6) if build_valid else Color(.9,.25,.2,.6)


func _place_build_order()->void:
	if not build_valid:
		hud.toast("Здесь нельзя строить: нужен свободный ровный участок.")
		return
	if not build_move_id.is_empty():
		life._queue_command(str(active.role),"build:relocate",{"target_id":build_move_id,"position":_vector(build_point),"rotation":build_rotation},false)
		_cancel_build()
		return
	var radius:float=settlement.BLUEPRINTS[build_kind].radius
	var approach:Vector3=build_point+Vector3(0,0,radius+1.8).rotated(Vector3.UP,build_rotation)
	_enqueue(active.role,{"action":"construct","kind":build_kind,"id":"","position":_ground(Vector2(approach.x,approach.z)),"build_position":build_point,"rotation":build_rotation,"phase":"waiting"})
	_cancel_build()


func _cancel_build()->void:
	build_kind=""
	build_move_id=""
	if is_instance_valid(build_ghost): build_ghost.queue_free()
	build_ghost=null


func _building_storage(action:String,id:String,role:String)->void:
	if not settlement.buildings.has(id): return
	var store:Dictionary=settlement.buildings[id].storage
	var inv:=_inventory(role)
	if action=="store_all":
		for item in inv.keys():
			if item in Campaign.EQUIPMENT or item in ["water","ration","parcel"]: continue
			store[item]=int(store.get(item,0))+int(inv[item])
			inv[item]=0
	else:
		for item in store.keys():
			inv[item]=int(inv.get(item,0))+int(store[item])
			store[item]=0
	hud.toast("Припасы переложены.")

