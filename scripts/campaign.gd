extends RefCounted

const ITEMS := {
	"fishing_rod":"Удочка","lute":"Лютня","wand":"Ученический жезл","trout":"Форель","amber":"Янтарь","quartz":"Кварц","fossil":"Окаменелость","beetle":"Лесной жук","butterfly":"Луговая бабочка","river_pearl":"Речная жемчужина",
	"wheat":"Зерно","flour":"Мука","bread":"Хлеб","meal":"Похлёбка","fish":"Рыба","meat":"Мясо","milk":"Молоко","egg":"Яйцо",
	"wool":"Шерсть","hide":"Шкуры","iron_tool":"Железные инструменты","cloth":"Ткань","clothing":"Рабочая одежда",
	"leather":"Кожа","pottery":"Посуда","jewelry":"Украшения","ale":"Эль","book":"Книга","paper":"Писчие листы",
	"remedy":"Лекарственный сбор","tonic":"Травяной настой","research_notes":"Исследовательские записи","ward_charm":"Защитное изделие","map":"Карта дорог","artwork":"Художественная работа",
	"branch": "Ветки", "stone": "Камни", "wood": "Древесина",
	"herb": "Лечебные травы", "berry": "Ягоды", "ore": "Железная руда",
	"pickaxe": "Каменная кирка", "sword": "Деревянный меч",
	"bandage": "Повязки", "ration": "Дорожная еда", "water": "Вода",
	"mint": "Мята", "lavender": "Лаванда", "healing_potion": "Лечебное зелье",
	"stamina_potion": "Зелье бодрости", "hay": "Сено", "carrot": "Морковь", "parcel": "Посылка Марты",
	"hoe": "Мотыга", "axe": "Топор", "saw": "Пила", "log": "Брёвна", "plank": "Доски",
	"coal": "Древесный уголь", "iron_ingot": "Железный слиток", "iron_blank": "Кованая заготовка",
	"iron_sword": "Железный меч", "iron_armor": "Железный доспех", "bow": "Охотничий лук", "arrow": "Стрелы",
	"seeds_carrot": "Семена моркови", "seeds_herb": "Семена трав", "apple_sapling": "Саженец яблони", "apple": "Яблоки"
}
const SKILLS := {
	"magic":"Практическая магия","painting":"Живопись",
	"social":"Общение","literacy":"Грамотность","athletics":"Физическая подготовка",
	"charisma":"Общение","trade":"Торговля","reading":"Грамотность","teaching":"Наставничество","combat":"Военное дело",
	"fishing":"Рыболовство","tracking":"Следопытство","research":"Исследования","performance":"Выступления",
	"tailoring":"Портняжное дело","leatherworking":"Кожевенное дело","pottery":"Гончарное дело","jewelry":"Ювелирное дело",
	"potion_brewing": "Зельеварение",
	"crafting": "Ремесло", "woodcutting": "Лесозаготовка", "carpentry": "Плотницкое дело",
	"blacksmithing": "Кузнечное дело", "weapon_smith": "Оружейное дело", "armor_smith": "Изготовление доспехов",
	"farming": "Земледелие", "alchemy": "Алхимия", "cooking": "Готовка", "herbalism": "Травничество",
	"animal_husbandry": "Животноводство", "mining": "Горное дело"
}
const EQUIPMENT := ["pickaxe", "hoe", "axe", "saw", "sword", "iron_sword", "iron_armor", "bow", "fishing_rod", "lute", "wand"]
const CONSUMABLES := ["bandage", "ration", "water", "berry", "carrot", "apple", "healing_potion", "stamina_potion", "bread", "meal", "fish", "meat", "milk", "egg", "remedy", "tonic"]
const RECIPES := {
	"fishing_rod":{"name":"Удочка","cost":{"branch":3,"wool":1},"item":"fishing_rod","count":1,"duration":50.0,"station":"workbench","skill":"carpentry","xp":20,"needs_tool":"","description":"Упругое удилище и нить. Ягоды можно использовать как наживку."},
	"lute":{"name":"Простая лютня","cost":{"plank":4,"wool":2},"item":"lute","count":1,"duration":80.0,"station":"workbench","skill":"carpentry","xp":30,"needs_tool":"","description":"Собрать деревянный корпус и струны для занятий музыкой."},
	"wand":{"name":"Ученический жезл","cost":{"branch":2,"quartz":1},"item":"wand","count":1,"duration":45.0,"station":"","skill":"crafting","xp":20,"needs_tool":"","description":"Закрепить найденный кристалл. Заклинания изучаются отдельно в академии."},
	"stone_pickaxe": {"name": "Каменная кирка", "cost": {"stone": 3, "branch": 2}, "item": "pickaxe", "count": 1, "duration": 40.0, "station": "", "skill": "crafting", "xp": 18, "needs_tool": "", "description": "Связать рукоять с каменным остриём."},
	"wooden_sword": {"name": "Деревянный меч", "cost": {"branch": 3, "stone": 1}, "item": "sword", "count": 1, "duration": 45.0, "station": "", "skill": "weapon_smith", "xp": 20, "needs_tool": "", "description": "Первое тренировочное оружие; развивает оружейное дело."},
	"bandage": {"name": "Травяная повязка", "cost": {"herb": 2}, "item": "bandage", "count": 1, "duration": 20.0, "station": "", "skill": "crafting", "xp": 8, "needs_tool": "", "description": "Подготовить лечебные листья и перевязочный материал."},
	"camp_ration": {"name": "Дорожная еда", "cost": {"berry": 2, "wood": 1}, "item": "ration", "count": 1, "duration": 35.0, "station": "campfire", "skill": "cooking", "xp": 15, "needs_tool": "", "description": "Готовится у костра; древесина служит топливом."},
	"healing_potion": {"name": "Лечебное зелье", "cost": {"herb": 2, "mint": 1, "water": 1}, "item": "healing_potion", "count": 1, "duration": 60.0, "station": "cauldron", "skill": "alchemy", "xp": 25, "needs_tool": "", "description": "После урока травницы смешать настой в алхимическом котле."},
	"stamina_potion": {"name": "Зелье бодрости", "cost": {"lavender": 2, "berry": 1, "water": 1}, "item": "stamina_potion", "count": 1, "duration": 60.0, "station": "cauldron", "skill": "alchemy", "xp": 25, "needs_tool": "", "description": "После урока травницы сварить бодрящий отвар."},
	"stone_hoe": {"name": "Мотыга", "cost": {"stone": 2, "branch": 3}, "item": "hoe", "count": 1, "duration": 40.0, "station": "", "skill": "crafting", "xp": 18, "needs_tool": "", "description": "Ручной инструмент для подготовки грядок."},
	"stone_axe": {"name": "Топор", "cost": {"stone": 3, "branch": 2}, "item": "axe", "count": 1, "duration": 45.0, "station": "", "skill": "crafting", "xp": 20, "needs_tool": "", "description": "Нужен для рубки отмеченных деревьев."},
	"iron_saw": {"name": "Пила", "cost": {"iron_ingot": 1, "branch": 2}, "item": "saw", "count": 1, "duration": 65.0, "station": "anvil", "skill": "blacksmithing", "xp": 25, "needs_tool": "", "description": "Позволяет распиливать брёвна на верстаке."},
	"plank_saw": {"name": "Доски на верстаке", "cost": {"log": 1}, "item": "plank", "count": 3, "duration": 45.0, "station": "workbench", "skill": "carpentry", "xp": 18, "needs_tool": "saw", "description": "Одна пила в личном рюкзаке; инструмент сохраняется."},
	"plank_mill": {"name": "Доски на пилораме", "cost": {"log": 1}, "item": "plank", "count": 4, "duration": 30.0, "station": "sawmill", "skill": "carpentry", "xp": 20, "needs_tool": "", "description": "Стационарная пила даёт четыре доски из бревна."},
	"charcoal": {"name": "Древесный уголь", "cost": {"wood": 3}, "item": "coal", "count": 3, "duration": 60.0, "station": "campfire", "skill": "crafting", "xp": 16, "needs_tool": "", "description": "Обжечь древесину для кузнечного топлива."},
	"smelt_iron": {"name": "Железный слиток", "cost": {"ore": 3, "coal": 1}, "item": "iron_ingot", "count": 1, "duration": 75.0, "station": "smelter", "skill": "blacksmithing", "xp": 25, "needs_tool": "", "description": "Переплавить руду в печи. Доступно начинающему кузнецу."},
	"forge_blank": {"name": "Кованая заготовка", "cost": {"iron_ingot": 1, "coal": 1}, "item": "iron_blank", "count": 1, "duration": 60.0, "station": "anvil", "skill": "blacksmithing", "xp": 22, "needs_tool": "", "description": "Проковать нагретый слиток на наковальне."},
	"iron_sword": {"name": "Железный меч", "cost": {"iron_blank": 2, "plank": 1, "coal": 1}, "item": "iron_sword", "count": 1, "duration": 90.0, "station": "anvil", "skill": "weapon_smith", "xp": 40, "needs_tool": "", "description": "Оружейная специализация: собрать и закалить клинок."},
	"iron_armor": {"name": "Железный доспех", "cost": {"iron_blank": 3, "coal": 2}, "item": "iron_armor", "count": 1, "duration": 90.0, "station": "anvil", "skill": "armor_smith", "xp": 45, "needs_tool": "", "description": "Кузнечная специализация: выковать и соединить защитные пластины."},
	"hunting_bow": {"name": "Охотничий лук", "cost": {"plank": 2, "branch": 2}, "item": "bow", "count": 1, "duration": 65.0, "station": "workbench", "skill": "weapon_smith", "xp": 28, "needs_tool": "", "description": "Выстрогать гибкие плечи и натянуть тетиву."},
	"arrows": {"name": "Шесть стрел", "cost": {"branch": 2, "stone": 1}, "item": "arrow", "count": 6, "duration": 30.0, "station": "workbench", "skill": "weapon_smith", "xp": 12, "needs_tool": "", "description": "Подготовить древки и каменные наконечники."},
	"carrot_seeds": {"name": "Семена моркови", "cost": {"carrot": 2}, "item": "seeds_carrot", "count": 4, "duration": 25.0, "station": "", "skill": "farming", "xp": 10, "needs_tool": "", "description": "Отобрать посадочный материал для четырёх грядок."},
	"herb_seeds": {"name": "Семена лечебных трав", "cost": {"herb": 2}, "item": "seeds_herb", "count": 4, "duration": 25.0, "station": "", "skill": "farming", "xp": 10, "needs_tool": "", "description": "Отобрать семена лекарственных растений."},
	"apple_sapling": {"name": "Саженец яблони", "cost": {"apple": 2, "water": 1}, "item": "apple_sapling", "count": 1, "duration": 60.0, "station": "", "skill": "farming", "xp": 20, "needs_tool": "", "description": "Подготовить молодой саженец для сада."}
}
const OBJECTIVES := [
	"Поговорите с хозяйкой фермы. Нажмите на Марту и выберите «Поговорить».",
	"Соберите 3 камня и 2 ветки. В разделе «Крафт» сделайте каменную кирку.",
	"Зайдите к стражнику Арденхольма. Он знает, что случилось на дороге.",
	"Найдите травы в Эйваре, помогите отбиться от мародёров и сделайте повязку.",
	"Доберитесь до штольни, поговорите с горняком и добудьте 3 куска руды.",
	"Победите Стража выработки. Брат сражается автоматически, сестра ищет укрытие.",
	"Вернитесь к Марте с рудой и расскажите о найденной выработке.",
	"Первое путешествие завершено. Лиора открыта для свободного исследования."
]

static func new_state() -> Dictionary:
	return {
		"version": 2, "elapsed": 0.0,
		"characters": {
			"brother": character_state({"ration": 2, "water": 3, "bandage": 1}, 100.0),
			"sister": character_state({"ration": 1, "water": 2}, 80.0)
		},
		"flags": {}, "depleted": [], "defeated": [],
		"stage": 0, "gathered_ore": 0, "selected": "brother",
		"auto_elapsed": 0.0, "auto_index": 0
	}

static func character_state(inventory: Dictionary, health: float) -> Dictionary:
	return {"inventory": inventory.duplicate(true), "health": health, "stamina": 100.0,
		"hunger": 100.0, "thirst": 100.0, "sleep": 100.0, "skills": skill_defaults(),
		"work_mode": "", "allow_new_plots": false, "follow": false,
		"hotbar": ["pickaxe", "sword", "bandage", "ration", "water", "healing_potion"], "equipped": ""}

static func skill_defaults() -> Dictionary:
	var result: Dictionary = {}
	for skill: String in SKILLS:
		result[skill] = 0.0
	return result

static func skill_level(person: Dictionary, skill: String) -> int:
	return maxi(0, floori(float(person.get("skills", {}).get(skill, 0.0)) / 100.0))

static func objective(stage: int) -> String:
	return OBJECTIVES[clampi(stage, 0, OBJECTIVES.size() - 1)]

static func journal(stage: int) -> String:
	return "ДОРОГА ЧЕРЕЗ ЛИОРУ\n\nБрат и младшая сестра готовятся к большому путешествию. Их первый приют — отдельная ферма возле Арденхольма. Хозяйке нужны железо и вести о старой штольне.\n\nТекущая цель\n" + objective(stage) + "\n\nМаршрут\nФерма → Арденхольм → опушка Эйвара → штольня → ферма.\n\nПрипасы\nНажимайте на предметы, чтобы изучать и собирать их. Кирка требует 3 камня и 2 ветки, меч — 3 ветки и 1 камень. Для повязки нужны 2 травы, для еды у костра — 2 ягоды и древесина. Работа занимает время; материалы расходуются только после завершения.\n\nМастерские\nТопором рубят отмеченные деревья. Брёвна распиливают пилой на верстаке либо на пилораме. Руду с углём плавят в слитки, затем на наковальне делают заготовки, мечи и доспехи. Оружейное, бронное и кузнечное дело имеют отдельный опыт.\n\nСемья\nВне боя выбирайте любого из двоих. У каждого собственная очередь поручений; следование включается отдельно. В бою брат защищает сестру, а она ищет кусты или бочку. Можно отвести брата кликом по земле.\n\nОтдых\nУ колодца можно попить и набрать воду. Костёр восстанавливает силы. Повязки и еду используйте через инвентарь.\n\nУправление\nЛевая кнопка — идти или открыть меню предмета. Колесо — масштаб. Средняя кнопка — вращать камеру. WASD — сдвиг камеры. Пробел — вернуться к выбранному персонажу. Tab — сменить героя. I — инвентарь. C — крафт. F5 — сохранить. F9 — загрузить."
