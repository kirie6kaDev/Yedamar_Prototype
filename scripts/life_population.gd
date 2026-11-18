extends RefCounted
const Catalog = preload("res://scripts/life_catalog.gd")
const FIRST_M := ["Арен","Борис","Вален","Гарет","Дамир","Елисей","Жарек","Зорин","Ивар","Клим","Леон","Мирон","Никлас","Орин","Павел","Радан"]
const FIRST_F := ["Алена","Бела","Вера","Грета","Дара","Ева","Жанна","Злата","Ирина","Кира","Лада","Мира","Нина","Ольда","Рада","Соня"]
const FAMILY := ["Липовые","Речные","Каменевы","Светловы","Дубровы","Тихие","Ветровы","Рябиновы","Зерновы","Лесные","Ясеневы","Садовые","Медные","Родниковы","Береговые","Звёздные"]
const JOBS := ["farmer","baker","miller","blacksmith","miner","lumberjack","merchant","teacher","guard","guard","healer","innkeeper","carpenter","gardener","tailor","hunter","shepherd","farmer","baker","scribe","potter","fisher","cook","brewer","groom","herbalist","carrier","mason","street_cleaner","musician","librarian","steward"]

static func person(id:String,title:String,age:float,gender:String,house_id:String,home_id:String,pos:Array,job:String="")->Dictionary:
	return {"id":id,"name":title,"gender":gender,"age_years":age,"stage":Catalog.stage(age),"household_id":house_id,"home_id":home_id,"profession":job,"workplace_id":"", "position":pos.duplicate(),
		"needs":Catalog.default_needs(),"traits":[],"preferences":{"food":"bread","hobby":"socialize","weather":"clear"},"aspiration":"family","aspiration_done":false,
		"appearance":{"outfit":"wanderer","color":"green","height":"average","body":"average"},"skills":{},"inventory":{},
		"career":{"level":1,"performance":0.0,"work_minutes":0.0,"earned":0,"shifts":0},"relationships":{},"mood":20.0,"moodlets":[],"memories":[],
		"parents":[],"partner_id":"","children":[],"alive":true,"external":false,"autonomy":true,"current_action":{},"queue":[],"blocked":{},"health":100.0,"personal_coins":0,"family_plan_due":-1.0,"last_social":-999.0,"last_birth_day":-999,"education":0.0,"last_wage_day":0,"lifetime_wages":0,"birth_day":1}

static func create(venues:Dictionary,seed_value:int)->Dictionary:
	var residents:Dictionary={}
	var households:Dictionary={}
	var rng:=RandomNumberGenerator.new(); rng.seed=seed_value
	var trait_ids:Array=Catalog.TRAITS.keys()
	for family_index in 16:
		var hid:String="house_%02d" % (family_index+1)
		var home:String="life_home_%02d" % (family_index+1)
		var point:Array=venues.get(home,{}).get("position",[3510.0,65.0,3698.0])
		var members:Array[String]=[]
		for member in 3:
			var number:int=family_index*3+member+1
			var id:String="resident_%03d" % number
			var name:String=FIRST_M[family_index] if member==0 else (FIRST_F[family_index] if member==1 else (FIRST_F[(family_index+7)%16] if family_index%2 else FIRST_M[(family_index+5)%16]))
			var age:float=31+family_index%18 if member<2 else 7+family_index%11
			var gender:String="male" if member==0 or (member==2 and family_index%2==0) else "female"
			var job:String=JOBS[family_index*2+member] if member<2 else ""
			var p:Dictionary=person(id,name+" · "+FAMILY[family_index],age,gender,hid,home,point,job)
			p.traits=[trait_ids[(family_index+member*3)%trait_ids.size()],trait_ids[(family_index*3+member+5)%trait_ids.size()]]
			p.appearance.outfit="guard" if job=="guard" else ("ranger" if job in ["hunter","lumberjack"] else "craftsman")
			p.appearance.color=["green","blue","red","brown"][number%4]
			p.appearance.height=["short","average","tall"][number%3]
			p.appearance.body=["slim","average","broad"][number%3]
			p.preferences.hobby=["read","socialize","train","relax"][number%4]
			p.aspiration=["family","master","wealth","scholar","community"][number%5]
			p.needs.hunger=rng.randf_range(45,90)
			p.needs.energy=rng.randf_range(65,95)
			p.inventory={"bread":2,"water":2}
			residents[id]=p
			members.append(id)
		residents[members[0]].partner_id=members[1]; residents[members[1]].partner_id=members[0]
		residents[members[2]].parents=[members[0],members[1]]
		for parent_id:String in [members[0],members[1]]: residents[parent_id].children=[members[2]]
		for a:String in members:
			for b:String in members:
				if a!=b: residents[a].relationships[b]={"friendship":65.0,"romance":60.0 if b==residents[a].partner_id else 0.0,"met":true,"last_contact":0.0}
		households[hid]={"id":hid,"name":"Семья "+FAMILY[family_index],"members":members,"home_id":home,"properties":[home],"coins":180+family_index*9,"inventory":{"bread":8,"meal":3},"income":0,"expenses":0,"reputation":10.0,"last_family_day":-20}
	households["house_player"]={"id":"house_player","name":"Наше хозяйство","members":[],"home_id":"life_player_home","properties":["life_player_home"],"coins":120,"inventory":{"bread":8,"meal":3},"income":0,"expenses":0,"reputation":10.0,"last_family_day":-20}
	return {"residents":residents,"households":households}
