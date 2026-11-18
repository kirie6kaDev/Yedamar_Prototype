extends RefCounted
## Prototype municipal rules. These are not a canonical legal system for all Yedamar.
const RANKS := [
	{"id":"ragged","name":"Оборванец","work":0,"reputation":0,"guild":0,"errands":0,"diploma":false,"days":0,"rights":"Временный приют, оплачиваемая работа и городские поручения."},
	{"id":"free","name":"Вольный житель","work":120,"reputation":10,"guild":0,"errands":1,"diploma":false,"days":0,"rights":"Ученичество, небольшой заём и право подать прошение о гражданстве."},
	{"id":"citizen","name":"Горожанин","work":480,"reputation":30,"guild":20,"errands":3,"diploma":false,"days":0,"rights":"Можно получить именное разрешение на покупку жилого участка или дома."},
	{"id":"honorary","name":"Почётный гражданин","work":1440,"reputation":80,"guild":100,"errands":6,"diploma":true,"days":2,"rights":"Можно получить разрешение на предприятие и основать городское объединение."},
	{"id":"noble","name":"Дворянин","work":3600,"reputation":170,"guild":250,"errands":12,"diploma":true,"days":5,"rights":"Признанный родовой титул; право назначить наследника в своём хозяйстве. Не монархическая власть над миром."}
]
const ERRANDS := {
	"food_aid":{"name":"Припасы для нуждающихся","venue":"life_town_hall","items":{"bread":2,"carrot":2},"work":0,"reward":5,"reputation":7,"guild":4},
	"repair_supplies":{"name":"Материалы для городской починки","venue":"life_builders","items":{"wood":4,"stone":3},"work":0,"reward":7,"reputation":8,"guild":5},
	"clinic_supplies":{"name":"Травы для лечебницы","venue":"life_clinic","items":{"herb":3,"water":2},"work":0,"reward":6,"reputation":8,"guild":4},
	"school_supplies":{"name":"Бумага для школы","venue":"life_school","items":{"paper":2,"bread":1},"work":0,"reward":5,"reputation":7,"guild":6},
	"honest_shift":{"name":"Три часа добросовестной службы","venue":"life_guild","items":{},"work":180,"reward":8,"reputation":10,"guild":8}
}
const EMOTIONS := {"fine":"Спокойствие","happy":"Радость","sad":"Грусть","angry":"Злость","confident":"Уверенность","energized":"Бодрость","focused":"Сосредоточенность","inspired":"Вдохновение","flirty":"Романтическое настроение","playful":"Игривость","tense":"Напряжение","uncomfortable":"Дискомфорт","embarrassed":"Смущение","bored":"Скука","scared":"Страх"}
const WISHES := {
	"meal":{"name":"Поесть с удовольствием","actions":["eat"],"target":1,"reward":12},
	"friend":{"name":"Поговорить с другим человеком","actions":["socialize","compliment"],"target":1,"reward":15},
	"work":{"name":"Честно закончить рабочий час","actions":["work"],"target":1,"reward":18},
	"learn":{"name":"Узнать что-нибудь новое","actions":["read","study","lesson"],"target":1,"reward":15},
	"cook":{"name":"Приготовить еду своими руками","actions":["cook"],"target":1,"reward":15},
	"garden":{"name":"Позаботиться о саде","actions":["farm_water","farm_harvest","farm_tend","farm_plant"],"target":2,"reward":18},
	"rest":{"name":"Устроить себе спокойный отдых","actions":["relax","sleep"],"target":1,"reward":12},
	"service":{"name":"Помочь поселению","actions":["deliver_errand"],"target":1,"reward":20},
	"courage":{"name":"Справиться со страхом","actions":["calm_fear"],"target":1,"reward":20}
}
const FEARS := {
	"failure":{"name":"Страх неудачи","advice":"Завершайте работу, учитесь и спокойно обсудите неудачу."},
	"poverty":{"name":"Страх нужды","advice":"Оплатите просроченные обязательства и восстановите небольшой запас средств."},
	"dark":{"name":"Страх темноты","advice":"Вернитесь в безопасное место и успокойтесь; работа со страхом требует спокойной обстановки."},
	"isolation":{"name":"Страх одиночества","advice":"Общайтесь и восстанавливайте близкие отношения."}
}
const REWARDS := {
	"composure":{"name":"Внутренняя опора","cost":35,"description":"Ослабляет активные страхи на 25 и даёт спокойное настроение на четыре часа."},
	"focus":{"name":"Учебный настрой","cost":45,"description":"Сосредоточенность на четыре часа: успешная учёба и работа дают небольшой дополнительный опыт."},
	"second_wind":{"name":"Второе дыхание","cost":40,"description":"Восстанавливает 25 пунктов сна и даёт краткую бодрость."}
}
const CLUB_ACTIVITIES := {"read":"Кружок чтения","train":"Учебное товарищество","socialize":"Круг соседей"}
const PUBLIC_ONLY := ["life_player_home","life_town_hall","life_watch","life_school","life_library","life_clinic","life_graveyard","life_temple","life_guild","life_academy","life_square","life_south_square","life_post"]
const ACTIONS := {
	"petition":{"name":"Подать прошение о статусе","duration":20.0,"venue":"life_town_hall"},
	"collect_status":{"name":"Получить свидетельство","duration":10.0,"venue":"life_town_hall"},
	"permit":{"name":"Оформить именное разрешение","duration":15.0,"venue":"life_town_hall"},
	"accept_errand":{"name":"Взять городское поручение","duration":8.0,"venue":"life_town_hall"},
	"deliver_errand":{"name":"Сдать городское поручение","duration":15.0},
	"apprentice":{"name":"Записаться в ученики","duration":20.0,"venue":"life_guild"},
	"lesson":{"name":"Занятие с мастером","duration":40.0,"venue":"life_guild"},
	"exam":{"name":"Сдать квалификационный экзамен","duration":45.0,"venue":"life_guild"},
	"pay_tax":{"name":"Оплатить имущественный сбор","duration":10.0,"venue":"life_town_hall"},
	"take_loan":{"name":"Получить заём на 40 монет","duration":15.0,"venue":"life_town_hall"},
	"repay_loan":{"name":"Вернуть 44 монеты","duration":10.0,"venue":"life_town_hall"},
	"pay_fine":{"name":"Оплатить штраф","duration":10.0,"venue":"life_town_hall"},
	"appeal_fine":{"name":"Подать объяснение по штрафу","duration":20.0,"venue":"life_town_hall"},
	"calm_fear":{"name":"Успокоиться в безопасном месте","duration":25.0},
	"reward":{"name":"Потратить удовлетворённость","duration":0.0,"portable":true},
	"dismiss_wish":{"name":"Отпустить желание","duration":0.0,"portable":true},
	"found_club":{"name":"Основать городское объединение","duration":25.0,"venue":"life_guild"},
	"invite_club":{"name":"Пригласить в объединение","duration":15.0},
	"gather_club":{"name":"Провести встречу объединения","duration":45.0},
	"name_house":{"name":"Название и знак рода","duration":0.0,"portable":true},
	"name_heir":{"name":"Назначить наследника","duration":15.0,"venue":"life_town_hall"}
}
