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
	# Explicit per-role table. Name and workplace come from city_world.gd so identifiers stay in sync.
	var weekday:Array=[0,1,2,3,4,5]
	var everyday:Array=[0,1,2,3,4,5,6]
	var school_days:Array=[0,1,2,3,4]
	var defs:Dictionary={
		"farmer":{"skill":"farming","wage":20,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{"wheat":5,"carrot":2},"service":""},
		"gardener":{"skill":"farming","wage":20,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{"herb":3,"apple":2},"service":""},
		"shepherd":{"skill":"animal_husbandry","wage":22,"start":8,"end":17,"days":weekday,"inputs":{"hay":1},"outputs":{"milk":3,"wool":1},"service":""},
		"blacksmith":{"skill":"blacksmithing","wage":36,"start":8,"end":17,"days":weekday,"inputs":{"ore":2,"coal":1},"outputs":{"iron_ingot":2},"service":""},
		"carpenter":{"skill":"carpentry","wage":28,"start":8,"end":17,"days":weekday,"inputs":{"log":1},"outputs":{"plank":4},"service":""},
		"mason":{"skill":"carpentry","wage":27,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{"stone":4},"service":""},
		"tailor":{"skill":"tailoring","wage":30,"start":8,"end":17,"days":weekday,"inputs":{"wool":2},"outputs":{"cloth":3,"clothing":1},"service":""},
		"leatherworker":{"skill":"leatherworking","wage":27,"start":8,"end":17,"days":weekday,"inputs":{"hide":2},"outputs":{"leather":3},"service":""},
		"potter":{"skill":"pottery","wage":25,"start":8,"end":17,"days":weekday,"inputs":{"stone":1},"outputs":{"pottery":2},"service":""},
		"jeweler":{"skill":"jewelry","wage":40,"start":8,"end":17,"days":weekday,"inputs":{"iron_ingot":1},"outputs":{"jewelry":1},"service":""},
		"merchant":{"skill":"trade","wage":30,"start":8,"end":18,"days":weekday,"inputs":{},"outputs":{},"service":"community"},
		"innkeeper":{"skill":"trade","wage":28,"start":14,"end":23,"days":everyday,"inputs":{},"outputs":{},"service":"community"},
		"cook":{"skill":"cooking","wage":26,"start":10,"end":20,"days":weekday,"inputs":{"carrot":2,"fish":1},"outputs":{"meal":5},"service":""},
		"baker":{"skill":"cooking","wage":25,"start":5,"end":13,"days":weekday,"inputs":{"flour":2,"wood":1},"outputs":{"bread":7},"service":""},
		"brewer":{"skill":"cooking","wage":26,"start":8,"end":17,"days":weekday,"inputs":{"wheat":2},"outputs":{"ale":4},"service":""},
		"teacher":{"skill":"teaching","wage":26,"start":9,"end":16,"days":school_days,"inputs":{},"outputs":{},"service":"education"},
		"mentor":{"skill":"teaching","wage":28,"start":9,"end":16,"days":school_days,"inputs":{},"outputs":{},"service":"education"},
		"librarian":{"skill":"teaching","wage":25,"start":9,"end":17,"days":weekday,"inputs":{},"outputs":{},"service":"education"},
		"scribe":{"skill":"reading","wage":27,"start":8,"end":17,"days":weekday,"inputs":{"paper":2},"outputs":{"book":1},"service":""},
		"clerk":{"skill":"literacy","wage":26,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{},"service":"community"},
		"guard":{"skill":"combat","wage":28,"start":20,"end":6,"days":everyday,"inputs":{},"outputs":{},"service":"safety"},
		"guard_captain":{"skill":"combat","wage":34,"start":8,"end":17,"days":everyday,"inputs":{},"outputs":{},"service":"safety"},
		"healer":{"skill":"herbalism","wage":32,"start":8,"end":18,"days":everyday,"inputs":{"herb":2},"outputs":{"remedy":2},"service":""},
		"herbalist":{"skill":"herbalism","wage":22,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{"herb":4},"service":""},
		"groom":{"skill":"animal_husbandry","wage":20,"start":6,"end":15,"days":everyday,"inputs":{},"outputs":{},"service":"community"},
		"courier":{"skill":"trade","wage":22,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{},"service":"community"},
		"carrier":{"skill":"trade","wage":23,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{},"service":"community"},
		"builder":{"skill":"carpentry","wage":28,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{},"service":"community"},
		"street_cleaner":{"skill":"athletics","wage":18,"start":6,"end":14,"days":everyday,"inputs":{},"outputs":{},"service":"community"},
		"steward":{"skill":"trade","wage":32,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{},"service":"community"},
		"hunter":{"skill":"tracking","wage":26,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{"meat":3,"hide":1},"service":""},
		"tracker":{"skill":"tracking","wage":28,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{"research_notes":1},"service":""},
		"guide":{"skill":"tracking","wage":26,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{},"service":"community"},
		"scout":{"skill":"combat","wage":28,"start":6,"end":14,"days":weekday,"inputs":{},"outputs":{},"service":"safety"},
		"hired_guard":{"skill":"combat","wage":27,"start":18,"end":2,"days":everyday,"inputs":{},"outputs":{},"service":"safety"},
		"explorer":{"skill":"research","wage":32,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{"research_notes":2},"service":""},
		"relic_hunter":{"skill":"research","wage":34,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{"research_notes":2},"service":""},
		"cartographer":{"skill":"reading","wage":32,"start":8,"end":17,"days":weekday,"inputs":{"paper":2},"outputs":{"map":1},"service":""},
		"monster_hunter":{"skill":"combat","wage":36,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{},"service":"safety"},
		"alchemist":{"skill":"alchemy","wage":36,"start":8,"end":17,"days":weekday,"inputs":{"herb":2,"water":1},"outputs":{"tonic":2},"service":""},
		"magic_researcher":{"skill":"research","wage":36,"start":8,"end":17,"days":weekday,"inputs":{"paper":1},"outputs":{"research_notes":2},"service":""},
		"artificer":{"skill":"crafting","wage":38,"start":8,"end":17,"days":weekday,"inputs":{"iron_ingot":1,"research_notes":1},"outputs":{"ward_charm":2},"service":""},
		"magical_healer":{"skill":"herbalism","wage":36,"start":8,"end":18,"days":everyday,"inputs":{"herb":2},"outputs":{"remedy":3},"service":""},
		"ward_specialist":{"skill":"crafting","wage":34,"start":8,"end":17,"days":weekday,"inputs":{"wood":1,"herb":1},"outputs":{"ward_charm":1},"service":""},
		"arcane_mentor":{"skill":"teaching","wage":34,"start":10,"end":18,"days":school_days,"inputs":{},"outputs":{},"service":"education"},
		"musician":{"skill":"performance","wage":26,"start":14,"end":22,"days":everyday,"inputs":{},"outputs":{},"service":"culture"},
		"singer":{"skill":"performance","wage":26,"start":14,"end":22,"days":everyday,"inputs":{},"outputs":{},"service":"culture"},
		"dancer":{"skill":"performance","wage":25,"start":14,"end":22,"days":everyday,"inputs":{},"outputs":{},"service":"culture"},
		"actor":{"skill":"performance","wage":27,"start":14,"end":22,"days":everyday,"inputs":{},"outputs":{},"service":"culture"},
		"storyteller":{"skill":"performance","wage":24,"start":14,"end":22,"days":everyday,"inputs":{},"outputs":{},"service":"culture"},
		"street_artist":{"skill":"performance","wage":26,"start":14,"end":22,"days":everyday,"inputs":{"wood":1},"outputs":{"artwork":1},"service":""},
		"impresario":{"skill":"performance","wage":30,"start":14,"end":22,"days":everyday,"inputs":{},"outputs":{},"service":"culture"},
		"miner":{"skill":"mining","wage":25,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{"ore":4,"coal":2},"service":""},
		"lumberjack":{"skill":"woodcutting","wage":26,"start":8,"end":17,"days":weekday,"inputs":{},"outputs":{"log":3,"wood":4},"service":""},
		"miller":{"skill":"crafting","wage":23,"start":8,"end":17,"days":weekday,"inputs":{"wheat":3},"outputs":{"flour":6},"service":""},
		"fisher":{"skill":"fishing","wage":23,"start":6,"end":14,"days":weekday,"inputs":{},"outputs":{"fish":4},"service":""},
	}
	var result:Dictionary={}
	for id:String in City.PROFESSION_NAMES:
		var def:Dictionary=defs[id]
		result[id]={
			"id":id,
			"name":City.PROFESSION_NAMES[id],
			"venue_id":City.PROFESSION_VENUES[id],
			"skill":str(def.skill),
			"wage":int(def.wage),
			"start":int(def.start),
			"end":int(def.end),
			"days":def.days.duplicate(),
			"inputs":def.inputs.duplicate(),
			"outputs":def.outputs.duplicate(),
			"service":str(def.service),
			"minimum_age":int(def.get("minimum_age",18)),
		}
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
