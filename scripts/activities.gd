extends Node3D
## Timed, finite outdoor activities. Positions and rewards survive saving.
const Campaign=preload("res://scripts/campaign.gd")
const COLLECTIONS={"amber":"Янтарь","quartz":"Кварц","fossil":"Окаменелость","beetle":"Лесной жук","butterfly":"Луговая бабочка","river_pearl":"Речная жемчужина"}
const SPELLS={
	"heal":{"name":"Малое исцеление","cost":24.0,"cooldown":90.0,"lesson_cost":18,"level":0,"details":"Восстановить 25 здоровья выбранному домочадцу рядом."},
	"rain":{"name":"Дождь для сада","cost":32.0,"cooldown":120.0,"lesson_cost":25,"level":1,"details":"Увлажнить существующие грядки в радиусе 12 м."},
	"ward":{"name":"Защитный оберег","cost":30.0,"cooldown":180.0,"lesson_cost":30,"level":1,"details":"Получаемый героем урон снижается на 25% на четыре игровых часа."},
	"light":{"name":"Светляк","cost":12.0,"cooldown":30.0,"lesson_cost":10,"level":0,"details":"Мягкий источник света сопровождает героя ночью в течение трёх часов."}
}
var game
var sites:Dictionary={}
var people:Dictionary={}
var collections:Dictionary={}
var claims:Dictionary={}
var _lights:Dictionary={}
var _rng:=RandomNumberGenerator.new()
var _clock:=0.0
var _requests:Dictionary={}

func configure(owner_game)->void:
	game=owner_game
	_rng.seed=178246
	_clock=float(game.life.sim.clock)
	_build()

func _build()->void:
	var definitions:Array=[
		["activity_fishing_1","fish","Рыбалка · городская заводь",Vector2(2839,3661),6],
		["activity_fishing_2","fish","Рыбалка · северная протока",Vector2(2745,3349),5],
		["activity_fishing_3","fish","Рыбалка · тихий берег",Vector2(2542,3708),4],
		["activity_dig_1","dig","Каменная россыпь",Vector2(3065,3655),3],
		["activity_dig_2","dig","Старая осыпь у шахты",Vector2(2860,4410),3],
		["activity_dig_3","dig","Янтарные камни",Vector2(4440,3905),3],
		["activity_insects_1","insects","Бабочки у луга",Vector2(4160,4400),4],
		["activity_insects_2","insects","Лесные насекомые",Vector2(4320,3900),4],
		["activity_music","music","Музыкальная площадка",Vector2(3593,3454),0],
		["activity_paint","paint","Мольберт у сада",Vector2(4068,4444),0],
		["activity_collection","collection","Стол находок библиотеки",Vector2(3682,3536),0]
	]
	for d in definitions:
		var pos:Vector3=_safe(d[3])
		var id:String=d[0]
		sites[id]={"id":id,"kind":d[1],"name":d[2],"position":game._vector(pos),"stock":int(d[4]),"capacity":int(d[4]),"refill":_clock+1440.0,"count":0}
		_create_site(id)

func _safe(p:Vector2)->Vector3:
	for radius in range(0,22,2):
		for step in range(12):
			var test:Vector2=p+Vector2.from_angle(TAU*float(step)/12)*radius
			if game.navigation.is_walkable(test): return game._ground(test)
	return game._ground(p)

func _create_site(id:String)->void:
	var s:Dictionary=sites[id]
	var node:=Node3D.new()
	node.name=id
	add_child(node)
	node.position=game._decode_position(s.position)
	var pick:=StaticBody3D.new()
	pick.collision_layer=2; pick.collision_mask=0; pick.set_meta("object_id",id)
	var shape:=CollisionShape3D.new(); var cylinder:=CylinderShape3D.new()
	cylinder.radius=1.15; cylinder.height=1.8; shape.shape=cylinder; shape.position.y=.9
	pick.add_child(shape); node.add_child(pick)
	var mesh:=MeshInstance3D.new(); var geo:=CylinderMesh.new()
	geo.top_radius=1.1; geo.bottom_radius=1.3; geo.height=.16; geo.radial_segments=12
	mesh.mesh=geo; mesh.position.y=.1
	var mat:=StandardMaterial3D.new(); mat.albedo_color=Color("#688c9c") if s.kind=="fish" else Color("#a89466")
	mesh.material_override=mat; node.add_child(mesh)
	if s.kind in ["paint","collection","music"]:
		var prop:Node3D=game.city.create_prop("easel" if s.kind=="paint" else "map_table" if s.kind=="collection" else "lute",node)
		prop.position=Vector3(0,.2,-.7)
	else:
		for i in 4:
			var detail:=MeshInstance3D.new(); var rock:=SphereMesh.new()
			rock.radius=.18+float(i)*.055; rock.height=rock.radius*1.2; rock.radial_segments=8; rock.rings=4
			detail.mesh=rock; detail.position=Vector3(sin(float(i)*2)*.7,.22,cos(float(i)*2)*.7); detail.material_override=mat; node.add_child(detail)
	game.world.objects[id]={"id":id,"type":"activity_site","name":s.name,"description":"Доступные занятия требуют подхода, времени и подходящих инструментов. Запасы восстанавливаются раз в день.","position":node.position,"approach":node.position+Vector3(0,0,1.5),"surface_radius":.1,"node":node}
	game.life.sim.venues[id]={"id":id,"name":s.name,"kind":"activity","position":game._vector(node.position+Vector3(0,0,1.5)),"capacity":1,"safe":false}

func _person(role:String)->Dictionary:
	if not people.has(role): people[role]={"mana":100.0,"spells":[],"cooldowns":{},"ward_until":0.0,"light_until":0.0,"perform_until":0.0,"fish_caught":0,"finds":0,"paintings":0}
	return people[role]

func tick(delta:float)->void:
	_clock=float(game.life.sim.clock)
	for id in sites:
		var s:Dictionary=sites[id]
		if _clock>=float(s.refill): s.stock=int(s.capacity); s.refill=_clock+1440.0
	for role in game._roles():
		var p:Dictionary=_person(role)
		p.mana=minf(100,float(p.mana)+delta*(.08 if float(game.state.characters[role].sleep)>20 else .025))
		if float(p.light_until)>_clock:
			if not _lights.has(role):
				var light:=OmniLight3D.new(); light.omni_range=12; light.light_color=Color("#e3d898"); light.light_energy=1.2
				game._hero(role).add_child(light); light.position=Vector3(0,2.5,0); _lights[role]=light
		elif _lights.has(role):
			if is_instance_valid(_lights[role]): _lights[role].queue_free()
			_lights.erase(role)

func owns(id:String)->bool: return sites.has(id)

func actions(id:String,role:String)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if not sites.has(id): return result
	var choices:Array=[]
	match str(sites[id].kind):
		"fish": choices=[["fish","Ловить рыбу"],["fish_bait","Ловить с наживкой · ягода"]]
		"dig": choices=[["dig","Исследовать камни · кирка"]]
		"insects": choices=[["insects","Поймать насекомое"]]
		"music": choices=[["practice_music","Разучивать мелодию"],["perform","Выступить перед горожанами"]]
		"paint": choices=[["paint","Написать картину · ткань и уголь"]]
		"collection": choices=[["exhibit","Передать находки в коллекцию"]]
	for choice in choices: result.append(_action(role,choice[0],choice[1],{"target_id":id}))
	return result

func _action(role:String,verb:String,label:String,payload:Dictionary)->Dictionary:
	var check:Dictionary=spec(role,verb,payload)
	return {"id":"activity:"+verb,"label":label,"payload":payload,"enabled":bool(check.ok),"reason":str(check.reason)}

func spec(role:String,verb:String,payload:Dictionary={})->Dictionary:
	var r:Dictionary={"ok":false,"reason":"","target":Vector3.ZERO,"venue_id":"","duration":30.0,"animation":"interact","portable":false,"label":"Занятие"}
	if not game.state.characters.has(role): r.reason="Персонаж недоступен."; return r
	var inv:Dictionary=game._inventory(role)
	var p:Dictionary=_person(role)
	var id:String=str(payload.get("target_id",""))
	if verb=="learn_spell":
		var spell:String=str(payload.get("spell_id",""))
		if not SPELLS.has(spell): r.reason="Неизвестный урок."; return r
		if p.spells.has(spell): r.reason="Этот приём уже изучен."; return r
		if float(game.life.sim.residents[role].age_years)<13: r.reason="Практическая магия доступна с подросткового возраста."; return r
		if Campaign.skill_level(game.state.characters[role],"magic")<int(SPELLS[spell].level): r.reason="Нужен первый уровень прикладной магии."; return r
		if int(game.life.sim.households.house_player.coins)<int(SPELLS[spell].lesson_cost): r.reason="Не хватает средств на урок."; return r
		r.venue_id="life_academy"; r.target=game.life._vec(game.life.sim.venues.life_academy.approach); r.duration=60.0; r.label="Урок: "+str(SPELLS[spell].name); r.ok=true; return r
	if verb=="cast":
		var spell:String=str(payload.get("spell_id",""))
		if not SPELLS.has(spell) or not p.spells.has(spell): r.reason="Сначала изучите этот приём в академии."; return r
		if float(p.mana)<float(SPELLS[spell].cost): r.reason="Не хватает магических сил."; return r
		if _clock<float(p.cooldowns.get(spell,0)): r.reason="Приём ещё восстанавливается."; return r
		if int(inv.get("wand",0))<1: r.reason="Нужна фокусирующая палочка в рюкзаке."; return r
		r.target=game._hero(role).position; r.portable=true; r.duration=5.0; r.label=str(SPELLS[spell].name)
		if spell=="heal":
			if not game.state.characters.has(id): r.reason="Выберите домочадца."; return r
			r.target=game._hero(id).position; r.portable=false; r.venue_id="person:"+id
			if game._hero(id).health>=game._hero(id).max_health: r.reason="Лечение сейчас не требуется."; return r
		if spell=="rain":
			var nearby:=false
			for plot in game.farm.plots:
				if game.world.objects.has(plot) and game._flat_distance(r.target,game.world.objects[plot].position)<=12: nearby=true
			if not nearby: r.reason="Встаньте рядом с грядками своего сада."; return r
		r.ok=true; return r
	if not sites.has(id): r.reason="Выберите место занятия."; return r
	var s:Dictionary=sites[id]
	r.target=game.world.objects[id].approach; r.venue_id=id
	if claims.has(id) and str(claims[id].role)!=role and float(claims[id].until)>_clock: r.reason="Место занято другим персонажем."; return r
	if verb in ["fish","fish_bait","dig","insects"] and int(s.stock)<=0: r.reason="На сегодня запасы исчерпаны. Вернитесь завтра."; return r
	match verb:
		"fish","fish_bait":
			if s.kind!="fish": r.reason="Здесь нельзя ловить рыбу."; return r
			if int(inv.get("fishing_rod",0))<1: r.reason="Изготовьте удочку на верстаке или купите на рынке."; return r
			if verb=="fish_bait" and int(inv.get("berry",0))<1: r.reason="Для наживки нужна ягода."; return r
			r.duration=45.0; r.label="Ловить рыбу"
		"dig":
			if s.kind!="dig" or int(inv.get("pickaxe",0))<1: r.reason="Нужны россыпь и кирка."; return r
			r.duration=35.0; r.animation="mine"; r.label="Исследовать россыпь"
		"insects":
			if s.kind!="insects": r.reason="Здесь нет насекомых."; return r
			r.duration=25.0; r.label="Поймать насекомое"
		"practice_music","perform":
			if s.kind!="music": r.reason="Выберите музыкальную площадку."; return r
			if int(inv.get("lute",0))<1: r.reason="Нужна лютня в рюкзаке."; return r
			if verb=="perform" and Campaign.skill_level(game.state.characters[role],"performance")<1: r.reason="Сначала разучите несколько мелодий: нужен первый уровень."; return r
			if verb=="perform" and _clock<float(p.perform_until): r.reason="Публике нужен перерыв. Следующее выступление через несколько часов."; return r
			r.duration=70.0 if verb=="perform" else 50.0; r.label="Выступать" if verb=="perform" else "Репетировать"
		"paint":
			if s.kind!="paint" or int(inv.get("cloth",0))<1 or int(inv.get("coal",0))<1: r.reason="Для картины нужны мольберт, ткань и уголь."; return r
			r.duration=80.0; r.label="Написать картину"
		"exhibit":
			if s.kind!="collection": r.reason="Выберите стол коллекции в библиотеке."; return r
			var held:=false
			for item in COLLECTIONS:
				if int(inv.get(item,0))>0 and not collections.has(item): held=true
			if not held: r.reason="Нет новых находок для коллекции."; return r
			r.duration=20.0; r.label="Описать и выставить находки"
		_: r.reason="Неизвестное занятие."; return r
	r.ok=true
	return r

func reserve(role:String,id:String,duration:float)->bool:
	if id.is_empty() or not sites.has(id): return true
	if claims.has(id) and str(claims[id].role)!=role and float(claims[id].until)>_clock: return false
	claims[id]={"role":role,"until":_clock+duration+30}
	return true

func release(role:String)->void:
	for id in claims.keys():
		if claims[id].role==role: claims.erase(id)

func complete(role:String,verb:String,payload:Dictionary={})->Dictionary:
	var key:String=role+":"+str(payload.get("request_id",""))
	if payload.has("request_id") and _requests.has(key):
		var replay:Dictionary=_requests[key].duplicate(true)
		replay["replayed"]=true
		return replay
	var check:Dictionary=spec(role,verb,payload)
	if not check.ok: return {"ok":false,"message":check.reason}
	if not check.portable and game._flat_distance(game._hero(role).position,check.target)>2.25: return {"ok":false,"message":"Подойдите к месту занятия."}
	var inv:Dictionary=game._inventory(role); var p:Dictionary=_person(role)
	var id:String=str(payload.get("target_id","")); var item:=""; var amount:=1
	var result:Dictionary={"ok":true,"message":"Готово.","skill":"research","xp":12}
	if verb in ["fish","fish_bait","dig","insects"]:
		sites[id].stock=int(sites[id].stock)-1; sites[id].count=int(sites[id].count)+1
	match verb:
		"fish","fish_bait":
			if verb=="fish_bait": inv.berry=int(inv.berry)-1
			var level:int=Campaign.skill_level(game.state.characters[role],"fishing")
			item="river_pearl" if verb=="fish_bait" and int(sites[id].count)%5==0 else "trout" if level>=1 and int(sites[id].count)%3==0 else "fish"
			amount=2 if verb=="fish_bait" and item=="fish" else 1
			p.fish_caught=int(p.fish_caught)+amount; result.skill="fishing"; result.xp=22
		"dig": item=["quartz","amber","fossil"][(int(sites[id].count)-1+int(id.hash())%3+3)%3]; result.skill="research"; p.finds=int(p.finds)+1
		"insects": item="butterfly" if int(sites[id].count)%2==0 else "beetle"; result.skill="herbalism"; p.finds=int(p.finds)+1
		"practice_music": result.skill="performance"; result.xp=25; result.message="Мелодия стала звучать увереннее."
		"perform":
			var visitors:=0
			for resident in game.life.sim.residents:
				if resident==role or not game.life.sim.residents[resident].alive: continue
				if game._flat_distance(game.life.sim.position_of(resident),game._hero(role).position)<100: visitors+=1
			var income:int=mini(int(game.life.sim.market.treasury),mini(20,visitors*2+Campaign.skill_level(game.state.characters[role],"performance")))
			game.life.sim.market.treasury-=income; game.life.sim.households.house_player.coins+=income; game.life.sim.households.house_player.income+=income
			p.perform_until=_clock+240; result.skill="performance"; result.xp=35; result.message="Выступление завершено. Слушателей поблизости: %d. Заработано: %d монет."%[visitors,income]
		"paint": inv.cloth=int(inv.cloth)-1; inv.coal=int(inv.coal)-1; item="artwork"; p.paintings=int(p.paintings)+1; result.skill="painting"; result.xp=25
		"exhibit":
			var donated:=0
			for found in COLLECTIONS:
				if int(inv.get(found,0))>0 and not collections.has(found):
					inv[found]=int(inv[found])-1; collections[found]={"by":role,"time":_clock}; donated+=1
			result.message="Новых находок в общей коллекции: %d из %d."%[donated,COLLECTIONS.size()]; result.xp=donated*30
			if collections.size()==COLLECTIONS.size() and not collections.has("rewarded"):
				collections["rewarded"]={"by":role,"time":_clock}; inv.book=int(inv.get("book",0))+1; result.message+=" Коллекция завершена: библиотека вручила редкую книгу."
		"learn_spell":
			var spell:String=str(payload.spell_id); var cost:int=int(SPELLS[spell].lesson_cost)
			game.life.sim.households.house_player.coins-=cost; game.life.sim.households.house_player.expenses+=cost; game.life.sim.market.treasury+=cost
			p.spells.append(spell); result.skill="magic"; result.xp=35; result.message="Изучен приём: "+str(SPELLS[spell].name)
		"cast":
			var spell:String=str(payload.spell_id)
			p.mana-=float(SPELLS[spell].cost); p.cooldowns[spell]=_clock+float(SPELLS[spell].cooldown)
			match spell:
				"heal": game._hero(id).health=minf(game._hero(id).max_health,game._hero(id).health+25)
				"rain":
					for plot in game.farm.plots:
						if game.world.objects.has(plot) and game._flat_distance(game._hero(role).position,game.world.objects[plot].position)<=12: game.farm.plots[plot].water=minf(100,float(game.farm.plots[plot].water)+45)
				"ward": p.ward_until=_clock+240
				"light": p.light_until=_clock+180
			result.skill="magic"; result.xp=18; result.message="Сработал приём: "+str(SPELLS[spell].name)
	if not item.is_empty():
		inv[item]=int(inv.get(item,0))+amount; result.item=item; result.count=amount; result.message="Получено: %s × %d."%[Campaign.ITEMS.get(item,item),amount]
	game.life.sim._change_need(role,"fun",15)
	if payload.has("request_id"):
		_requests[key]=result.duplicate(true)
		if _requests.size()>256: _requests.erase(_requests.keys()[0])
	release(role)
	return result

func damage_multiplier(role:String)->float:
	return .75 if people.has(role) and float(people[role].ward_until)>_clock else 1.0

func ui_rows(role:String)->Dictionary:
	var result:Dictionary={"activities":[],"collections":[],"magic":[]}
	for id in sites:
		var s:Dictionary=sites[id]
		var rows:Array=actions(id,role)
		rows.push_front({"id":"activity:focus","label":"Показать место","payload":{"target_id":id},"enabled":true})
		result.activities.append({"id":id,"name":s.name,"details":["Доступно сегодня: "+str(s.stock) if int(s.capacity)>0 else "Общественное место занятий"],"actions":rows})
	for item in COLLECTIONS:
		result.collections.append({"id":item,"name":COLLECTIONS[item],"details":["Выставлено в библиотеке" if collections.has(item) else "Ещё не найдено и не передано", "В личном рюкзаке: "+str(game._inventory(role).get(item,0))],"actions":[]})
	var p:Dictionary=_person(role)
	for spell in SPELLS:
		var rows:Array=[]
		if not p.spells.has(spell): rows.append(_action(role,"learn_spell","Пройти урок · %d монет"%int(SPELLS[spell].lesson_cost),{"spell_id":spell}))
		elif spell=="heal":
			for member in game._roles(): rows.append(_action(role,"cast","Исцелить: "+str(game._hero(member).display_name),{"spell_id":spell,"target_id":member}))
		else: rows.append(_action(role,"cast","Применить",{"spell_id":spell}))
		result.magic.append({"id":spell,"name":SPELLS[spell].name,"details":[SPELLS[spell].details,"Силы: %d/100 · затраты %d"%[int(p.mana),int(SPELLS[spell].cost)],"Изучено" if p.spells.has(spell) else "Требуется урок в академии"],"actions":rows})
	return result

func snapshot()->Dictionary:
	return {"version":1,"sites":sites.duplicate(true),"people":people.duplicate(true),"collections":collections.duplicate(true),"clock":_clock,"requests":_requests.duplicate(true)}

func valid_snapshot(data:Variant)->bool:
	if not data is Dictionary or int(data.get("version",0))!=1: return false
	if not data.get("sites") is Dictionary or not data.get("people") is Dictionary or not data.get("collections") is Dictionary: return false
	if not game._number(data.get("clock")) or not data.get("requests",{}) is Dictionary: return false
	if not game.life.sim._finite_tree(data): return false
	for value in data.get("requests",{}).values():
		if not value is Dictionary or not value.get("ok") is bool or not value.get("message") is String or not game._number(value.get("xp",0)): return false
	for id in data.sites:
		var s=data.sites[id]
		if not sites.has(id) or not s is Dictionary or not game._valid_vector(s.get("position")) or int(s.get("stock",-1))<0 or int(s.get("stock",0))>int(s.get("capacity",0)): return false
		if not s.get("refill") is float and not s.get("refill") is int: return false
		if not game._number(s.get("count")) or int(s.count)<0 or int(s.get("capacity",-1))!=int(sites[id].capacity): return false
	for role in data.people:
		var p=data.people[role]
		if not p is Dictionary or not p.get("spells") is Array or not p.get("cooldowns") is Dictionary or not game._number(p.get("mana")): return false
		if float(p.mana)<0 or float(p.mana)>100: return false
		for spell in p.spells:
			if not SPELLS.has(spell): return false
		for spell in p.cooldowns:
			if not SPELLS.has(spell) or not game._number(p.cooldowns[spell]): return false
		for key in ["ward_until","light_until","perform_until","fish_caught","finds","paintings"]:
			if not game._number(p.get(key)): return false
	return true

func restore(data:Dictionary)->void:
	claims.clear(); _requests.clear()
	for light in _lights.values():
		if is_instance_valid(light): light.queue_free()
	_lights.clear()
	if data.is_empty():
		people.clear(); collections.clear(); _clock=float(game.life.sim.clock)
		for s in sites.values(): s.stock=int(s.capacity); s.refill=_clock+1440; s.count=0
		return
	if not valid_snapshot(data): return
	people=data.people.duplicate(true); collections=data.collections.duplicate(true); _requests=data.get("requests",{}).duplicate(true); _clock=float(data.clock)
	for id in data.sites:
		for key in ["stock","refill","count"]: sites[id][key]=data.sites[id][key]
