extends RefCounted
## Stable venue/profession identifiers shared by world construction and life simulation.
## Coordinates are metres in the existing terrain, not a separate map or loading scene.

const CITY_CENTER := Vector2(3510, 3680)
const SECOND_CENTER := Vector2(3360, 4515)
const CITY_RECT := Rect2(3220, 3390, 580, 580)
const STATIC_CLEARINGS := [
	{"p":Vector2(3915,3570),"r":36.0}, {"p":Vector2(3915,3680),"r":36.0},
	{"p":Vector2(3915,3790),"r":36.0}, {"p":Vector2(3490,4580),"r":36.0}, {"p":Vector2(4190,4480),"r":36.0},
	{"p": Vector2(3990,4485), "r":40.0},
	{"p": Vector2(3510,3680), "r":420.0},
	{"p": Vector2(3360,4515), "r":114.0},
	{"p": Vector2(3710,4045), "r":65.0},
	{"p": Vector2(3050,3630), "r":35.0},
	{"p": Vector2(2815,4375), "r":28.0},
	{"p": Vector2(4585,3700), "r":34.0},
	{"p": Vector2(4460,3880), "r":36.0},
	{"p": Vector2(2890,3670), "r":24.0},
]

const PROFESSION_VENUES := {
	"farmer":"life_farm", "gardener":"life_farm", "shepherd":"life_farm",
	"blacksmith":"life_forge", "carpenter":"life_carpentry", "mason":"life_quarry",
	"tailor":"life_tailor", "leatherworker":"life_tannery", "potter":"life_pottery", "jeweler":"life_jeweler",
	"merchant":"life_market", "innkeeper":"life_tavern", "cook":"life_kitchen", "baker":"life_bakery", "brewer":"life_brewery",
	"teacher":"life_school", "mentor":"life_guild", "librarian":"life_library", "scribe":"life_scriptorium", "clerk":"life_town_hall",
	"guard":"life_watch", "guard_captain":"life_watch", "healer":"life_clinic", "herbalist":"life_apothecary", "groom":"life_stable",
	"courier":"life_post", "carrier":"life_warehouse", "builder":"life_builders", "street_cleaner":"life_square", "steward":"life_town_hall",
	"hunter":"life_hunting_lodge", "tracker":"life_hunting_lodge", "guide":"life_travel_guild", "scout":"life_watch",
	"hired_guard":"life_travel_guild", "explorer":"life_academy", "relic_hunter":"life_academy", "cartographer":"life_mapmakers", "monster_hunter":"life_hunting_lodge",
	"alchemist":"life_apothecary", "magic_researcher":"life_academy", "artificer":"life_artificers", "magical_healer":"life_clinic",
	"ward_specialist":"life_temple", "arcane_mentor":"life_academy",
	"musician":"life_theatre", "singer":"life_theatre", "dancer":"life_theatre", "actor":"life_theatre", "storyteller":"life_tavern",
	"street_artist":"life_square", "impresario":"life_theatre",
	"miner":"life_mine", "lumberjack":"life_logging_camp", "miller":"life_mill", "fisher":"life_fishery",
}

const PROFESSION_PROPS := {
	"farmer":"crop", "gardener":"planter", "shepherd":"trough",
	"blacksmith":"anvil", "carpenter":"workbench", "mason":"stonebench", "tailor":"loom", "leatherworker":"tanning_rack", "potter":"pottery_wheel", "jeweler":"jewelbench",
	"merchant":"stall", "innkeeper":"counter", "cook":"hearth", "baker":"oven", "brewer":"brewvat",
	"teacher":"lectern", "mentor":"training", "librarian":"bookshelf", "scribe":"writing_desk", "clerk":"writing_desk",
	"guard":"weapon_rack", "guard_captain":"map_table", "healer":"medical_table", "herbalist":"herb_table", "groom":"trough",
	"courier":"post_board", "carrier":"cargo", "builder":"workbench", "street_cleaner":"broom_rack", "steward":"ledger_desk",
	"hunter":"archery", "tracker":"map_table", "guide":"map_table", "scout":"telescope", "hired_guard":"training",
	"explorer":"specimen_table", "relic_hunter":"relic_table", "cartographer":"map_table", "monster_hunter":"weapon_rack",
	"alchemist":"cauldron", "magic_researcher":"research_table", "artificer":"jewelbench", "magical_healer":"medical_table", "ward_specialist":"ward_table", "arcane_mentor":"lectern",
	"musician":"lute", "singer":"music_stand", "dancer":"dance_floor", "actor":"stage_props", "storyteller":"story_chair", "street_artist":"easel", "impresario":"writing_desk",
	"miner":"ore", "lumberjack":"sawhorse", "miller":"millstone", "fisher":"fishing_rack",
}

const PROFESSION_NAMES := {
	"farmer":"Фермер", "gardener":"Садовник", "shepherd":"Пастух", "blacksmith":"Кузнец", "carpenter":"Плотник", "mason":"Каменщик",
	"tailor":"Портной", "leatherworker":"Кожевник", "potter":"Гончар", "jeweler":"Ювелир", "merchant":"Торговец", "innkeeper":"Трактирщик", "cook":"Повар", "baker":"Пекарь", "brewer":"Пивовар",
	"teacher":"Учитель", "mentor":"Наставник", "librarian":"Библиотекарь", "scribe":"Писарь", "clerk":"Городской служащий", "guard":"Стражник", "guard_captain":"Начальник стражи", "healer":"Лекарь", "herbalist":"Травник", "groom":"Конюх",
	"courier":"Курьер", "carrier":"Перевозчик", "builder":"Строитель", "street_cleaner":"Уборщик улиц", "steward":"Управляющий", "hunter":"Охотник", "tracker":"Следопыт", "guide":"Проводник", "scout":"Разведчик", "hired_guard":"Наёмный охранник",
	"explorer":"Исследователь", "relic_hunter":"Искатель реликвий", "cartographer":"Картограф", "monster_hunter":"Охотник на нечисть", "alchemist":"Алхимик", "magic_researcher":"Исследователь магии", "artificer":"Артефактор", "magical_healer":"Магический целитель", "ward_specialist":"Мастер защитных средств", "arcane_mentor":"Наставник магии",
	"musician":"Музыкант", "singer":"Певец", "dancer":"Танцор", "actor":"Актёр", "storyteller":"Рассказчик", "street_artist":"Уличный артист", "impresario":"Организатор представлений", "miner":"Шахтёр", "lumberjack":"Лесоруб", "miller":"Мельник", "fisher":"Рыбак",
}

static func venue_specs() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		_v("life_player_home","home","Дом семьи у фермы",3990,4485,28,24,"Ферма Марты",4),
		_v("life_square","square","Ратушная площадь",3510,3698,58,46,"Центр",40),
		_v("life_market","market","Рынок Арденхольма",3440,3698,40,36,"Торговый",24),
		_v("life_tavern","tavern","Таверна «У ворот»",3590,3698,40,32,"Торговый",18),
		_v("life_bakery","bakery","Городская пекарня",3420,3625,30,28,"Ремесленный",6),
		_v("life_mill","mill","Ветряная мельница",3290,3870,28,28,"Ремесленный",4),
		_v("life_forge","forge","Кузница и литейный двор",3330,3700,34,30,"Ремесленный",8),
		_v("life_carpentry","carpentry","Столярная мастерская",3330,3770,34,30,"Ремесленный",6),
		_v("life_tailor","tailor","Портняжная мастерская",3420,3555,30,28,"Ремесленный",6),
		_v("life_tannery","tannery","Кожевенный двор",3330,3625,32,28,"Ремесленный",5),
		_v("life_pottery","pottery","Гончарная мастерская",3330,3555,30,28,"Ремесленный",5),
		_v("life_jeweler","jeweler","Ювелирная лавка",3420,3485,28,26,"Ремесленный",4),
		_v("life_school","school","Городская школа",3605,3555,36,30,"Учёный",14),
		_v("life_library","library","Городская библиотека",3685,3555,36,30,"Учёный",12),
		_v("life_clinic","clinic","Лечебница",3685,3625,36,30,"Учёный",8),
		_v("life_watch","watch","Казарма городской стражи",3510,3870,38,32,"Южные ворота",12),
		_v("life_bathhouse","bathhouse","Общественная баня",3605,3780,38,32,"Жилой",10),
		_v("life_stable","stable","Городская конюшня",3685,3870,38,32,"Южные ворота",8),
		_v("life_farm","farm","Пригородная ферма",3710,4045,56,44,"Предместье",12),
		_v("life_mine","mine","Горный промысел",2815,4375,28,24,"Шахты",6),
		_v("life_hunting_lodge","hunting_lodge","Охотничья заимка",4460,3880,38,30,"Лес",10),
		_v("life_town_hall","town_hall","Ратуша Арденхольма",3510,3555,42,34,"Центр",16),
		_v("life_graveyard","graveyard","Городское кладбище",3760,3430,44,34,"Северные ворота",12),
		_v("life_temple","temple","Дом памяти и защиты",3685,3485,38,30,"Учёный",16),
		_v("life_guild","guild","Гильдия мастеров",3420,3770,34,30,"Ремесленный",10),
		_v("life_academy","academy","Академия исследований",3685,3700,42,38,"Учёный",16),
		_v("life_brewery","brewery","Пивоварня",3605,3625,32,28,"Торговый",6),
		_v("life_kitchen","kitchen","Общая кухня",3420,3870,32,28,"Жилой",10),
		_v("life_theatre","theatre","Театральный двор",3605,3485,40,34,"Учёный",24),
		_v("life_post","post","Почтовый двор",3510,3780,30,28,"Торговый",8),
		_v("life_warehouse","warehouse","Караванный склад",3330,3870,34,30,"Южные ворота",8),
		_v("life_quarry","quarry","Каменный карьер",3050,3630,34,28,"Карьер",6),
		_v("life_fishery","fishery","Рыбацкий двор у заводи",2890,3670,28,24,"Берег",6),
		_v("life_logging_camp","logging_camp","Лесозаготовительный лагерь",4585,3700,32,28,"Лес",6),
		_v("life_scriptorium","scriptorium","Писцовая палата",3510,3485,30,28,"Учёный",6),
		_v("life_apothecary","apothecary","Аптекарская мастерская",3685,3780,34,30,"Учёный",6),
		_v("life_builders","builders","Строительный двор",3330,3485,32,28,"Ремесленный",8),
		_v("life_travel_guild","travel_guild","Гильдия проводников",3605,3870,34,30,"Южные ворота",8),
		_v("life_mapmakers","mapmakers","Картографическая мастерская",3420,3925,30,24,"Южные ворота",5),
		_v("life_artificers","artificers","Мастерская приборов",3685,3925,30,24,"Южные ворота",5),
		_v("life_south_square","square","Лиоров Брод · площадь",3360,4515,38,30,"Лиоров Брод",16),
		_v("life_south_market","market","Лиоров Брод · торговый двор",3315,4515,30,26,"Лиоров Брод",10),
		_v("life_south_tavern","tavern","Лиоров Брод · постоялый двор",3405,4515,32,28,"Лиоров Брод",12),
		_v("life_south_bath","bathhouse","Лиоров Брод · баня",3360,4570,28,24,"Лиоров Брод",6),
	]
	var home_points: Array[Vector2] = []
	for x: float in [3310,3370,3430,3490,3550,3610,3670]:
		home_points.append(Vector2(x,3425))
	for z: float in [3520,3600,3680,3760,3840]:
		home_points.append(Vector2(3760,z))
	for z: float in [3520,3600,3700,3800]:
		home_points.append(Vector2(3260,z))
	home_points.append_array([Vector2(3315,4460),Vector2(3405,4460),Vector2(3315,4570),Vector2(3405,4570)])
	for i in home_points.size():
		var p: Vector2 = home_points[i]
		var home := _v("life_home_%02d" % (i+1),"home","Дом №%d" % (i+1),p.x,p.y,28,24,"Арденхольм" if i<16 else "Лиоров Брод",4)
		home["price"] = 180 + (i % 4) * 25
		home["buyable"] = i >= 16
		result.append(home)
	var lot_points:Array[Vector2]=[Vector2(3915,3570),Vector2(3915,3680),Vector2(3915,3790),Vector2(3490,4580),Vector2(4190,4480)]
	for i in lot_points.size():
		var p:Vector2=lot_points[i]
		var lot:=_v("life_plot_%02d"%(i+1),"plot","Участок №%d · свободная земля"%(i+1),p.x,p.y,44,40,"Восточная слобода" if i<3 else "Лиоров Брод" if i==3 else "Фермерская округа",4)
		lot.merge({"price":90+i*20,"buyable":true,"lot":true})
		result.append(lot)
	return result

static func _v(id: String, kind: String, title: String, x: float, z: float, width: float, depth: float, district: String, capacity: int) -> Dictionary:
	return {"id":id,"kind":kind,"name":title,"p":Vector2(x,z),"size":Vector2(width,depth),"district":district,"capacity":capacity,"safe":true}
