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

func _initialize()->void:
	var days:int=30
	var args:=OS.get_cmdline_user_args()
	if args.size()>0: days=int(args[0])
	var sim=LifeSim.new()
	sim.configure(_config())
	print("START treasury=%d base=%d npc_coins=%s" % [sim.market.treasury,sim.market.treasury_base,str(_npc_coins(sim))])
	var seen:=0
	var max_mult:=0.0; var min_mult:=99.0
	var hungry:=0
	for day in days:
		sim.advance(1440.0)
		var line:="day %2d treasury=%6d npc=%s" % [sim._day,int(sim.market.treasury),str(_npc_coins(sim))]
		for item:String in ["bread","wood","ale","iron_tool"]:
			line+=" %s=%d(x%.2f,s%d)" % [item,sim.price(item),sim.price_multiplier(item),int(sim.market.stocks[item])]
		print(line)
		for item:String in sim.Catalog.GOODS:
			var m:float=sim.price_multiplier(item); max_mult=maxf(max_mult,m); min_mult=minf(min_mult,m)
		for i in range(seen,sim._next_event):
			pass
		for e:Dictionary in sim.events:
			if int(str(e.id).trim_prefix("event_"))<=seen: continue
			if str(e.kind) in ["treasury","fair_trade","market"]: print("    [%s] %s · %s" % [e.kind,e.name,", ".join(e.details)])
		seen=sim._next_event-1
	for id:String in sim.residents:
		var p:Dictionary=sim.residents[id]
		if p.alive and not p.external and float(p.needs.hunger)<10: hungry+=1
	print("END multipliers min=%.2f max=%.2f hungry_npcs=%d alive=%d" % [min_mult,max_mult,hungry,sim.residents.values().filter(func(r): return r.alive).size()])
	for hid:String in sim.households:
		var h:Dictionary=sim.households[hid]; var jobs:Array=[]
		for m in h.members: jobs.append("%s(%d,%s)" % [str(sim.residents[m].profession),int(sim.residents[m].age_years),str(sim.residents[m].traits)])
		print("  %s coins=%d income=%d expenses=%d %s" % [hid,int(h.coins),int(h.income),int(h.expenses),", ".join(jobs)])
	for item:String in WATCH: print("  %s buy=%d sell=%d stock=%d target=%d" % [item,sim.price(item),sim.price(item,true),int(sim.market.stocks[item]),sim._stock_target(item)])
	# Migration: fake a v1 save with the legacy treasury and no step-3 fields.
	var snap:Dictionary=sim.snapshot()
	snap.version=1; snap.market.treasury=1000000-2300; snap.market.erase("flow"); snap.market.erase("ledger"); snap.market.erase("treasury_base")
	for b in snap.businesses.values(): b.markup=1.2
	var decoded=JSON.parse_string(JSON.stringify(snap))
	var other=LifeSim.new(); other.configure(_config())
	var ok:bool=other.restore(decoded)
	print("MIGRATION v1 ok=%s treasury=%d base=%d flow=%s ledger=%s next_version=%d" % [ok,int(other.market.treasury),int(other.market.treasury_base),str(other.market.flow.size()),str(other.market.ledger),int(other.snapshot().version)])
	var snap2=JSON.parse_string(JSON.stringify(other.snapshot()))
	var third=LifeSim.new(); third.configure(_config())
	print("ROUNDTRIP v2 ok=%s treasury=%d" % [third.restore(snap2),int(third.market.treasury)])
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
