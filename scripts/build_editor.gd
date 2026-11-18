extends RefCounted
## Stable object IDs preserve furniture state when moving. Undo reverses only its own delta.
var game
var history:Array=[]
var colors:Dictionary={}
const PALETTE={"oak":Color("#a8794a"),"white":Color("#ded4b7"),"green":Color("#75967a"),"red":Color("#ac6253")}
func configure(owner_game)->void: game=owner_game
func owns(id:String)->bool: return id.begins_with("built_") and (game.settlement.buildings.has(id) or game.industry._records.has(id))
func _record(id:String)->Dictionary:
	return game.settlement.buildings.get(id,game.industry._records.get(id,{}))
func _point(record:Dictionary)->Vector3: return game._decode_position(record.position)
func begin_move(id:String)->void:
	if not owns(id): return
	game._begin_build(str(_record(id).kind)); game.build_move_id=id
	game.build_rotation=float(_record(id).get("rotation",0))
	game.hud.toast("Выберите новое место. Перенос сохранит содержимое и состояние мебели.")
func placement(role:String,id:String,point:Vector3)->String:
	if not owns(id): return "Постройка больше не существует."
	var reason:String=game.settlement.can_place(str(_record(id).kind),point,role,id)
	if reason.is_empty() and game.industry.BLUEPRINTS.has(_record(id).kind): reason=game.industry.can_place(str(_record(id).kind),point,id)
	return reason
func spec(role:String,verb:String,payload:Dictionary)->Dictionary:
	if verb.begins_with("paint:"):
		payload=payload.duplicate(true); payload.color=verb.trim_prefix("paint:"); verb="paint"
	var id:String=str(payload.get("target_id",""))
	if verb=="undo" and not history.is_empty(): id=str(history.back().id)
	var reason:=""
	if not game.state.characters.has(role): reason="Персонаж недоступен."
	elif verb=="undo":
		if history.is_empty(): reason="Нет изменений для отмены."
		elif str(history.back().role)!=role: reason="Последнее изменение сделал другой домочадец."
	elif not owns(id): reason="Редактировать можно только собственные новые постройки."
	elif verb not in ["relocate","rotate","paint","demolish"]: reason="Неизвестное изменение."
	if reason.is_empty():
		for worker in game.orders:
			var queue:Array=game.orders[worker]
			if queue.is_empty() or str(queue[0].get("phase",""))!="working": continue
			if worker==role and str(queue[0].get("action","")).begins_with("life:build:"): continue
			if str(queue[0].get("id",""))==id or str(queue[0].get("payload",{}).get("target_id",""))==id: reason="Сначала закончите использование этого предмета."; break
		for claim in game.life.sim.reservations.get(id,[]):
			if str(claim.actor_id)!=role and float(claim.expires)>float(game.life.sim.clock): reason="Предмет занят другим жителем."; break
	if reason.is_empty() and verb!="undo":
		var r:Dictionary=_record(id)
		reason=game.v5.civic.can_build(role,_point(r),str(r.kind))
		if reason.is_empty() and verb=="relocate":
			if not game._valid_vector(payload.get("position")): reason="Не выбрано новое место."
			else: reason=placement(role,id,game._decode_position(payload.position))
		if reason.is_empty() and verb=="paint" and not PALETTE.has(payload.get("color","")): reason="Выберите цвет."
		if reason.is_empty() and payload.has("rotation") and not game._number(payload.rotation): reason="Неверный угол поворота."
		if reason.is_empty() and verb=="paint" and int(game._inventory(role).get("coal",0))<1: reason="Нужен уголь для приготовления краски."
		if reason.is_empty() and verb=="demolish" and not r.get("storage",{}).values().filter(func(n):return int(n)>0).is_empty(): reason="Сначала освободите ящик."
	var point:Vector3=game._hero(role).position if game.state.characters.has(role) else Vector3.ZERO
	if verb=="undo" and not history.is_empty(): point=game._decode_position(history.back().approach)
	elif game.world.objects.has(id): point=game.world.objects[id].get("approach",game.world.objects[id].position)
	return {"ok":reason.is_empty(),"reason":reason,"target":point,"venue_id":id,"portable":false,"duration":20.0,"animation":"interact","label":{"relocate":"Перенести постройку","rotate":"Повернуть постройку","paint":"Покрасить","demolish":"Разобрать","undo":"Отменить изменение"}.get(verb,verb)}
func complete(role:String,verb:String,payload:Dictionary)->Dictionary:
	if verb.begins_with("paint:"):
		payload=payload.duplicate(true); payload.color=verb.trim_prefix("paint:"); verb="paint"
	var plan:Dictionary=spec(role,verb,payload)
	if not plan.ok: return {"ok":false,"message":plan.reason}
	if game._flat_distance(game._hero(role).position,plan.target)>2.3: return {"ok":false,"message":"Подойдите к постройке."}
	if verb=="undo": return _undo(role)
	var id:String=str(payload.target_id)
	var old:Dictionary=_record(id).duplicate(true)
	var entry:Dictionary={"role":role,"id":id,"verb":verb,"before":old,"color":colors.get(id,""),"refund":{},"approach":game._vector(plan.target),"domestic":game.v5.domestic.objects.get(id,{}).duplicate(true) if verb=="demolish" else {}}
	if verb=="demolish":
		for item in game.settlement.BLUEPRINTS[old.kind].cost:
			var amount:int=floori(float(game.settlement.BLUEPRINTS[old.kind].cost[item])*.5)
			if amount>0: entry.refund[item]=amount; game._inventory(role)[item]=int(game._inventory(role).get(item,0))+amount
		_remove(id); colors.erase(id)
	else:
		if verb=="paint":
			game._inventory(role).coal=int(game._inventory(role).coal)-1
			colors[id]=str(payload.color); _paint_node(game.world.objects[id].node,PALETTE[payload.color])
		else:
			var changed:Dictionary=old.duplicate(true)
			changed.rotation=float(payload.get("rotation",old.get("rotation",0)+PI/2))
			if verb=="relocate": changed.position=payload.position.duplicate()
			if not _replace(id,changed): return {"ok":false,"message":"Перенос отменён: мастерская не помещается. Прежнее положение сохранено."}
	entry["after"]=_record(id).duplicate(true)
	entry["after_color"]=colors.get(id,"")
	history.append(entry)
	if history.size()>12: history.pop_front()
	game._sync_navigation(); game.v5.domestic.sync_objects()
	return {"ok":true,"message":"Изменение готово. Последнюю операцию можно отменить в «Жизнь → Дом → Постройки»."}
func _remove(id:String)->void:
	if game.industry._records.has(id): game.industry._remove_placed(id)
	else:
		if game.world.objects.has(id): game.world.objects[id].node.queue_free(); game.world.objects.erase(id)
		game.settlement.buildings.erase(id)
		game.world.obstacles=game.world.obstacles.filter(func(o):return str(o.get("settlement_id",""))!=id)
	game.life.sim.venues.erase(id)
func _replace(id:String,record:Dictionary)->bool:
	var previous:Dictionary=_record(id).duplicate(true)
	_remove(id)
	if game.industry.BLUEPRINTS.has(record.kind):
		var node=game.industry.place_station(record.kind,id,_point(record),float(record.rotation))
		if node==null:
			if not previous.is_empty(): game.industry._add_object(str(previous.kind),id,Vector2(float(previous.position[0]),float(previous.position[2])),float(previous.rotation),true)
			game.life._register_building(id); game._sync_navigation()
			return false
	else:
		game.settlement._place_plain(record.kind,id,_point(record),float(record.rotation))
		game.settlement.buildings[id]=record.duplicate(true)
	game.life._register_building(id)
	if colors.has(id): _paint_node(game.world.objects[id].node,PALETTE[colors[id]])
	return true
func _paint_node(node:Node,color:Color)->void:
	if node is MeshInstance3D:
		var mat:=StandardMaterial3D.new(); mat.albedo_color=color; mat.roughness=.9; node.material_override=mat
	for child in node.get_children(): _paint_node(child,color)
func _undo(role:String)->Dictionary:
	var e:Dictionary=history.back(); var id:String=e.id
	if _record(id)!=e.after or str(colors.get(id,""))!=str(e.after_color): return {"ok":false,"message":"Предмет изменился после операции. Отмена не затронет новый прогресс."}
	if e.verb=="demolish":
		for item in e.refund:
			if int(game._inventory(role).get(item,0))<int(e.refund[item]): return {"ok":false,"message":"Возвращённые материалы уже израсходованы. Для отмены верните их в рюкзак."}
		var reason:String=game.settlement.can_place(str(e.before.kind),_point(e.before),role)
		if reason.is_empty() and game.industry.BLUEPRINTS.has(e.before.kind): reason=game.industry.can_place(str(e.before.kind),_point(e.before))
		if not reason.is_empty(): return {"ok":false,"message":reason}
		for item in e.refund: game._inventory(role)[item]=int(game._inventory(role)[item])-int(e.refund[item])
	elif e.verb in ["rotate","relocate"]:
		var reason:String=placement(role,id,_point(e.before))
		if not reason.is_empty(): return {"ok":false,"message":reason}
	var previous_color:String=str(colors.get(id,""))
	if str(e.color).is_empty(): colors.erase(id)
	else: colors[id]=e.color
	if not _replace(id,e.before):
		if previous_color.is_empty(): colors.erase(id)
		else: colors[id]=previous_color
		if e.verb=="demolish":
			for item in e.refund: game._inventory(role)[item]=int(game._inventory(role).get(item,0))+int(e.refund[item])
		return {"ok":false,"message":"Постройка не помещается; отмена не потратила материалы."}
	if e.verb=="paint": game._inventory(role).coal=int(game._inventory(role).get("coal",0))+1
	# Restore only this object's condition, never the whole household's elapsed simulation.
	game.v5.domestic.sync_objects()
	if e.verb=="demolish" and game.v5.domestic.has_method("restore_object_condition"): game.v5.domestic.restore_object_condition(id,e.domestic)
	history.pop_back(); game._sync_navigation()
	return {"ok":true,"message":"Последнее изменение отменено."}
func actions(id:String,role:String)->Array:
	var rows:Array=[]
	for verb in ["move","rotate","demolish"]:
		rows.append({"id":"build:"+verb,"label":{"move":"Перенести","rotate":"Повернуть на 90°","demolish":"Разобрать · вернуть половину материалов"}[verb],"payload":{"target_id":id},"enabled":true})
	for color in PALETTE:
		rows.append({"id":"build:paint:"+color,"label":"Цвет: "+{"oak":"дуб","white":"светлая штукатурка","green":"зелёный","red":"охра"}[color],"payload":{"target_id":id,"color":color},"enabled":int(game._inventory(role).get("coal",0))>0,"reason":"Нужен 1 уголь."})
	return rows
func ui_rows(role:String)->Array:
	var rows:Array=[{"id":"undo","name":"Отменить последнее изменение","details":["Перенос, поворот, цвет или разбор. Материалы и содержимое проверяются повторно."],"actions":[{"id":"build:undo","label":"Отменить","payload":{},"enabled":not history.is_empty()}]}]
	for id in game.world.objects:
		if owns(id): rows.append({"id":id,"name":str(game.world.objects[id].name)+" · "+id,"details":["Положение: %.0f, %.0f"%[_point(_record(id)).x,_point(_record(id)).z]],"actions":actions(id,role)})
	return rows
func snapshot()->Dictionary: return {"version":1,"history":history.duplicate(true),"colors":colors.duplicate(true)}
func valid_snapshot(data:Variant)->bool:
	if not data is Dictionary or int(data.get("version",0))!=1 or not data.get("history") is Array or not data.get("colors") is Dictionary: return false
	if data.history.size()>12 or not game.life.sim._finite_tree(data): return false
	for c in data.colors.values():
		if not PALETTE.has(c): return false
	for e in data.history:
		if not e is Dictionary or not e.get("id") is String or not e.get("before") is Dictionary or not e.get("after") is Dictionary or not game._valid_vector(e.get("approach")) or not game._valid_vector(e.before.get("position")) or not game.settlement.BLUEPRINTS.has(e.before.get("kind","")): return false
		if not game._valid_counts(e.get("refund",{})) or e.get("verb","") not in ["paint","rotate","relocate","demolish"]: return false
		if not e.get("role") is String or not e.get("color") is String or not e.get("after_color") is String or not game._number(e.before.get("rotation")): return false
		if not e.color.is_empty() and not PALETTE.has(e.color): return false
		if not e.after_color.is_empty() and not PALETTE.has(e.after_color): return false
		if not e.get("domestic") is Dictionary: return false
		for record in [e.before,e.after]:
			if record.is_empty(): continue
			if not game._valid_counts(record.get("storage",{})) or not game._number(record.get("health",100)) or not game._number(record.get("rotation")) or not game._valid_vector(record.get("position")): return false
		if not e.domestic.is_empty():
			if not e.domestic.get("lit") is bool: return false
			for key in ["condition","cleanliness","fuel","fire","hazard","upgrade","uses"]:
				if not game._number(e.domestic.get(key)): return false
	return true
func restore(data:Dictionary)->void:
	history=data.get("history",[]).duplicate(true); colors=data.get("colors",{}).duplicate(true)
	for id in colors:
		if game.world.objects.has(id): _paint_node(game.world.objects[id].node,PALETTE[colors[id]])
