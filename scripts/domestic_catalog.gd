extends RefCounted

const ACTIONS := {
	"clean":{"name":"Вымыть и убрать","duration":18.0,"skill":"crafting","xp":3.0},
	"repair":{"name":"Починить","duration":35.0,"skill":"crafting","xp":12.0},
	"upgrade":{"name":"Укрепить соединения","duration":45.0,"skill":"crafting","xp":16.0},
	"fuel":{"name":"Подложить дрова","duration":9.0,"skill":"crafting","xp":2.0},
	"light":{"name":"Развести огонь","duration":8.0,"skill":"cooking","xp":2.0},
	"douse":{"name":"Погасить очаг","duration":6.0,"skill":"crafting","xp":1.0},
	"extinguish":{"name":"Потушить пожар водой","duration":12.0,"skill":"crafting","xp":10.0},
	"cook":{"name":"Приготовить семейное блюдо","duration":35.0,"skill":"cooking","xp":14.0},
	"eat":{"name":"Взять порцию","duration":16.0,"skill":"cooking","xp":1.0},
	"store_food":{"name":"Убрать остатки в кладовую","duration":10.0,"skill":"cooking","xp":2.0},
	"serve_food":{"name":"Подать еду на стол","duration":8.0,"skill":"cooking","xp":2.0},
	"discard_food":{"name":"Выбросить испорченную еду","duration":10.0,"skill":"crafting","xp":2.0},
	"wash_dishes":{"name":"Вымыть грязную посуду","duration":20.0,"skill":"crafting","xp":4.0},
	"collect_laundry":{"name":"Собрать грязное бельё","duration":12.0,"skill":"crafting","xp":3.0},
	"wash_laundry":{"name":"Выстирать бельё в тазу","duration":30.0,"skill":"crafting","xp":7.0},
	"hang_laundry":{"name":"Развесить мокрое бельё","duration":16.0,"skill":"crafting","xp":4.0},
	"fold_laundry":{"name":"Снять и сложить сухое бельё","duration":15.0,"skill":"crafting","xp":4.0},
	"change_linen":{"name":"Сменить бельё и одежду","duration":15.0,"skill":"crafting","xp":3.0},
	"warm_clothes":{"name":"Сшить тёплую накидку","duration":35.0,"skill":"tailoring","xp":12.0},
	"remove_cloak":{"name":"Снять тёплую накидку","duration":5.0,"skill":"tailoring","xp":0.0},
	"doctor":{"name":"Осмотр и лечение у лекаря · 8 монет","duration":35.0,"skill":"herbalism","xp":3.0},
	"herbal_care":{"name":"Приготовить лечебный настой","duration":25.0,"skill":"herbalism","xp":7.0},
	"rest":{"name":"Отлежаться под одеялом","duration":45.0,"skill":"herbalism","xp":2.0},
	"feed_child":{"name":"Покормить малыша","duration":20.0,"skill":"parenting","xp":8.0},
	"change_child":{"name":"Вымыть малыша и сменить пелёнки","duration":25.0,"skill":"parenting","xp":8.0},
	"soothe_child":{"name":"Убаюкать малыша","duration":30.0,"skill":"parenting","xp":8.0}
}
const RECIPES := {
	"porridge":{"name":"Зерновая каша","cost":{"wheat":2,"water":1},"portions":4,"nutrition":48.0,"life":360.0},
	"stew":{"name":"Овощная похлёбка","cost":{"carrot":3,"water":1},"portions":4,"nutrition":56.0,"life":300.0},
	"fish_soup":{"name":"Рыбная уха","cost":{"fish":2,"water":1},"portions":4,"nutrition":65.0,"life":240.0},
	"bread":{"name":"Домашние лепёшки","cost":{"flour":2,"water":1},"portions":4,"nutrition":45.0,"life":720.0}
}
const HEAT := ["hearth","cauldron","kiln","campfire"]
const MAINTAINED := ["bed","bath","washbasin","latrine","hearth","dining","table","bench","bookshelf","pantry","storage","cauldron","loom","kiln","training","well","wash_tub","drying_line","basket","cradle"]
const NAMES := {"basket":"Корзина для белья","wash_tub":"Таз для стирки","drying_line":"Верёвка для сушки","cradle":"Колыбель"}
const DISEASES := {"":"Здоров","cold":"Простуда","food":"Расстройство желудка","fever":"Лихорадка от сырости"}
