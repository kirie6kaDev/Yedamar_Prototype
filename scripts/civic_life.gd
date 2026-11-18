extends RefCounted
## Local municipal progression and personal psychology. No scene/network ownership.
const Catalog=preload("res://scripts/civic_catalog.gd")
var sim
var houses:Dictionary={}
var people:Dictionary={}
var clubs:Dictionary={}
var events:Array=[]
var clock:float=0.0
var _context:Dictionary={}
var _processed:Dictionary={}
var _requests:Dictionary={}
var _next_id:int=1
var _configured:bool=false


func configure(life_sim,options:Dictionary={})->void:
	if _configured: return
	_configured=true; sim=life_sim; clock=float(sim.clock)
	for id:String in sim.households:
		houses[id]=_new_house(id)
		if id!="house_player": houses[id].rank=2; _import_deeds(id)
		elif bool(options.get("legacy",false)): _import_deeds(id)
		else: sim.households[id].properties.erase("life_player_home")
	sync()


func _new_house(id:String)->Dictionary:
	return {"id":id,"rank":0,"reputation":0.0,"work_minutes":0.0,"guild_xp":0.0,"errands":0,"since":clock,"certificates":[],"petition":{},"permits":{},"deeds":{},"shelter":"life_player_home" if id=="house_player" else "","licences":{},"tax_invoices":[],"next_tax":clock+10080,"loan":{},"fines":[],"public_insults":[],"legacy":false,"house_name":"","crest":"","heir_id":"","last_inheritance":-1.0}


func _new_person(id:String)->Dictionary:
	return {"id":id,"satisfaction":0,"wishes":[],"wish_history":[],"next_wishes":clock,"fears":{},"effects":[],"emotion":"fine","emotion_strength":0.0,"sentiments":{},"errands":{},"errand_days":{},"apprenticeship":{},"diplomas":{},"last_lesson_day":-1,"lessons_today":0,"exam_after":0.0,"unsafe_minutes":0.0,"lonely_minutes":0.0,"last_meeting":{},"club_ids":[],"calm_after":0.0}


func _import_deeds(house_id:String)->void:
	var record:Dictionary=houses[house_id]; record.legacy=true
	for id:String in sim.households[house_id].properties:
		record.deeds[id]={"kind":"home","legacy":true,"issued":clock,"actor_id":""}
	for id:String in sim.businesses:
		if str(sim.businesses[id].owner)==house_id: record.deeds[id]={"kind":"business","legacy":true,"issued":clock,"actor_id":""}


func sync(context:Dictionary={})->void:
	if not context.is_empty(): _context=context.duplicate(true)
	for id:String in sim.households:
		if not houses.has(id): houses[id]=_new_house(id)
	for id:String in sim.residents:
		if not people.has(id): people[id]=_new_person(id)


func _now()->float:
	return float(sim.clock)


func _house(actor:String)->Dictionary:
	return houses.get(str(sim.residents.get(actor,{}).get("household_id","")),{})


func _controlled(actor:String,issuer:String)->bool:
	return sim.residents.has(actor) and str(sim.controllers.get(issuer,""))==str(sim.residents[actor].household_id)


func _adult(actor:String)->bool:
	return sim.residents.has(actor) and bool(sim.residents[actor].alive) and float(sim.residents[actor].age_years)>=18


func _vec(value)->Vector3:
	if value is Vector3: return value
	if value is Array and value.size()==3: return Vector3(float(value[0]),float(value[1]),float(value[2]))
	return Vector3.ZERO


func _distance(a:Vector3,b:Vector3)->float:
	return Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))


func _property_kind(id:String)->String:
	if not sim.venues.has(id): return ""
	if str(sim.venues[id].get("kind","")) in ["home","plot"]: return "home"
	if sim.businesses.has(id): return "business"
	return ""


func can_use_shelter(actor:String,home_id:String)->bool:
	return not _house(actor).is_empty() and str(_house(actor).shelter)==home_id


func before_action(actor:String,action:String,payload:Dictionary={},_spec:Dictionary={})->String:
	if not sim.residents.has(actor): return "Житель недоступен."
	if not houses.has(str(sim.residents[actor].household_id)): return ""
	if action not in ["buy_home","buy_workshop"]: return ""
	if not _adult(actor): return "Приобретать землю и предприятия может взрослый заявитель."
	var id:String=str(payload.get("home_id","") if action=="buy_home" else payload.get("business_id",""))
	var house:Dictionary=_house(actor)
	if Catalog.PUBLIC_ONLY.has(id): return "Это общественное место или временный приют; оно не продаётся."
	var kind:String=_property_kind(id)
	if kind.is_empty(): return "Неизвестный участок или предприятие."
	var required:int=2 if kind=="home" else 3
	if int(house.rank)<required: return "Нужен статус «"+str(Catalog.RANKS[required].name)+"», заслуженный трудом и службой."
	if _overdue(house)>0: return "Сначала урегулируйте просроченные обязательства в ратуше."
	var permit:Dictionary=house.permits.get(id,{})
	if permit.is_empty() or str(permit.get("actor_id",""))!=actor or bool(permit.get("used",false)) or float(permit.get("expires",0))<_now(): return "Нужно действующее именное разрешение ратуши именно на этот участок."
	return ""


func grant_build_license(actor:String,license_id:String,position:Vector3,size:Vector2,kinds:Array,source:String="Разрешение хозяина")->bool:
	if _house(actor).is_empty() or license_id.is_empty() or not position.is_finite() or size.x<=0 or size.y<=0: return false
	_house(actor).licences[license_id]={"id":license_id,"position":[position.x,position.y,position.z],"size":[size.x,size.y],"kinds":kinds.duplicate(),"source":source}
	return true


func can_build(actor:String,position:Vector3,kind:String="")->String:
	var house:Dictionary=_house(actor)
	if house.is_empty(): return "Сначала зарегистрируйте хозяйство."
	for id:String in house.deeds:
		if not sim.venues.has(id) or not _owns_deed(house,id): continue
		if _inside(position,sim.venues[id]): return ""
	for licence:Dictionary in house.licences.values():
		if licence.kinds.has(kind) and _inside(position,licence): return ""
	return "Стройка требует принадлежащего семье участка или отдельного разрешения хозяина на этот вид работ."


func land_access(actor:String,position:Vector3)->String:
	return can_build(actor,position,"")


func _inside(point:Vector3,venue:Dictionary)->bool:
	var center:Vector3=_vec(venue.get("center",venue.get("position",[])))
	if venue.get("size") is Array and venue["size"].size()==2:
		return absf(point.x-center.x)<=float(venue["size"][0])*.5 and absf(point.z-center.z)<=float(venue["size"][1])*.5
	return _distance(point,center)<=float(venue.get("build_radius",20.0))


func _owns_deed(house:Dictionary,id:String)->bool:
	return sim.households[house.id].properties.has(id) or sim.businesses.has(id) and sim.businesses[id].owner==house.id


func _rank_reason(actor:String,next_rank:int)->String:
	if next_rank<=0 or next_rank>=Catalog.RANKS.size(): return "Следующего статуса в прототипе пока нет."
	var h:Dictionary=_house(actor); var requirement:Dictionary=Catalog.RANKS[next_rank]
	var missing:PackedStringArray=[]
	if float(h.work_minutes)<float(requirement.work): missing.append("труд %.0f/%.0f мин" % [h.work_minutes,requirement.work])
	if float(h.reputation)<float(requirement.reputation): missing.append("доверие %.0f/%.0f" % [h.reputation,requirement.reputation])
	if float(h.guild_xp)<float(requirement.guild): missing.append("гильдейский опыт %.0f/%.0f" % [h.guild_xp,requirement.guild])
	if int(h.errands)<int(requirement.errands): missing.append("поручения %d/%d" % [h.errands,requirement.errands])
	if int(requirement.days)>0 and _now()-float(h.since)<int(requirement.days)*1440: missing.append("не менее %d дней службы" % int(requirement.days))
	if bool(requirement.diploma):
		var has_diploma:bool=false
		for member:String in sim.households[h.id].members:
			if people.has(member) and not people[member].diplomas.is_empty(): has_diploma=true
		if not has_diploma: missing.append("диплом мастера у члена семьи")
	if _overdue(h)>0: missing.append("погасить просроченные обязательства")
	return "Осталось: "+"; ".join(missing) if not missing.is_empty() else ""


func command_spec(actor:String,action:String,payload:Dictionary={})->Dictionary:
	var spec:Dictionary={"ok":false,"reason":"","target":Vector3.ZERO,"venue_id":"","duration":0.0,"animation":"interact","portable":false}
	if not sim.residents.has(actor) or not people.has(actor) or not bool(sim.residents[actor].alive): spec.reason="Житель недоступен."; return spec
	if not Catalog.ACTIONS.has(action) or not _safe_data(payload): spec.reason="Неизвестная или повреждённая команда."; return spec
	var p:Dictionary=sim.residents[actor]; var person:Dictionary=people[actor]; var h:Dictionary=_house(actor)
	var definition:Dictionary=Catalog.ACTIONS[action]
	spec.duration=float(definition.duration); spec.portable=bool(definition.get("portable",false)); spec.target=sim.position_of(actor)
	var venue:String=str(definition.get("venue",""))
	if action=="deliver_errand": venue=str(Catalog.ERRANDS.get(str(payload.get("errand_id","")),{}).get("venue","life_town_hall"))
	if action=="calm_fear": venue=str(p.home_id)
	if action=="gather_club": venue=str(clubs.get(str(payload.get("club_id","")),{}).get("venue_id","life_guild"))
	if action=="invite_club":
		var target:String=str(payload.get("target_id",""))
		if not sim.residents.has(target) or target==actor or not bool(sim.residents[target].alive): spec.reason="Нужен другой живой житель."; return spec
		spec.target=sim.position_of(target); spec.venue_id="person:"+target
	elif not spec.portable:
		if not sim.venues.has(venue): spec.reason="Место действия недоступно."; return spec
		spec.venue_id=venue; spec.target=_vec(sim.venues[venue].position)
	if action not in ["calm_fear","reward","dismiss_wish","lesson","gather_club"] and not _adult(actor): spec.reason="Этим вопросом занимается взрослый член хозяйства."; return spec
	match action:
		"petition":
			if not h.petition.is_empty(): spec.reason="Прошение уже подано. Дождитесь решения."; return spec
			spec.reason=_rank_reason(actor,int(h.rank)+1)
		"collect_status":
			if h.petition.is_empty(): spec.reason="Сначала подайте прошение."; return spec
			if _now()<float(h.petition.due): spec.reason="Рассмотрение: ещё %d игровых минут." % ceili(float(h.petition.due)-_now()); return spec
			spec.reason=_rank_reason(actor,int(h.petition.rank))
		"permit":
			var property_id:String=str(payload.get("property_id","")); var kind:String=_property_kind(property_id)
			if kind.is_empty() or Catalog.PUBLIC_ONLY.has(property_id): spec.reason="Этот объект не предоставляется в частную собственность."; return spec
			var required:int=2 if kind=="home" else 3
			if int(h.rank)<required: spec.reason="Нужно свидетельство статуса «"+Catalog.RANKS[required].name+"»."; return spec
			if _property_owner(property_id)!="": spec.reason="Участок уже принадлежит другому хозяйству."; return spec
			if _overdue(h)>0: spec.reason="Просроченные обязательства мешают выдаче нового разрешения."; return spec
			var permit:Dictionary=h.permits.get(property_id,{})
			if not permit.is_empty() and not bool(permit.used) and float(permit.expires)>=_now(): spec.reason="Действующее разрешение на этот участок уже выдано."; return spec
			if int(sim.households[h.id].coins)<_permit_fee(kind): spec.reason="Сбор за оформление: %d монет." % _permit_fee(kind); return spec
		"accept_errand":
			var errand:String=str(payload.get("errand_id",""))
			if not Catalog.ERRANDS.has(errand): spec.reason="Неизвестное поручение."; return spec
			if person.errands.has(errand) or int(person.errand_days.get(errand,-1))==_day(): spec.reason="Это поручение уже взято или выполнено сегодня."; return spec
			if person.errands.size()>=2: spec.reason="Сначала закончите одно из двух текущих поручений."; return spec
		"deliver_errand":
			var errand:String=str(payload.get("errand_id",""))
			if not person.errands.has(errand): spec.reason="Сначала возьмите это поручение."; return spec
			var task:Dictionary=Catalog.ERRANDS[errand]
			if float(person.errands[errand].work)<float(task.work): spec.reason="Нужны рабочие часы после получения поручения: %.0f/%.0f мин." % [person.errands[errand].work,task.work]; return spec
			for item:String in task.items:
				if int(p.inventory.get(item,0))<int(task.items[item]): spec.reason="В личном рюкзаке не хватает: "+_item_name(item); return spec
		"apprentice":
			if int(h.rank)<1: spec.reason="Сначала получите статус Вольного жителя."; return spec
			var profession:String=str(payload.get("profession_id",""))
			if not sim.professions.has(profession): spec.reason="Выберите профессию."; return spec
			if not person.apprenticeship.is_empty(): spec.reason="Сначала завершите текущее ученичество."; return spec
			if person.diplomas.has(profession): spec.reason="Эта квалификация уже подтверждена."; return spec
		"lesson":
			if person.apprenticeship.is_empty(): spec.reason="Сначала запишитесь в ученики."; return spec
			if int(person.last_lesson_day)==_day() and int(person.lessons_today)>=3: spec.reason="На сегодня занятия закончены."; return spec
		"exam":
			if person.apprenticeship.is_empty(): spec.reason="Нет текущего ученичества."; return spec
			var training:Dictionary=person.apprenticeship
			if int(training.lessons)<3 or float(training.practice)<180: spec.reason="Для экзамена нужны три занятия и три часа практики по профессии."; return spec
			if _now()<float(person.exam_after): spec.reason="Повторный экзамен можно сдавать на следующий день."; return spec
			if float(p.needs.energy)<25 or float(p.needs.hunger)<20: spec.reason="Перед экзаменом нужны отдых и еда."; return spec
		"pay_tax":
			var amount:int=_tax_total(h)
			if amount<=0: spec.reason="Неоплаченных имущественных сборов нет."; return spec
			if int(sim.households[h.id].coins)<amount: spec.reason="Для оплаты требуется %d монет." % amount; return spec
		"take_loan":
			if int(h.rank)<1: spec.reason="Городской заём доступен зарегистрированному Вольному жителю."; return spec
			if not h.loan.is_empty() or _overdue(h)>0: spec.reason="Сначала погасите прежние обязательства."; return spec
			if int(sim.market.treasury)<40: spec.reason="В городской кассе сейчас нет средств."; return spec
		"repay_loan":
			if h.loan.is_empty(): spec.reason="Открытого займа нет."; return spec
			if int(sim.households[h.id].coins)<int(h.loan.total): spec.reason="Нужно вернуть %d монет." % int(h.loan.total); return spec
		"pay_fine","appeal_fine":
			var fine:Dictionary=_find_fine(h,str(payload.get("fine_id","")))
			if fine.is_empty() or bool(fine.paid) or bool(fine.dismissed): spec.reason="Неоплаченного штрафа с этим номером нет."; return spec
			if action=="pay_fine" and int(sim.households[h.id].coins)<int(fine.amount): spec.reason="Недостаточно средств на штраф."; return spec
			if action=="appeal_fine" and bool(fine.appealed): spec.reason="Это обращение уже рассмотрено."; return spec
		"calm_fear":
			if not person.fears.has(str(payload.get("fear_id",""))): spec.reason="Этот страх сейчас не активен."; return spec
			if _context.get("unsafe_actors",[]).has(actor) or _context.get("threat_actors",[]).has(actor): spec.reason="Сначала вернитесь в безопасное место."; return spec
			if _now()<float(person.calm_after): spec.reason="Дайте себе время закрепить спокойствие."; return spec
		"reward":
			var reward:String=str(payload.get("reward_id",""))
			if not Catalog.REWARDS.has(reward): spec.reason="Неизвестная награда."; return spec
			if int(person.satisfaction)<int(Catalog.REWARDS[reward].cost): spec.reason="Недостаточно очков удовлетворённости."; return spec
		"dismiss_wish":
			if _find_wish(person,str(payload.get("wish_id",""))).is_empty(): spec.reason="Это желание уже завершено."; return spec
		"found_club":
			if int(h.rank)<3: spec.reason="Основать городское объединение может Почётный гражданин."; return spec
			if str(payload.get("name","")).strip_edges().is_empty() or str(payload.get("name","")).length()>48: spec.reason="Название: от 1 до 48 знаков."; return spec
			if not Catalog.CLUB_ACTIVITIES.has(str(payload.get("activity",""))): spec.reason="Выберите чтение, тренировку или общение."; return spec
			if not person.club_ids.is_empty(): spec.reason="В прототипе можно состоять в одном объединении."; return spec
		"invite_club","gather_club":
			var club:Dictionary=clubs.get(str(payload.get("club_id","")),{})
			if club.is_empty() or str(club.leader)!=actor: spec.reason="Это действие доступно руководителю объединения."; return spec
			if action=="invite_club":
				var target:String=str(payload.get("target_id",""))
				if not _adult(target) or club.members.has(target) or club.members.size()>=6 or not people[target].club_ids.is_empty(): spec.reason="Нужен взрослый свободный участник; в объединении до шести мест."; return spec
				if float(p.relationships.get(target,{}).get("friendship",0))<20: spec.reason="Сначала познакомьтесь и подружитесь."; return spec
			else:
				if club.members.size()<2: spec.reason="Сначала пригласите хотя бы одного участника."; return spec
				if _now()<float(club.next_gathering): spec.reason="Следующая встреча возможна через несколько часов."; return spec
		"name_house","name_heir":
			if int(h.rank)<4: spec.reason="Родовой титул оформляется после признания дворянского статуса."; return spec
			if action=="name_house" and (str(payload.get("name","")).strip_edges().is_empty() or str(payload.get("name","")).length()>48 or str(payload.get("crest","")).length()>32): spec.reason="Название рода до 48 знаков, описание знака до 32."; return spec
			if action=="name_heir":
				var heir:String=str(payload.get("target_id",""))
				if not sim.residents.has(heir) or not sim.residents[heir].alive or sim.residents[heir].household_id!=p.household_id or heir==actor: spec.reason="Наследник должен быть другим живым членом вашего хозяйства."; return spec
	if not str(spec.reason).is_empty(): return spec
	spec.ok=true
	return spec


func command(actor:String,action:String,payload:Dictionary={},issuer:String="local")->Dictionary:
	if not _controlled(actor,issuer): return {"ok":false,"message":"Нет права управлять этим хозяйством."}
	var key:String=issuer+":"+str(payload.get("request_id",""))
	if payload.has("request_id") and _requests.has(key): return _requests[key].duplicate(true)
	var spec:Dictionary=command_spec(actor,action,payload)
	if not spec.ok: return {"ok":false,"message":spec.reason}
	if not spec.portable and _distance(sim.position_of(actor),spec.target)>2.2: return {"ok":false,"message":"Сначала подойдите к месту оформления или занятия."}
	var result:Dictionary=_complete(actor,action,payload)
	if bool(result.get("ok",false)) and payload.has("request_id"):
		_requests[key]=result.duplicate(true)
		if _requests.size()>512: _requests.erase(_requests.keys()[0])
	return result


func snapshot()->Dictionary:
	return {"version":1,"houses":houses.duplicate(true),"people":people.duplicate(true),"clubs":clubs.duplicate(true),"events":events.duplicate(true),"clock":clock,"next_id":_next_id,"processed":_processed.duplicate(true),"requests":_requests.duplicate(true)}


func valid_snapshot(data:Dictionary)->bool:
	if not _safe_data(data) or int(data.get("version",0))!=1: return false
	for field:String in ["houses","people","clubs","processed","requests"]:
		if not data.get(field) is Dictionary: return false
	if not data.get("events") is Array or not _number(data.get("clock")) or not _number(data.get("next_id")): return false
	if data.houses.size()>128 or data.people.size()>256 or data.clubs.size()>64 or data.requests.size()>512 or data.processed.size()>1024: return false
	if not data.houses.has("house_player"): return false
	for id:String in data.houses:
		var h=data.houses[id]
		if not h is Dictionary or not sim.households.has(id) or str(h.get("id",""))!=id: return false
		for key:String in ["rank","reputation","work_minutes","guild_xp","errands","since","next_tax","last_inheritance"]:
			if not _number(h.get(key)): return false
		if int(h.rank)<0 or int(h.rank)>=Catalog.RANKS.size() or float(h.work_minutes)<0 or float(h.guild_xp)<0 or int(h.errands)<0: return false
		for key:String in ["shelter","house_name","crest","heir_id"]:
			if not h.get(key) is String: return false
		for key:String in ["petition","permits","deeds","licences","loan"]:
			if not h.get(key) is Dictionary: return false
		for key:String in ["certificates","tax_invoices","fines","public_insults"]:
			if not h.get(key) is Array: return false
		if not h.petition.is_empty():
			if not _number(h.petition.get("rank")) or not _number(h.petition.get("due")) or not h.petition.get("actor_id") is String: return false
			if int(h.petition.rank)!=int(h.rank)+1 or int(h.petition.rank)>=Catalog.RANKS.size(): return false
		for permit in h.permits.values():
			if not permit is Dictionary: return false
			for key:String in ["id","property_id","actor_id","kind"]:
				if not permit.get(key) is String: return false
			for key:String in ["issued","expires","fee"]:
				if not _number(permit.get(key)): return false
			if not permit.get("used") is bool: return false
		for property:String in h.deeds:
			var deed=h.deeds[property]
			if not deed is Dictionary or not deed.get("legacy") is bool or not _number(deed.get("issued")) or not deed.get("actor_id") is String: return false
			if deed.get("kind","") not in ["home","business"] or not sim.venues.has(property): return false
		for licence in h.licences.values():
			if not licence is Dictionary or not _vector_valid(licence.get("position")) or not licence.get("size") is Array or licence["size"].size()!=2 or not licence.get("kinds") is Array: return false
			if not _number(licence["size"][0]) or not _number(licence["size"][1]): return false
		for invoice in h.tax_invoices:
			if not invoice is Dictionary or not invoice.get("id") is String or not invoice.get("paid") is bool: return false
			for key:String in ["amount","issued","due"]:
				if not _number(invoice.get(key)) or float(invoice[key])<0: return false
		if not h.loan.is_empty():
			for key:String in ["principal","fee","total","issued","due"]:
				if not _number(h.loan.get(key)) or float(h.loan[key])<0: return false
		for fine in h.fines:
			if not fine is Dictionary: return false
			for key:String in ["id","actor_id","reason","decision"]:
				if not fine.get(key) is String: return false
			for key:String in ["amount","issued","due"]:
				if not _number(fine.get(key)) or float(fine[key])<0: return false
			for key:String in ["paid","dismissed","appealed"]:
				if not fine.get(key) is bool: return false
		for offence in h.public_insults:
			if not offence is Dictionary or not _number(offence.get("time")): return false
	for id:String in data.people:
		var p=data.people[id]
		if not p is Dictionary or str(p.get("id",""))!=id or not sim.residents.has(id): return false
		for key:String in ["satisfaction","next_wishes","emotion_strength","last_lesson_day","lessons_today","exam_after","unsafe_minutes","lonely_minutes","calm_after"]:
			if not _number(p.get(key)): return false
		if int(p.satisfaction)<0 or not Catalog.EMOTIONS.has(str(p.get("emotion",""))): return false
		for key:String in ["wishes","wish_history","effects","club_ids"]:
			if not p.get(key) is Array: return false
		for key:String in ["fears","sentiments","errands","errand_days","apprenticeship","diplomas","last_meeting"]:
			if not p.get(key) is Dictionary: return false
		for wish in p.wishes:
			if not wish is Dictionary or not wish.get("id") is String or not wish.get("name") is String or not Catalog.WISHES.has(str(wish.get("kind",""))): return false
			for key:String in ["progress","target","reward","created","expires"]:
				if not _number(wish.get(key)) or float(wish[key])<0: return false
		for entry in p.wish_history:
			if not entry is Dictionary or not Catalog.WISHES.has(str(entry.get("kind",""))) or not _number(entry.get("completed")): return false
		for effect in p.effects:
			if not effect is Dictionary or not Catalog.EMOTIONS.has(str(effect.get("emotion",""))) or not _number(effect.get("strength")) or not _number(effect.get("expires")): return false
		for kind:String in p.fears:
			if not Catalog.FEARS.has(kind) or not p.fears[kind] is Dictionary: return false
			for key:String in ["intensity","created","next_effect"]:
				if not _number(p.fears[kind].get(key)): return false
		for sentiment in p.sentiments.values():
			if not sentiment is Dictionary or not sentiment.get("target_id") is String or not sentiment.get("kind") is String: return false
			for key:String in ["strength","created","expires"]:
				if not _number(sentiment.get(key)): return false
		for task:String in p.errands:
			if not Catalog.ERRANDS.has(task) or not p.errands[task] is Dictionary or not _number(p.errands[task].get("work")) or not _number(p.errands[task].get("accepted")): return false
		if not p.apprenticeship.is_empty():
			if not sim.professions.has(str(p.apprenticeship.get("profession",""))) or not _number(p.apprenticeship.get("lessons")) or not _number(p.apprenticeship.get("practice")): return false
		for job:String in p.diplomas:
			if not sim.professions.has(job) or not p.diplomas[job] is Dictionary or not _number(p.diplomas[job].get("grade")) or not _number(p.diplomas[job].get("issued")): return false
	for id:String in data.clubs:
		var club=data.clubs[id]
		if not club is Dictionary or not club.get("members") is Array or not club.get("active") is Dictionary: return false
		for key:String in ["id","name","activity","leader","venue_id"]:
			if not club.get(key) is String: return false
		if not Catalog.CLUB_ACTIVITIES.has(club.activity) or not sim.venues.has(club.venue_id): return false
		for key:String in ["points","gatherings","next_gathering"]:
			if not _number(club.get(key)): return false
		if not club.active.is_empty() and (not _number(club.active.get("until")) or not club.active.get("awarded") is bool): return false
	for entry in data.requests.values():
		if not entry is Dictionary or not entry.get("ok") is bool or not entry.get("message") is String: return false
	return true


func restore(data:Dictionary)->bool:
	if not valid_snapshot(data): return false
	houses=data.houses.duplicate(true); people=data.people.duplicate(true); clubs=data.clubs.duplicate(true); events=data.events.duplicate(true)
	clock=float(data.clock); _next_id=int(data.next_id); _processed=data.processed.duplicate(true); _requests=data.requests.duplicate(true)
	for id:String in houses:
		var h:Dictionary=houses[id]
		# configure(new) removes the provisional starter title. A genuine V4 deed
		# recorded during migration is the only reason to restore that legacy title.
		if h.deeds.has("life_player_home") and h.deeds.life_player_home.legacy and not sim.households[id].properties.has("life_player_home"): sim.households[id].properties.append("life_player_home")
	return true


func _number(value:Variant)->bool:
	return (value is float or value is int) and is_finite(float(value))


func _vector_valid(value:Variant)->bool:
	return value is Array and value.size()==3 and _number(value[0]) and _number(value[1]) and _number(value[2])


func _safe_data(value:Variant)->bool:
	if value is float: return is_finite(value)
	if value is Dictionary:
		for key in value:
			if not (key is String or key is StringName) or not _safe_data(value[key]): return false
	elif value is Array:
		for entry in value:
			if not _safe_data(entry): return false
	elif not (value is String or value is StringName or value is int or value is bool or value==null): return false
	return true


func _complete(actor:String,action:String,payload:Dictionary)->Dictionary:
	var p:Dictionary=sim.residents[actor]; var person:Dictionary=people[actor]; var h:Dictionary=_house(actor)
	var message:String=str(Catalog.ACTIONS[action].name)+" — готово."
	match action:
		"petition":
			h.petition={"rank":int(h.rank)+1,"actor_id":actor,"submitted":_now(),"due":_now()+60}
			message="Прошение принято. Через час заберите свидетельство в ратуше; заслуги будут проверены повторно."
		"collect_status":
			h.rank=int(h.petition.rank); h.certificates.append({"rank":h.rank,"actor_id":actor,"issued":_now()}); h.petition={}
			if int(h.rank)==4: h["title_holder"]=actor
			_remember(actor,"status","Получен статус: "+Catalog.RANKS[h.rank].name); _emotion(actor,"confident",12,360,"status")
			_event("Статус хозяйства: "+Catalog.RANKS[h.rank].name,[actor]); message="Выдано свидетельство: "+Catalog.RANKS[h.rank].name+". Оно не заменяет разрешение на конкретный участок."
		"permit":
			var id:String=str(payload.property_id); var kind:String=_property_kind(id); var fee:int=_permit_fee(kind)
			_charge(h.id,fee)
			h.permits[id]={"id":_id("permit"),"property_id":id,"actor_id":actor,"kind":kind,"issued":_now(),"expires":_now()+10080,"used":false,"fee":fee}
			message="Именное разрешение выдано на «"+str(sim.venues[id].name)+"». Действует семь дней; покупка оплачивается отдельно."
		"accept_errand":
			var id:String=str(payload.errand_id)
			person.errands[id]={"accepted":_now(),"work":0.0}; message="Принято: "+Catalog.ERRANDS[id].name+". Требуются ваши припасы или работа после принятия."
		"deliver_errand":
			var id:String=str(payload.errand_id); var task:Dictionary=Catalog.ERRANDS[id]
			for item:String in task.items: p.inventory[item]=int(p.inventory[item])-int(task.items[item])
			person.errands.erase(id); person.errand_days[id]=_day()
			h.errands=int(h.errands)+1; h.reputation=float(h.reputation)+float(task.reputation); h.guild_xp=float(h.guild_xp)+float(task.guild)
			_credit(h.id,int(task.reward)); _emotion(actor,"confident",7,180,"service"); _progress_wishes(actor,"deliver_errand")
			message="Поручение выполнено: +%d доверия, +%d гильдейского опыта, %d монет семье." % [task.reputation,task.guild,task.reward]
		"apprentice":
			var job:String=str(payload.profession_id)
			person.apprenticeship={"profession":job,"lessons":0,"practice":0.0,"started":_now()}
			message="Ученичество: "+str(sim.professions[job].name)+". Нужны три занятия и три часа практики именно по этой профессии."
		"lesson":
			if int(person.last_lesson_day)!=_day(): person.last_lesson_day=_day(); person.lessons_today=0
			person.lessons_today=int(person.lessons_today)+1; person.apprenticeship.lessons=int(person.apprenticeship.lessons)+1
			var job:String=str(person.apprenticeship.profession)
			sim._skill(actor,str(sim.professions[job].skill),8); h.guild_xp=float(h.guild_xp)+4
			_emotion(actor,"focused",8,240,"lesson"); _progress_wishes(actor,"lesson")
			message="Занятие завершено. Практику проходите оплачиваемой работой у профильного станка."
		"exam":
			var training:Dictionary=person.apprenticeship; var job:String=str(training.profession)
			var experience:float=float(p.skills.get(str(sim.professions[job].skill),0))
			var grade:int=clampi(roundi(40+experience*.25+float(training.practice)/30+float(p.needs.energy)*.15+(minf(0,float(p.mood))*.25)),0,100)
			person.exam_after=_now()+1440
			if grade>=60:
				person.diplomas[job]={"profession":job,"grade":grade,"issued":_now()}; person.apprenticeship={}
				h.guild_xp=float(h.guild_xp)+30; h.reputation=float(h.reputation)+12
				person.fears.erase("failure"); _emotion(actor,"confident",14,480,"diploma"); _remember(actor,"diploma","Получен диплом: "+str(sim.professions[job].name))
				message="Экзамен сдан: %d/100. Диплом даёт признание и небольшой дополнительный опыт успешной профильной работы." % grade
			else:
				_add_fear(actor,"failure",35); _emotion(actor,"embarrassed",10,240,"exam")
				message="Экзамен: %d/100, требуется 60. Практика и занятия сохраняются; повтор возможен завтра." % grade
		"pay_tax":
			var amount:int=_tax_total(h); _charge(h.id,amount)
			for invoice:Dictionary in h.tax_invoices: invoice.paid=true
			message="Имущественный сбор оплачен: %d монет." % amount
		"take_loan":
			_credit(h.id,40); h.loan={"principal":40,"fee":4,"total":44,"issued":_now(),"due":_now()+10080}
			message="Выдано 40 монет. Через семь дней вернуть 44; ежедневного сложного процента нет."
		"repay_loan":
			_charge(h.id,int(h.loan.total)); h.loan={}; _reduce_fear(actor,"poverty",40); message="Заём погашен."
		"pay_fine":
			var fine:Dictionary=_find_fine(h,str(payload.fine_id)); _charge(h.id,int(fine.amount)); fine.paid=true; message="Штраф оплачен."
		"appeal_fine":
			var fine:Dictionary=_find_fine(h,str(payload.fine_id)); fine.appealed=true
			if h.fines.size()==1 and float(h.reputation)>=20:
				fine.amount=maxi(1,ceili(float(fine.amount)*.5)); fine.decision="Первое нарушение и подтверждённая служба: взыскание уменьшено вдвое."
			else: fine.decision="Оснований для смягчения нет: нарушение подтверждено повторными публичными оскорблениями."
			message=str(fine.decision)
		"calm_fear":
			var fear:String=str(payload.fear_id); _reduce_fear(actor,fear,40); person.calm_after=_now()+240
			_emotion(actor,"confident",8,180,"coping"); _progress_wishes(actor,"calm_fear"); message="Страх ослаб. Спокойные условия и успешные действия помогут закрепить результат."
		"reward":
			var reward:String=str(payload.reward_id); person.satisfaction=int(person.satisfaction)-int(Catalog.REWARDS[reward].cost)
			if reward=="composure":
				for fear:String in person.fears.keys(): _reduce_fear(actor,fear,25)
				_emotion(actor,"happy",8,240,"reward")
			elif reward=="focus": _emotion(actor,"focused",12,240,"reward")
			else: sim._change_need(actor,"energy",25); _emotion(actor,"energized",8,120,"reward")
			message="Использована награда: "+str(Catalog.REWARDS[reward].name)+"."
		"dismiss_wish":
			var wish:Dictionary=_find_wish(person,str(payload.wish_id)); person.wishes.erase(wish); person.next_wishes=maxf(float(person.next_wishes),_now()+180); message="Желание отпущено без награды."
		"found_club":
			var id:String=_id("club"); var activity:String=str(payload.activity)
			var place:String={"read":"life_library","train":"life_watch","socialize":"life_tavern"}[activity]
			clubs[id]={"id":id,"name":str(payload.name).strip_edges(),"activity":activity,"leader":actor,"members":[actor],"venue_id":place,"points":0,"gatherings":0,"next_gathering":0.0,"active":{}}
			person.club_ids.append(id); message="Создано объединение. Пригласите знакомого и назначьте встречу."
		"invite_club":
			var id:String=str(payload.club_id); var target:String=str(payload.target_id)
			clubs[id].members.append(target); people[target].club_ids.append(id); _sentiment(target,actor,"respect",18)
			message="Житель вступил в объединение."
		"gather_club":
			var club:Dictionary=clubs[str(payload.club_id)]
			club.active={"until":_now()+180,"awarded":false}; club.next_gathering=_now()+240
			for member:String in club.members:
				if member==actor or not sim.residents.has(member) or bool(sim.residents[member].external): continue
				var activity:String="relax" if club.activity=="socialize" else str(club.activity)
				sim.residents[member].queue.append({"action":activity,"payload":{"venue_id":club.venue_id}})
			message="Участники получили приглашение к месту встречи. Общий результат появится, когда минимум двое действительно соберутся."
		"name_house": h.house_name=str(payload.name).strip_edges(); h.crest=str(payload.get("crest","")); message="Название и знак рода записаны в свидетельство."
		"name_heir": h.heir_id=str(payload.target_id); message="Наследник родового титула назначен. Само хозяйство и его вещи остаются общими."
	_refresh_emotion(actor)
	return {"ok":true,"message":message,"action":"civic:"+action,"actor_id":actor}


func after_action(actor:String,action:String,payload:Dictionary,result:Dictionary,_spec:Dictionary={})->void:
	if not bool(result.get("ok",false)) or not sim.residents.has(actor): return
	sync()
	var request:String=str(payload.get("request_id",""))
	if not request.is_empty():
		var key:String=actor+":"+request
		if _processed.has(key): return
		_processed[key]=true
		if _processed.size()>1024: _processed.erase(_processed.keys()[0])
	# Shared psychological results apply to the physical domestic variants too.
	if action=="home:cook": action="cook"
	elif action=="home:eat": action="eat"
	elif action=="home:rest": action="relax"
	var p:Dictionary=sim.residents[actor]; var person:Dictionary=people[actor]; var h:Dictionary=_house(actor)
	if action in ["buy_home","buy_workshop"]:
		var id:String=str(payload.get("home_id","") if action=="buy_home" else payload.get("business_id",""))
		if h.permits.has(id): h.permits[id].used=true
		h.deeds[id]={"kind":"home" if action=="buy_home" else "business","legacy":false,"issued":_now(),"actor_id":actor}
		_remember(actor,"deed","Получена законная собственность: "+str(sim.venues.get(id,{}).get("name",id)))
	if action=="work":
		h.work_minutes=float(h.work_minutes)+60; h.reputation=minf(500,float(h.reputation)+1)
		for task:Dictionary in person.errands.values(): task.work=float(task.work)+60
		if not person.apprenticeship.is_empty() and person.apprenticeship.profession==p.profession:
			person.apprenticeship.practice=float(person.apprenticeship.practice)+60; h.guild_xp=float(h.guild_xp)+6
		if person.diplomas.has(str(p.profession)):
			h.guild_xp=float(h.guild_xp)+2; sim._skill(actor,str(sim.professions[p.profession].skill),2)
		_reduce_fear(actor,"failure",8)
		if str(person.emotion) in ["focused","confident"] and sim.professions.has(str(p.profession)): sim._skill(actor,str(sim.professions[p.profession].skill),2)
	if action in ["read","study","educate"]:
		if str(person.emotion)=="focused": sim._skill(actor,"reading",2)
		_emotion(actor,"focused",7,180,"study")
		if action=="educate": h.reputation=minf(500,float(h.reputation)+.5)
	if action=="cook" or action.begins_with("craft:"):
		if str(person.emotion)=="inspired": sim._skill(actor,"cooking" if action=="cook" else "crafting",2)
		_emotion(actor,"inspired",6,120,"making")
	if action=="train": _emotion(actor,"energized",7,120,"exercise")
	if action in ["socialize","joke","compliment","apologize","flirt","insult","educate","invite_household"]:
		var target:String=str(payload.get("target_id",""))
		if sim.residents.has(target):
			if action=="insult":
				_sentiment(target,actor,"resentment",25); _emotion(target,"angry",10,180,actor); h.reputation=maxf(-100,float(h.reputation)-2); _public_insult(actor,target)
			elif action=="apologize":
				if people[target].sentiments.has(actor): people[target].sentiments[actor].strength=maxf(0,float(people[target].sentiments[actor].strength)-18)
				_emotion(target,"happy",4,120,"reconciliation")
			else:
				_reduce_fear(actor,"isolation",15); _reduce_fear(target,"isolation",15)
				var sentiment:Dictionary=people[target].sentiments.get(actor,{})
				if sentiment.get("kind","")=="resentment" and float(sentiment.strength)>10:
					var relation:Dictionary=sim._relationship(target,actor); relation.friendship=maxf(-100,float(relation.friendship)-2)
				else: _sentiment(target,actor,"gratitude" if action in ["educate","invite_household"] else "warmth",8)
				_emotion(actor,"playful" if action=="joke" else ("flirty" if action=="flirt" else "happy"),7,120,target)
	_progress_wishes(actor,action); _refresh_emotion(actor)


func advance(_minutes:float=0.0)->void:
	if not _configured: return
	sync()
	var elapsed:float=maxf(0,_now()-clock)
	clock=_now()
	for id:String in houses:
		var h:Dictionary=houses[id]
		while clock>=float(h.next_tax):
			var amount:int=0
			for property_id:String in h.deeds:
				if _owns_deed(h,property_id): amount+=5 if h.deeds[property_id].kind=="business" else 2
			if amount>0: h.tax_invoices.append({"id":_id("tax"),"amount":amount,"issued":h.next_tax,"due":float(h.next_tax)+4320,"paid":false})
			h.next_tax=float(h.next_tax)+10080
		var holder:String=str(h.get("title_holder","")); var heir:String=str(h.heir_id)
		if not holder.is_empty() and sim.residents.has(holder) and not sim.residents[holder].alive and sim.residents.has(heir) and sim.residents[heir].alive and sim.residents[heir].household_id==id:
			h.title_holder=heir; h.last_inheritance=clock; _remember(heir,"inheritance","Принят родовой титул "+str(h.house_name)); _event("Титул перешёл назначенному наследнику",[holder,heir])
	for id:String in people:
		if not sim.residents.has(id) or not sim.residents[id].alive: continue
		var p:Dictionary=sim.residents[id]; var person:Dictionary=people[id]
		for index in range(person.effects.size()-1,-1,-1):
			if float(person.effects[index].expires)<=clock: person.effects.remove_at(index)
		for target:String in person.sentiments.keys():
			if float(person.sentiments[target].expires)<=clock: person.sentiments.erase(target)
		for index in range(person.wishes.size()-1,-1,-1):
			if float(person.wishes[index].expires)<=clock: person.wishes.remove_at(index)
		if clock>=float(person.next_wishes): _generate_wishes(id)
		if _context.get("night",false) and _context.get("unsafe_actors",[]).has(id): person.unsafe_minutes=float(person.unsafe_minutes)+elapsed
		else: person.unsafe_minutes=maxf(0,float(person.unsafe_minutes)-elapsed)
		if float(person.unsafe_minutes)>=30 or _context.get("threat_actors",[]).has(id): _add_fear(id,"dark",20)
		if float(p.needs.social)<15: person.lonely_minutes=float(person.lonely_minutes)+elapsed
		else: person.lonely_minutes=maxf(0,float(person.lonely_minutes)-elapsed)
		if float(person.lonely_minutes)>120: _add_fear(id,"isolation",20)
		if _overdue(_house(id))>0: _add_fear(id,"poverty",20)
		elif int(sim.households[p.household_id].coins)>=20: _reduce_fear(id,"poverty",elapsed*.03)
		for target:String in person.sentiments:
			if not sim.residents.has(target) or not sim.residents[target].alive or _distance(sim.position_of(id),sim.position_of(target))>8: continue
			if clock-float(person.last_meeting.get(target,-9999))<180: continue
			person.last_meeting[target]=clock
			var sentiment:Dictionary=person.sentiments[target]
			_emotion(id,"angry" if sentiment.kind=="resentment" else "happy",minf(10,float(sentiment.strength)*.25),90,"meeting:"+target)
		_refresh_emotion(id)
	_tick_clubs()


func _tick_clubs()->void:
	for club:Dictionary in clubs.values():
		if club.active.is_empty(): continue
		if clock>float(club.active.until): club.active={}; continue
		if bool(club.active.awarded): continue
		var here:Array=[]; var point:Vector3=_vec(sim.venues.get(club.venue_id,{}).get("position",[]))
		for member:String in club.members:
			if sim.residents.has(member) and sim.residents[member].alive and _distance(sim.position_of(member),point)<=6: here.append(member)
		if here.size()<2 or not here.has(club.leader): continue
		club.active.awarded=true; club.points=int(club.points)+10; club.gatherings=int(club.gatherings)+1
		for member:String in here:
			_house(member).guild_xp=float(_house(member).guild_xp)+4; sim._change_need(member,"social",20); _emotion(member,"happy",8,180,"club:"+club.id)
			for other:String in here:
				if other!=member: _sentiment(member,other,"shared_time",12)
		_event("Состоялась встреча: "+str(club.name),here)


func _generate_wishes(actor:String)->void:
	var person:Dictionary=people[actor]; var p:Dictionary=sim.residents[actor]
	var choices:Array=[]
	if not person.fears.is_empty(): choices.append("courage")
	if float(p.needs.hunger)<60: choices.append("meal")
	if float(p.needs.social)<60: choices.append("friend")
	if float(p.needs.energy)<45: choices.append("rest")
	if p.traits.has("bookish") or float(p.age_years)<18: choices.append("learn")
	if p.traits.has("outdoors"): choices.append("garden")
	if not str(p.profession).is_empty(): choices.append("work")
	choices.append_array(["friend","learn","cook","service","rest"])
	for kind:String in choices:
		if person.wishes.size()>=3: break
		var exists:bool=false
		for wish:Dictionary in person.wishes:
			if wish.kind==kind: exists=true
		for previous:Dictionary in person.wish_history:
			if previous.kind==kind and _now()-float(previous.completed)<1440: exists=true
		if exists: continue
		var definition:Dictionary=Catalog.WISHES[kind]
		person.wishes.append({"id":_id("wish"),"kind":kind,"name":definition.name,"progress":0,"target":definition.target,"reward":definition.reward,"created":_now(),"expires":_now()+2880})
	person.next_wishes=_now()+240


func _progress_wishes(actor:String,action:String)->void:
	var person:Dictionary=people[actor]
	for index in range(person.wishes.size()-1,-1,-1):
		var wish:Dictionary=person.wishes[index]
		if not Catalog.WISHES[wish.kind].actions.has(action): continue
		wish.progress=int(wish.progress)+1
		if int(wish.progress)<int(wish.target): continue
		person.satisfaction=int(person.satisfaction)+int(wish.reward)
		person.wish_history.append({"kind":wish.kind,"completed":_now()})
		if person.wish_history.size()>30: person.wish_history.pop_front()
		_emotion(actor,"happy",6,120,"wish"); person.wishes.remove_at(index)


func _find_wish(person:Dictionary,id:String)->Dictionary:
	for wish:Dictionary in person.wishes:
		if wish.id==id: return wish
	return {}


func _emotion(actor:String,emotion:String,strength:float,duration:float,source:String)->void:
	if not people.has(actor): return
	var effects:Array=people[actor].effects
	var effect_id:String=emotion+":"+source
	for index in range(effects.size()-1,-1,-1):
		if effects[index].id==effect_id: effects.remove_at(index)
	effects.append({"id":effect_id,"emotion":emotion,"strength":strength,"expires":_now()+duration,"source":source})
	if effects.size()>20: effects.pop_front()
	var negative:bool=emotion in ["sad","angry","tense","uncomfortable","embarrassed","bored","scared"]
	sim._moodlet(actor,"civic:"+effect_id,str(Catalog.EMOTIONS[emotion]),-strength if negative else strength,duration,"civic:"+source)
	_refresh_emotion(actor)


func _refresh_emotion(actor:String)->void:
	var person:Dictionary=people[actor]; var totals:Dictionary={"fine":1.0}
	for effect:Dictionary in person.effects:
		if float(effect.expires)>_now(): totals[effect.emotion]=float(totals.get(effect.emotion,0))+float(effect.strength)
	for fear:Dictionary in person.fears.values(): totals.scared=float(totals.get("scared",0))+float(fear.intensity)*.25
	var needs:Dictionary=sim.residents[actor].needs
	if float(needs.hunger)<20 or float(needs.energy)<20 or float(needs.hygiene)<20: totals.uncomfortable=18.0
	if float(needs.fun)<20: totals.bored=14.0
	var best:String="fine"; var intensity:float=1.0
	for emotion:String in totals:
		if float(totals[emotion])>intensity: best=emotion; intensity=float(totals[emotion])
	person.emotion=best; person.emotion_strength=intensity


func _add_fear(actor:String,kind:String,intensity:float)->void:
	if not people.has(actor) or not Catalog.FEARS.has(kind): return
	var fears:Dictionary=people[actor].fears
	if not fears.has(kind): fears[kind]={"id":kind,"intensity":intensity,"created":_now(),"next_effect":0.0}
	else: fears[kind].intensity=maxf(float(fears[kind].intensity),intensity)
	if _now()>=float(fears[kind].next_effect):
		_emotion(actor,"scared",minf(15,float(fears[kind].intensity)*.25),180,"fear:"+kind); fears[kind].next_effect=_now()+180


func _reduce_fear(actor:String,kind:String,amount:float)->void:
	if not people.has(actor) or not people[actor].fears.has(kind): return
	var fear:Dictionary=people[actor].fears[kind]
	fear.intensity=maxf(0,float(fear.intensity)-amount)
	if float(fear.intensity)<=0: people[actor].fears.erase(kind)


func _sentiment(actor:String,target:String,kind:String,strength:float)->void:
	if not people.has(actor): return
	var previous:Dictionary=people[actor].sentiments.get(target,{})
	var combined:float=strength+float(previous.get("strength",0)) if str(previous.get("kind",""))==kind else strength
	people[actor].sentiments[target]={"target_id":target,"kind":kind,"strength":minf(100,combined),"created":_now(),"expires":_now()+10080}


func _public_insult(actor:String,target:String)->void:
	if sim.residents[actor].household_id==sim.residents[target].household_id: return
	var public_place:bool=false
	for venue:Dictionary in sim.venues.values():
		if str(venue.get("kind","")) not in ["square","market","tavern","town_hall","guild","school"]: continue
		if _distance(sim.position_of(actor),_vec(venue.position))<35: public_place=true; break
	if not public_place: return
	var h:Dictionary=_house(actor)
	for index in range(h.public_insults.size()-1,-1,-1):
		if _now()-float(h.public_insults[index].time)>1440: h.public_insults.remove_at(index)
	h.public_insults.append({"actor_id":actor,"target_id":target,"time":_now()})
	if h.public_insults.size()<3: return
	h.fines.append({"id":_id("fine"),"actor_id":actor,"reason":"Три повторных публичных оскорбления за сутки","evidence":h.public_insults.duplicate(true),"amount":6,"issued":_now(),"due":_now()+4320,"paid":false,"dismissed":false,"appealed":false,"decision":""})
	h.public_insults=[]; _event("Выписан штраф за повторный публичный конфликт",[actor,target])


func _tax_total(house:Dictionary)->int:
	var amount:int=0
	for invoice:Dictionary in house.tax_invoices:
		if not bool(invoice.paid): amount+=int(invoice.amount)
	return amount


func _overdue(house:Dictionary)->int:
	var amount:int=0
	for invoice:Dictionary in house.tax_invoices:
		if not bool(invoice.paid) and _now()>float(invoice.due): amount+=int(invoice.amount)
	for fine:Dictionary in house.fines:
		if not bool(fine.paid) and not bool(fine.dismissed) and _now()>float(fine.due): amount+=int(fine.amount)
	if not house.loan.is_empty() and _now()>float(house.loan.due): amount+=int(house.loan.total)
	return amount


func _find_fine(house:Dictionary,id:String)->Dictionary:
	for fine:Dictionary in house.fines:
		if fine.id==id: return fine
	return {}


func _property_owner(id:String)->String:
	if sim.businesses.has(id) and not str(sim.businesses[id].owner).is_empty(): return str(sim.businesses[id].owner)
	for house:String in sim.households:
		if sim.households[house].properties.has(id): return house
	return ""


func _permit_fee(kind:String)->int:
	return 12 if kind=="home" else 25


func _charge(house_id:String,amount:int)->void:
	sim.households[house_id].coins=int(sim.households[house_id].coins)-amount
	sim.households[house_id].expenses=int(sim.households[house_id].expenses)+amount
	sim.market.treasury=int(sim.market.treasury)+amount


func _credit(house_id:String,amount:int)->void:
	var payment:int=mini(maxi(0,amount),int(sim.market.treasury))
	sim.households[house_id].coins=int(sim.households[house_id].coins)+payment
	sim.households[house_id].income=int(sim.households[house_id].income)+payment
	sim.market.treasury=int(sim.market.treasury)-payment


func _day()->int:
	return floori(_now()/1440)


func _id(prefix:String)->String:
	var id:String=prefix+"_"+str(_next_id); _next_id+=1
	return id


func _item_name(item:String)->String:
	return str(sim.Catalog.GOODS.get(item,{}).get("name",item))


func _remember(actor:String,kind:String,title:String)->void:
	sim._remember(actor,"civic_"+kind,title)


func _event(title:String,actors:Array)->void:
	events.append({"id":_id("event"),"name":title,"time":_now(),"actors":actors.duplicate()})
	if events.size()>60: events.pop_front()


func _row(id:String,name:String,details:Array=[],actions:Array=[])->Dictionary:
	return {"id":id,"name":name,"details":details,"actions":actions}


func _action(actor:String,action:String,payload:Dictionary={},label:String="")->Dictionary:
	var values:Dictionary=payload.duplicate(true); values.actor_id=actor
	var spec:Dictionary=command_spec(actor,action,values)
	var control:bool=_controlled(actor,"local")
	return {"id":"civic:"+action,"label":str(Catalog.ACTIONS[action].name) if label.is_empty() else label,"payload":values,"enabled":control and bool(spec.ok),"reason":str(spec.reason) if control else "Можно управлять только своим хозяйством."}


func ui_rows(actor:String)->Dictionary:
	if not people.has(actor): return {"summary":{},"civic":[],"wishes":[],"fears":[],"sentiments":[],"guilds":[],"emotions":[]}
	var p:Dictionary=sim.residents[actor]; var person:Dictionary=people[actor]; var h:Dictionary=_house(actor)
	var result:Dictionary={"summary":{"rank":h.rank,"rank_name":Catalog.RANKS[int(h.rank)].name,"reputation":h.reputation,"work_minutes":h.work_minutes,"guild_xp":h.guild_xp,"errands":h.errands,"satisfaction":person.satisfaction,"emotion":Catalog.EMOTIONS[person.emotion]},"civic":[],"wishes":[],"fears":[],"sentiments":[],"guilds":[],"emotions":[]}
	result.civic.append(_row("status","Положение: "+str(Catalog.RANKS[int(h.rank)].name),[str(Catalog.RANKS[int(h.rank)].rights),"Подтверждено: труд %.0f ч · доверие %.0f · гильдейский опыт %.0f · поручений %d" % [float(h.work_minutes)/60,h.reputation,h.guild_xp,h.errands],_rank_reason(actor,int(h.rank)+1)],[_action(actor,"petition"),_action(actor,"collect_status")]))
	if not h.petition.is_empty(): result.civic.append(_row("petition","Прошение на рассмотрении",["До решения: %d игровых минут" % maxi(0,ceili(float(h.petition.due)-_now()))],[_action(actor,"collect_status")]))
	result.civic.append(_row("shelter","Временный приют",["Право ночевать и хранить припасы не является собственностью на землю. Старое имущество V4 сохраняет ранее признанные права."],[]))
	for id:String in sim.venues:
		var kind:String=_property_kind(id)
		if kind.is_empty() or Catalog.PUBLIC_ONLY.has(id): continue
		var owner:String=_property_owner(id)
		if not owner.is_empty() and owner!=h.id: continue
		var permit:Dictionary=h.permits.get(id,{})
		var details:Array=["Право покупки: "+str(Catalog.RANKS[2 if kind=="home" else 3].name),"Сбор за оформление: %d монет; цена покупки оплачивается отдельно." % _permit_fee(kind)]
		if h.deeds.has(id): details.append("Ранее признанная собственность V4" if h.deeds[id].legacy else "Приобретено по именному разрешению")
		elif not permit.is_empty(): details.append("Разрешение: "+str(sim.residents.get(permit.actor_id,{}).get("name",permit.actor_id))+" · "+("использовано" if permit.used else "ещё %d мин" % maxi(0,ceili(float(permit.expires)-_now()))))
		result.civic.append(_row("permit:"+id,str(sim.venues[id].name),details,[_action(actor,"permit",{"property_id":id})]))
	for id:String in Catalog.ERRANDS:
		var task:Dictionary=Catalog.ERRANDS[id]; var supplies:PackedStringArray=[]
		for item:String in task.items: supplies.append(_item_name(item)+" ×"+str(task.items[item]))
		var details:Array=["Награда: доверие +%d, гильдейский опыт +%d, %d монет" % [task.reputation,task.guild,task.reward]]
		if not supplies.is_empty(): details.append("Передать из личного рюкзака: "+", ".join(supplies))
		if int(task.work)>0: details.append("Работа после принятия: %.0f / %d мин" % [float(person.errands.get(id,{}).get("work",0)),task.work])
		result.civic.append(_row(id,task.name,details,[_action(actor,"accept_errand",{"errand_id":id}),_action(actor,"deliver_errand",{"errand_id":id})]))
	var debt:Array=["Сбор: 2 монеты за жилую собственность и 5 за предприятие раз в семь дней. Приют без титула не облагается.","Неоплаченные сборы: %d · просрочено всего: %d" % [_tax_total(h),_overdue(h)]]
	if not h.loan.is_empty(): debt.append("Заём: вернуть %d монет · до срока %d мин" % [h.loan.total,maxi(0,ceili(float(h.loan.due)-_now()))])
	result.civic.append(_row("obligations","Сборы и городской заём",debt,[_action(actor,"pay_tax"),_action(actor,"take_loan"),_action(actor,"repay_loan")]))
	result.civic.append(_row("rules","Временное городское положение",["Статус нельзя купить монетами. Разрешение выдаётся конкретному заявителю на конкретный участок.","Три публичных оскорбления за сутки дают штраф 6 монет. Первое взыскание можно смягчить при доверии не ниже 20.","Это игровые правила прототипа, а не единый закон всех государств Йедамара."],[]))
	for fine:Dictionary in h.fines:
		result.civic.append(_row(fine.id,"Штраф: "+str(fine.reason),["Сумма: %d · %s" % [fine.amount,"оплачен" if fine.paid else ("отменён" if fine.dismissed else "ожидает оплаты")],str(fine.decision)],[_action(actor,"pay_fine",{"fine_id":fine.id}),_action(actor,"appeal_fine",{"fine_id":fine.id})]))
	for wish:Dictionary in person.wishes:
		result.wishes.append(_row(wish.id,wish.name,["Прогресс %d/%d · награда %d удовлетворённости" % [wish.progress,wish.target,wish.reward]],[_action(actor,"dismiss_wish",{"wish_id":wish.id})]))
	for kind:String in person.fears:
		result.fears.append(_row(kind,Catalog.FEARS[kind].name,["Сила: %.0f" % person.fears[kind].intensity,Catalog.FEARS[kind].advice],[_action(actor,"calm_fear",{"fear_id":kind})]))
	for target:String in person.sentiments:
		var sentiment:Dictionary=person.sentiments[target]
		var name:String={"resentment":"Обида","gratitude":"Благодарность","respect":"Уважение","warmth":"Тёплое впечатление","shared_time":"Общее воспоминание"}.get(sentiment.kind,sentiment.kind)
		result.sentiments.append(_row(target,name+": "+str(sim.residents.get(target,{}).get("name",target)),["Сила %.0f · влияет на настроение при встрече и следующее общение" % sentiment.strength]))
	result.emotions.append(_row("emotion",Catalog.EMOTIONS[person.emotion],["Сила %.0f · удовлетворённость %d" % [person.emotion_strength,person.satisfaction],"Сосредоточенность/уверенность дают небольшой бонус успешной работе; вдохновение — готовке и ремеслу."]))
	for id:String in Catalog.REWARDS: result.emotions.append(_row(id,Catalog.REWARDS[id].name,["Цена: %d удовлетворённости" % Catalog.REWARDS[id].cost,Catalog.REWARDS[id].description],[_action(actor,"reward",{"reward_id":id})]))
	if not person.apprenticeship.is_empty():
		var training:Dictionary=person.apprenticeship
		result.guilds.append(_row("training","Ученичество: "+str(sim.professions[training.profession].name),["Занятия %d/3 · практика %.0f/180 мин" % [training.lessons,training.practice],"Экзамен учитывает опыт, практику, сон и настроение; проходной балл 60."],[_action(actor,"lesson"),_action(actor,"exam")]))
	else:
		for job:String in sim.professions: result.guilds.append(_row("apprentice:"+job,str(sim.professions[job].name),["Три занятия у мастера и три часа профильной практики; затем экзамен."],[_action(actor,"apprentice",{"profession_id":job})]))
	for job:String in person.diplomas: result.guilds.append(_row("diploma:"+job,"Диплом: "+str(sim.professions[job].name),["Оценка: %d/100. Профильная работа приносит дополнительный опыт." % person.diplomas[job].grade]))
	for activity:String in Catalog.CLUB_ACTIVITIES: result.guilds.append(_row("found:"+activity,Catalog.CLUB_ACTIVITIES[activity],["Для основания нужен статус Почётного гражданина."],[_action(actor,"found_club",{"name":Catalog.CLUB_ACTIVITIES[activity],"activity":activity})]))
	for club_id:String in person.club_ids:
		if not clubs.has(club_id): continue
		var club:Dictionary=clubs[club_id]; var actions:Array=[_action(actor,"gather_club",{"club_id":club_id})]
		var offered:int=0
		for target:String in sim.residents:
			if club.members.has(target) or not _adult(target): continue
			if float(p.relationships.get(target,{}).get("friendship",0))<20: continue
			actions.append(_action(actor,"invite_club",{"club_id":club_id,"target_id":target},"Пригласить: "+str(sim.residents[target].name))); offered+=1
			if offered>=4: break
		result.guilds.append(_row(club_id,club.name,["Участников %d · состоявшихся встреч %d · очков %d" % [club.members.size(),club.gatherings,club.points],"Общий результат требует физического присутствия минимум двух участников."],actions))
	if int(h.rank)>=4:
		var actions:Array=[_action(actor,"name_house",{"name":"Дом "+str(p.name),"crest":"Дерево и дорога"},"Записать семейное название и знак")]
		for member:String in sim.households[h.id].members:
			if member!=actor: actions.append(_action(actor,"name_heir",{"target_id":member},"Наследник: "+str(sim.residents[member].name)))
		result.civic.append(_row("dynasty",str(h.house_name) if not str(h.house_name).is_empty() else "Родовой титул",["Знак: "+str(h.crest),"Носитель: "+str(sim.residents.get(str(h.get("title_holder","")),{}).get("name","не указан")),"Наследник: "+str(sim.residents.get(str(h.heir_id),{}).get("name","не назначен"))],actions))
	return result
