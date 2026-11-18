extends RefCounted
## Pure data definitions. No scene or UI ownership.
const City = preload("res://scripts/city_world.gd")
const NEED_LABELS := {"hunger":"Сытость","thirst":"Жажда","energy":"Сон","hygiene":"Гигиена","bladder":"Уборная","social":"Общение","fun":"Досуг","comfort":"Комфорт"}
const NEED_RATES := {"hunger":.040,"thirst":.045,"energy":.055,"hygiene":.035,"bladder":.065,"social":.027,"fun":.030,"comfort":.012}
const STAGES := {"infant":"Младенец","toddler":"Малыш","child":"Ребёнок","teen":"Подросток","young_adult":"Молодой взрослый","adult":"Взрослый","elder":"Пожилой"}
const TRAITS := {
	"brave":{"name":"Храбрый","details":["Легче переносит опасность; чаще тренируется."],"weights":{"train":18},"fear":.5},
	"cowardly":{"name":"Осторожный","details":["Сильнее переживает угрозы и раньше возвращается домой."],"weights":{"sleep":12},"fear":1.6},
	"friendly":{"name":"Дружелюбный","details":["Чаще общается; добрые беседы сильнее укрепляют дружбу."],"weights":{"socialize":18},"social_bonus":1.4},
	"shy":{"name":"Застенчивый","details":["Меньше нуждается в общении; предпочитает тихий досуг."],"weights":{"socialize":-14,"read":12},"social_rate":.65},
	"lazy":{"name":"Неторопливый","details":["Быстрее устаёт от работы; предпочитает отдых."],"weights":{"work":-12,"relax":18},"productivity":.85},
	"hardworking":{"name":"Трудолюбивый","details":["Охотнее работает и получает больше результата за смену."],"weights":{"work":18},"productivity":1.18},
	"neat":{"name":"Аккуратный","details":["Раньше ищет умывальник; чистота лучше влияет на настроение."],"weights":{"wash":20},"hygiene_rate":.8},
	"slob":{"name":"Неприхотливый к чистоте","details":["Реже моется, быстрее пачкается во время работы."],"weights":{"wash":-15},"hygiene_rate":1.3},
	"ambitious":{"name":"Амбициозный","details":["Стремится работать и быстрее учится."],"weights":{"work":12,"read":8},"learning":1.2},
	"outdoors":{"name":"Любит природу","details":["Охотнее гуляет; ясная погода радует."],"weights":{"relax":12,"train":8},"weather":"clear"},
	"bookish":{"name":"Книголюб","details":["Предпочитает чтение и лучше учится по книгам."],"weights":{"read":25},"learning":1.12},
	"family":{"name":"Семейный","details":["Чаще общается с близкими; охотнее планирует детей."],"weights":{"socialize":15,"educate":20},"family":1.5},
	"frugal":{"name":"Бережливый","details":["Экономнее покупает продукты, выбирая простую еду."],"weights":{"work":5},"preferred_food":"bread"},
	"generous":{"name":"Щедрый","details":["Комплименты и помощь заметнее улучшают отношения."],"weights":{"socialize":10},"social_bonus":1.2},
	"patient":{"name":"Терпеливый","details":["Меньше страдает от скуки и хорошо обучает детей."],"weights":{"educate":15},"fun_rate":.75},
	"hotheaded":{"name":"Вспыльчивый","details":["Обиды сильнее портят отношения; чаще спорит при плохом настроении."],"weights":{"insult":10},"conflict":1.5}
}
const ASPIRATIONS := {
	"family":{"name":"Тёплый семейный дом","details":["Воспитать ребёнка и сохранить близкие отношения."],"target":1},
	"master":{"name":"Мастер своего дела","details":["Достичь пятого уровня профессии."],"target":5},
	"wealth":{"name":"Состоятельное хозяйство","details":["Накопить 500 монет в семейном бюджете."],"target":500},
	"scholar":{"name":"Образованный житель","details":["Получить 500 опыта чтения и обучения."],"target":500},
	"community":{"name":"Друг поселения","details":["Подружиться с пятью жителями."],"target":5}
}
const APPEARANCE := [
	{"id":"hair","name":"Причёска","details":[],"options":[{"id":"short","name":"Короткая"},{"id":"buzzed","name":"Остриженная"},{"id":"long","name":"Длинная"},{"id":"buns","name":"Пучки"}]},
	{"id":"outfit","name":"Одежда","details":[],"options":[{"id":"wanderer","name":"Путник"},{"id":"craftsman","name":"Ремесленник"},{"id":"guard","name":"Страж"},{"id":"ranger","name":"Следопыт"}]},
	{"id":"color","name":"Цвет одежды","details":[],"options":[{"id":"green","name":"Зелёный"},{"id":"blue","name":"Синий"},{"id":"red","name":"Красный"},{"id":"brown","name":"Коричневый"}]},
	{"id":"height","name":"Рост","details":[],"options":[{"id":"short","name":"Невысокий"},{"id":"average","name":"Средний"},{"id":"tall","name":"Высокий"}]},
	{"id":"body","name":"Телосложение","details":[],"options":[{"id":"slim","name":"Стройное"},{"id":"average","name":"Среднее"},{"id":"broad","name":"Крепкое"}]}
]
const PREFERENCES := [
	{"id":"food","name":"Любимая еда","details":[],"options":[{"id":"bread","name":"Хлеб"},{"id":"meal","name":"Похлёбка"},{"id":"apple","name":"Яблоки"},{"id":"fish","name":"Рыба"}]},
	{"id":"hobby","name":"Любимое занятие","details":[],"options":[{"id":"read","name":"Чтение"},{"id":"socialize","name":"Общение"},{"id":"train","name":"Тренировка"},{"id":"relax","name":"Прогулки"}]},
	{"id":"weather","name":"Любимая погода","details":[],"options":[{"id":"clear","name":"Ясно"},{"id":"rain","name":"Дождь"},{"id":"cloudy","name":"Облачно"},{"id":"snow","name":"Снег"}]}
]
const GOODS := {
	"fishing_rod":{"name":"Удочка","price":14,"stock":12},"lute":{"name":"Лютня","price":28,"stock":8},"wand":{"name":"Ученический жезл","price":20,"stock":8},
	"trout":{"name":"Форель","price":7,"stock":20,"food":50},"amber":{"name":"Янтарь","price":9,"stock":0},"quartz":{"name":"Кварц","price":5,"stock":0},"fossil":{"name":"Окаменелость","price":12,"stock":0},"beetle":{"name":"Лесной жук","price":3,"stock":0},"butterfly":{"name":"Луговая бабочка","price":4,"stock":0},"river_pearl":{"name":"Речная жемчужина","price":22,"stock":0},
	"egg":{"name":"Яйцо","price":2,"stock":40,"food":16},
	"wheat":{"name":"Зерно","price":1,"stock":180},"flour":{"name":"Мука","price":2,"stock":150},"bread":{"name":"Хлеб","price":3,"stock":200,"food":40},
	"meal":{"name":"Горячая похлёбка","price":5,"stock":120,"food":65},"carrot":{"name":"Морковь","price":2,"stock":120,"food":20},"apple":{"name":"Яблоки","price":2,"stock":100,"food":25},
	"fish":{"name":"Рыба","price":4,"stock":100,"food":45},"meat":{"name":"Мясо","price":5,"stock":80,"food":45},"milk":{"name":"Молоко","price":2,"stock":80,"food":22},
	"herb":{"name":"Лечебные травы","price":3,"stock":100},"hay":{"name":"Сено","price":1,"stock":100},"wool":{"name":"Шерсть","price":3,"stock":100},"hide":{"name":"Шкуры","price":3,"stock":100},
	"log":{"name":"Брёвна","price":3,"stock":160},"wood":{"name":"Дрова","price":2,"stock":200},"plank":{"name":"Доски","price":4,"stock":100},"stone":{"name":"Камень","price":2,"stock":150},
	"ore":{"name":"Руда","price":3,"stock":150},"coal":{"name":"Уголь","price":2,"stock":180},"iron_ingot":{"name":"Железо","price":6,"stock":120},"iron_tool":{"name":"Железные инструменты","price":10,"stock":60},
	"cloth":{"name":"Ткань","price":5,"stock":80},"clothing":{"name":"Рабочая одежда","price":12,"stock":40},"leather":{"name":"Кожа","price":5,"stock":70},"pottery":{"name":"Посуда","price":6,"stock":70},
	"jewelry":{"name":"Украшения","price":20,"stock":20},"ale":{"name":"Эль","price":4,"stock":80},"book":{"name":"Книги","price":15,"stock":40},"paper":{"name":"Писчие листы","price":2,"stock":100},
	"remedy":{"name":"Лекарственные сборы","price":8,"stock":60},"tonic":{"name":"Травяной настой","price":9,"stock":50},"research_notes":{"name":"Исследовательские записи","price":8,"stock":40},
	"ward_charm":{"name":"Защитные изделия","price":12,"stock":30},"map":{"name":"Карты дорог","price":12,"stock":40},"artwork":{"name":"Резные и рисованные работы","price":14,"stock":25},
	"seeds_carrot":{"name":"Семена моркови","price":2,"stock":80},"seeds_herb":{"name":"Семена трав","price":3,"stock":60},"apple_sapling":{"name":"Саженец яблони","price":10,"stock":30},
	"hoe":{"name":"Мотыга","price":12,"stock":25},"axe":{"name":"Топор","price":16,"stock":25},"saw":{"name":"Пила","price":20,"stock":20},"water":{"name":"Фляга воды","price":1,"stock":400}
}
const ACTIONS := {
	"eat":{"name":"Поесть","duration":20.0,"animation":"interact"},"drink":{"name":"Попить","duration":8.0,"animation":"interact"},
	"wash":{"name":"Умыться","duration":25.0,"animation":"interact"},"toilet":{"name":"Посетить уборную","duration":12.0,"animation":"Sit_Chair_Idle"},
	"sleep":{"name":"Поспать","duration":120.0,"animation":"Lie_Idle"},"relax":{"name":"Отдохнуть","duration":30.0,"animation":"Sit_Chair_Idle"},
	"read":{"name":"Почитать","duration":40.0,"animation":"interact"},"train":{"name":"Потренироваться","duration":40.0,"animation":"interact"},
	"study":{"name":"Учиться","duration":60.0,"animation":"interact"},"cook":{"name":"Приготовить похлёбку","duration":35.0,"animation":"interact"},
	"socialize":{"name":"Поговорить","duration":15.0,"animation":"interact"},"joke":{"name":"Пошутить","duration":10.0,"animation":"interact"},
	"compliment":{"name":"Похвалить","duration":10.0,"animation":"interact"},"insult":{"name":"Поспорить","duration":10.0,"animation":"interact"},
	"apologize":{"name":"Извиниться","duration":12.0,"animation":"interact"},"flirt":{"name":"Проявить симпатию","duration":15.0,"animation":"interact"},
	"propose":{"name":"Предложить брак","duration":20.0,"animation":"interact"},"plan_child":{"name":"Планировать ребёнка","duration":20.0,"animation":"interact"},
	"adopt":{"name":"Принять ребёнка в семью","duration":30.0,"animation":"interact"},"educate":{"name":"Помочь с учёбой","duration":40.0,"animation":"interact"},
	"work":{"name":"Работать один час","duration":60.0,"animation":"interact"},"apply_job":{"name":"Устроиться на работу","duration":15.0,"animation":"interact"},
	"quit_job":{"name":"Оставить работу","duration":0.0,"animation":"","portable":true},"buy":{"name":"Купить","duration":10.0,"animation":"interact"},"sell":{"name":"Продать","duration":10.0,"animation":"interact"},
	"buy_home":{"name":"Купить дом","duration":0.0,"animation":"","portable":true},"move_home":{"name":"Назначить семейным домом","duration":0.0,"animation":"","portable":true},
	"invite_household":{"name":"Пригласить в хозяйство","duration":20.0,"animation":"interact"},"create_member":{"name":"Создать взрослого члена семьи","duration":0.0,"animation":"","portable":true},
	"buy_workshop":{"name":"Купить мастерскую","duration":15.0,"animation":"interact"},"hire_worker":{"name":"Нанять работника","duration":20.0,"animation":"interact"},"set_price":{"name":"Назначить наценку","duration":0.0,"animation":"","portable":true},
	"edit_profile":{"name":"Изменить персонажа","duration":0.0,"animation":"","portable":true},"set_autonomy":{"name":"Самостоятельная жизнь","duration":0.0,"animation":"","portable":true}
}
const SOCIAL := ["socialize","joke","compliment","insult","apologize","flirt","propose","plan_child","educate","invite_household"]
const WEATHER_NAMES := {"clear":"Ясно","cloudy":"Облачно","rain":"Дождь","storm":"Гроза","fog":"Туман","snow":"Снег"}
const SEASONS := ["Весна","Лето","Осень","Зима"]
const WEEKDAYS := ["День Луны","День Ремёсел","День Рынка","День Садов","День Путников","День Очагов","День Отдыха"]

static func professions() -> Dictionary:
	var result:Dictionary={}
	for id:String in City.PROFESSION_NAMES:
		result[id]={"id":id,"name":City.PROFESSION_NAMES[id],"venue_id":City.PROFESSION_VENUES[id],"skill":"crafting","wage":24,"start":8,"end":17,"days":[0,1,2,3,4,5],"inputs":{},"outputs":{},"service":"community","minimum_age":18}
	var rules:Dictionary={
		"farmer":["farming",20,{}, {"wheat":5,"carrot":2}],"gardener":["farming",20,{}, {"herb":3,"apple":2}],"shepherd":["animal_husbandry",22,{"hay":1},{"milk":3,"wool":1}],
		"blacksmith":["blacksmithing",36,{"ore":2,"coal":1},{"iron_ingot":2}],"carpenter":["carpentry",28,{"log":1},{"plank":4}],"mason":["carpentry",27,{}, {"stone":4}],
		"tailor":["tailoring",30,{"wool":2},{"cloth":3,"clothing":1}],"leatherworker":["leatherworking",27,{"hide":2},{"leather":3}],"potter":["pottery",25,{"stone":1},{"pottery":2}],"jeweler":["jewelry",40,{"iron_ingot":1},{"jewelry":1}],
		"cook":["cooking",24,{"carrot":2,"fish":1},{"meal":5}],"baker":["cooking",24,{"flour":2,"wood":1},{"bread":7}],"brewer":["cooking",26,{"wheat":2},{"ale":4}],
		"healer":["herbalism",32,{"herb":2},{"remedy":2}],"herbalist":["herbalism",24,{}, {"herb":4}],"scribe":["reading",27,{"paper":2},{"book":1}],
		"hunter":["tracking",26,{}, {"meat":3,"hide":1}],"tracker":["tracking",28,{}, {"research_notes":1}],"explorer":["research",32,{}, {"research_notes":2}],"relic_hunter":["research",34,{}, {"research_notes":2}],
		"cartographer":["reading",32,{"paper":2},{"map":1}],"alchemist":["alchemy",36,{"herb":2,"water":1},{"tonic":2}],"magic_researcher":["research",36,{"paper":1},{"research_notes":2}],
		"artificer":["crafting",38,{"iron_ingot":1,"research_notes":1},{"ward_charm":2}],"magical_healer":["herbalism",36,{"herb":2},{"remedy":3}],"ward_specialist":["crafting",34,{"wood":1,"herb":1},{"ward_charm":1}],
		"miner":["mining",25,{}, {"ore":4,"coal":2}],"lumberjack":["woodcutting",24,{}, {"log":3,"wood":4}],"miller":["crafting",23,{"wheat":3},{"flour":6}],"fisher":["fishing",23,{}, {"fish":4}],"street_artist":["performance",26,{"wood":1},{"artwork":1}]
	}
	for id:String in rules:
		var row:Array=rules[id]
		result[id].skill=row[0]; result[id].wage=row[1]; result[id].inputs=row[2]; result[id].outputs=row[3]; result[id].service=""
	for id:String in ["merchant","innkeeper","courier","carrier","steward"]: result[id].skill="trade"
	for id:String in ["teacher","mentor","librarian","arcane_mentor"]: result[id].skill="teaching"; result[id].service="education"
	for id:String in ["guard","guard_captain","hired_guard","monster_hunter","scout"]: result[id].skill="combat"; result[id].service="safety"
	for id:String in ["guide"]: result[id].skill="tracking"
	for id:String in ["groom"]: result[id].skill="animal_husbandry"
	for id:String in ["musician","singer","dancer","actor","storyteller","impresario"]: result[id].skill="performance"; result[id].service="culture"; result[id].start=14; result[id].end=22
	result.guard.start=20; result.guard.end=6; result.guard.days=[0,1,2,3,4,5,6]
	result.innkeeper.start=14; result.innkeeper.end=23
	return result

static func stage(age:float)->String:
	if age<1: return "infant"
	if age<5: return "toddler"
	if age<13: return "child"
	if age<18: return "teen"
	if age<30: return "young_adult"
	if age<65: return "adult"
	return "elder"

static func default_needs()->Dictionary:
	var values:Dictionary={}
	for key:String in NEED_RATES: values[key]=85.0
	return values

static func skill_level(xp:float)->int:
	return clampi(1+floori(maxf(0,xp)/100),1,10)
