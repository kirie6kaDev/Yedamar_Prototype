extends SceneTree
## Headless economy check (step 3): run LifeSim offscreen for N days without the 3D city.
## godot --headless --path . --script tests/economy_sim.gd -- [days]
const LifeSim = preload("res://scripts/life_sim.gd")
const CityWorld = preload("res://scripts/city_world.gd")
const WATCH := ["bread","meal","fish","wood","flour","iron_tool","ale","jewelry","remedy","clothing"]

func _config()->Dictionary:
	var venues:Dictionary={}; var workplaces:Dictionary={}
	for spec:Dictionary in CityWorld.venue_specs():
		var p:Vector2=spec.p
		var pos:Array=[p.x,65.0,p.y]
		var professions:Array=[]
		for prof:String in CityWorld.PROFESSION_VENUES:
			if CityWorld.PROFESSION_VENUES[prof]==spec.id: professions.append(prof)
		venues[spec.id]={"id":spec.id,"kind":spec.kind,"name":spec.name,"position":pos,"approach":pos,"capacity":int(spec.capacity),"safe":true,"district":spec.district,"professions":professions,"workstations":[],"action_targets":{},"need_targets":{}}
		for key:String in ["price","buyable","lot"]:
			if spec.has(key): venues[spec.id][key]=spec[key]
		for prof:String in professions:
			workplaces[prof]={"id":"life_job_"+prof,"venue_id":spec.id,"profession":prof,"prop":"bench","position":pos,"approach":pos}
	return {"venues":venues,"workplaces":workplaces,"seed":782941,"absolute_minutes":1920.0}

func _npc_coins(sim)->Array:
	var total:=0; var lo:=1<<30; var hi:=0
	for hid:String in sim.households:
		if hid=="house_player": continue
		var c:int=int(sim.households[hid].coins); total+=c; lo=mini(lo,c); hi=maxi(hi,c)
	return [total,lo,hi]

func _hero_work_hour(sim,hero:String)->void:
	var prof:String=str(sim.residents[hero].profession)
	if prof.is_empty() or not sim._is_work_time(prof): return
	if int(sim.residents[hero].get("paid_minutes_today",0))>=480 and int(sim.residents[hero].get("last_wage_day",-1))==sim._day: return
	sim.residents[hero].position=sim._point_array(sim._workplace(prof))
	sim._execute(hero,"work",{"profession_id":prof})

func _initialize()->void:
	var days:int=30
	var args:=OS.get_cmdline_user_args()
	if args.size()>0: days=int(args[0])
	var sim=LifeSim.new()
	sim.configure(_config())
	var live:Dictionary={"hunger":90.0,"thirst":90.0,"sleep":90.0,"health":100.0,"inventory":{},"skills":{}}
	sim.register_player("brother",live)
	var hero:="brother"
	print("START treasury=%d base=%d npc_coins=%s" % [sim.market.treasury,sim.market.treasury_base,str(_npc_coins(sim))])
	# J1: skill gate on apply_job.
	sim.residents[hero].position=sim._point_array(sim._workplace("blacksmith"))
	var gate:Dictionary=sim.command_spec(hero,"apply_job",{"profession_id":"blacksmith"})
	print("HERO apply blacksmith without skill: ok=%s reason=%s" % [gate.ok,gate.reason])
	live.skills["blacksmithing"]=210.0
	var hired:Dictionary=sim._execute(hero,"apply_job",{"profession_id":"blacksmith"})
	print("HERO apply with blacksmithing 210xp: %s" % hired.message)
	var totals:Dictionary={}
	var rx:=RegEx.new(); rx.compile("(продажи|подать|жалованье|выкуп у жителей|содержание города) (\\d+)")
	var seen:=0
	var max_mult:=0.0; var min_mult:=99.0
	var max_ratio:Dictionary={}
	var hungry_days:=0
	var orders_posted:=0; var orders_market:=0; var orders_hero:=0; var orders_expired:=0
	var recipe_hours:Dictionary={}
	var counted:Dictionary={}
	sim.command_observer=func(id,action,payload,result,spec):
		if action=="work" and not sim.residents[id].external: recipe_hours[str(result.get("recipe",""))]=int(recipe_hours.get(str(result.get("recipe","")),0))+1
	for day in days:
		live.hunger=90.0; live.thirst=90.0; live.sleep=90.0
		for hour in 24:
			sim.advance(60.0)
			_hero_work_hour(sim,hero)
		# Hero fulfils one open order per 5 days with goods "crafted" in his own systems.
		if day%5==4:
			for c in sim.open_contracts():
				if str(c.status)=="open":
					live.inventory[c.item]=int(live.inventory.get(c.item,0))+int(c.quantity)
					var before:int=int(sim.households.house_player.coins)
					var t:Dictionary=sim.command(hero,"take_order",{"order_id":c.id})
					var d:Dictionary=sim.command(hero,"deliver_order",{"order_id":c.id})
					if day<20 or day%30==4: print("    HERO order %s %s×%d: %s / %s (+%d coins)" % [c.id,c.item,int(c.quantity),t.get("message",""),d.get("message",""),int(sim.households.house_player.coins)-before])
					break
		var line:="day %3d treasury=%6d npc=%s" % [sim._day,int(sim.market.treasury),str(_npc_coins(sim))]
		for item:String in ["bread","flour","meal","remedy","iron_tool"]:
			line+=" %s=%d(x%.2f,s%d)" % [item,sim.price(item),sim.price_multiplier(item),int(sim.market.stocks[item])]
		if day%10==8 or day==days-1: print(line)
		for item:String in sim.Catalog.GOODS:
			var m:float=sim.price_multiplier(item); max_mult=maxf(max_mult,m); min_mult=minf(min_mult,m)
			var t:int=sim._stock_target(item)
			if t>0: max_ratio[item]=maxf(float(max_ratio.get(item,0.0)),float(sim.market.stocks[item])/t)
		for e:Dictionary in sim.events:
			if int(str(e.id).trim_prefix("event_"))<=seen: continue
			if str(e.kind)=="fair_trade" and day%10<7: print("    [%s] %s · %s" % [e.kind,e.name,", ".join(e.details)])
			if str(e.kind)=="order" and str(e.name).begins_with("Новый"): orders_posted+=1
			if str(e.kind)=="treasury":
				for m in rx.search_all(", ".join(e.details)): totals[m.get_string(1)]=int(totals.get(m.get_string(1),0))+int(m.get_string(2))
			if str(e.kind)=="fair_trade":
				var fm:=RegEx.create_from_string("за (\\d+) монет · завезено \\d+ шт. за (\\d+)").search(", ".join(e.details))
				if fm: totals["экспорт"]=int(totals.get("экспорт",0))+int(fm.get_string(1)); totals["импорт"]=int(totals.get("импорт",0))+int(fm.get_string(2))
		seen=sim._next_event-1
		for c in sim.contracts.values():
			if str(c.status) in ["open","taken"] or counted.has(c.id): continue
			counted[c.id]=true
			match str(c.status):
				"filled_market": orders_market+=1
				"done": orders_hero+=1
				"expired": orders_expired+=1
		var hungry:=0
		for id:String in sim.residents:
			var p:Dictionary=sim.residents[id]
			if p.alive and not p.external and float(p.needs.hunger)<10: hungry+=1
		if hungry>0: hungry_days+=1
	var hp:Dictionary=sim.residents[hero]
	print("HERO career: %s rank=%d shifts=%d hours=%.0f skill blacksmithing=%.0fxp (lvl %d) coins=%d" % [hp.profession,int(hp.career.level),int(hp.career.shifts),float(hp.career.work_minutes)/60,float(live.skills.get("blacksmithing",0)),sim._skill_level_of(hp,"blacksmithing"),int(sim.households.house_player.coins)])
	var ranks:Array=[]
	for id:String in sim.residents:
		var r:Dictionary=sim.residents[id]
		if r.alive and not r.external and not str(r.profession).is_empty(): ranks.append("%s:r%d/s%d" % [r.profession,int(r.career.level),int(r.career.get("shifts",0))])
	print("NPC ranks/shifts: ", ", ".join(ranks.slice(0,12)))
	print("ORDERS posted=%d by_market=%d by_hero=%d expired=%d open_now=%d" % [orders_posted,orders_market,orders_hero,orders_expired,sim.open_contracts().size()])
	print("RECIPE HOURS (NPC): ",recipe_hours)
	print("TREASURY FLOWS total: ",totals)
	print("END multipliers min=%.2f max=%.2f days_with_hungry_npc=%d alive=%d" % [min_mult,max_mult,hungry_days,sim.residents.values().filter(func(r): return r.alive).size()])
	var ratios:Array=[]
	for item in max_ratio: ratios.append([item,max_ratio[item]])
	ratios.sort_custom(func(a,b): return a[1]>b[1])
	var top:Array=[]
	for r in ratios.slice(0,12): top.append("%s %.2f×(now %d/%d)" % [r[0],r[1],int(sim.market.stocks[r[0]]),sim._stock_target(r[0])])
	print("MAX STOCK/TARGET top: ", ", ".join(top))
	for hid:String in sim.households:
		var h:Dictionary=sim.households[hid]; var jobs:Array=[]
		for m in h.members: jobs.append(str(sim.residents[m].profession))
		print("  %s coins=%d income=%d expenses=%d %s" % [hid,int(h.coins),int(h.income),int(h.expenses),",".join(jobs)])
	for item:String in WATCH: print("  %s buy=%d sell=%d stock=%d target=%d" % [item,sim.price(item),sim.price(item,true),int(sim.market.stocks[item]),sim._stock_target(item)])
	# Migration: fake a v1 save with the legacy treasury and no step-3 fields.
	var snap:Dictionary=sim.snapshot()
	snap.version=1; snap.market.treasury=1000000-2300; snap.market.erase("flow"); snap.market.erase("ledger"); snap.market.erase("treasury_base"); snap.erase("contracts"); snap.erase("next_contract")
	for r in snap.residents.values(): r.career.erase("shifts"); r.erase("career_history")
	for b in snap.businesses.values(): b.markup=1.2
	var decoded=JSON.parse_string(JSON.stringify(snap))
	var other=LifeSim.new(); other.configure(_config())
	var ok:bool=other.restore(decoded)
	print("MIGRATION v1->v3 ok=%s treasury=%d base=%d flow=%s ledger=%s next_version=%d" % [ok,int(other.market.treasury),int(other.market.treasury_base),str(other.market.flow.size()),str(other.market.ledger),int(other.snapshot().version)])
	var snap2=JSON.parse_string(JSON.stringify(sim.snapshot()))
	var third=LifeSim.new(); third.configure(_config())
	print("ROUNDTRIP v3 ok=%s treasury=%d/%d contracts=%d/%d hero_shifts=%d" % [third.restore(snap2),int(third.market.treasury),int(sim.market.treasury),third.contracts.size(),sim.contracts.size(),int(third.residents.brother.career.shifts)])
	# Price rule check: spread holds for every good, clamps hold.
	var bad:=0
	for item:String in sim.Catalog.GOODS:
		var b:int=sim.price(item); var sl:int=sim.price(item,true); var base:int=int(sim.Catalog.GOODS[item].price)
		if (b>1 and sl>=b) or float(sl)>float(base)*0.85+0.5 or b<1: bad+=1; print("  BAD price ",item," ",b," ",sl)
	print("PRICE RULES violations=%d goods=%d" % [bad,sim.Catalog.GOODS.size()])
	# Stress: nearly empty treasury. Wages must shrink, treasury must never go negative.
	var poor=LifeSim.new(); poor.configure(_config()); poor.market.treasury=300
	var lowest:=300; var factor_low:=1.0
	for hour in 24*14:
		poor.advance(60.0); lowest=mini(lowest,int(poor.market.treasury)); factor_low=minf(factor_low,poor._wage_factor())
	print("STRESS start=300 after14d=%d min=%d min_wage_factor=%.2f npc=%s" % [int(poor.market.treasury),lowest,factor_low,str(_npc_coins(poor))])
	quit()
