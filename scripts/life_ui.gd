extends RefCounted
## Data-only life presentation. Main owns commands, validation and simulation.

const TABS := {"profile":"Персонаж","people":"Люди","careers":"Работа","market":"Рынок","home":"Дом","civic":"Статус","pursuits":"Занятия","calendar":"Календарь"}
const TAB_ICONS := {"profile":"mood","people":"people","careers":"career","market":"market","home":"life","civic":"career","pursuits":"skills","calendar":"calendar"}
const PURSUITS := {"activities":"Занятия на карте","collections":"Коллекции","magic":"Магия","wishes":"Желания","fears":"Страхи","sentiments":"Чувства к людям","emotions":"Эмоции","guilds":"Обучение и объединения"}
const PROFILE_TABS := {"needs":"Самочувствие","personality":"Характер","skills":"Навыки","memories":"Память","family":"Родня","appearance":"Облик"}
const NEED_ICONS := {"hunger":"ration","thirst":"thirst","energy":"sleep","sleep":"sleep","stamina":"stamina","health":"health","hygiene":"hygiene","bladder":"bladder","social":"social","fun":"fun","comfort":"comfort"}

var host: CanvasLayer
var panel: PanelContainer
var model: Dictionary = {}
var tab := "profile"
var profile_tab := "needs"
var home_tab := "household"
var calendar_tab := "calendar"
var pursuit_tab := "activities"
var _rail_buttons: Dictionary = {}
var _page_title: Label
var _page_subtitle: Label
var _content: VBoxContainer
var _subnav: HBoxContainer
var _page: VBoxContainer
var _search: LineEdit
var _list: VBoxContainer
var _detail: VBoxContainer
var _list_buttons: Dictionary = {}
var _list_identity := ""
var _record_id := ""
var _record_key := -1
var _detail_record_id := "__none__"
var _detail_title: Label
var _detail_text: Label
var _detail_actions: VBoxContainer
var _detail_action_key := -1
var _need_rows: Dictionary = {}
var _mood_label: Label
var _mood_list: VBoxContainer
var _mood_key := -1
var _care_actions: VBoxContainer
var _care_key := -1
var _timeline: VBoxContainer
var _timeline_key := -1
var _family_tree: Tree
var _draft: Dictionary = {}
var _draft_owner := ""
var _trait_checks: Dictionary = {}
var _trait_count: Label
var _name_edit: LineEdit
var _form_key := ""
var _active_profile := ""
var _search_text := ""
var _goals_list: VBoxContainer
var _goals_key := -1
var _header_budget: Label
var _header_speeds: HBoxContainer
var _header_speed_buttons: Dictionary = {}
var _header_speed_key := -1


func _init(owner_hud: CanvasLayer) -> void:
	host=owner_hud
	var window: Dictionary=host._window("Noctis Live · Жизнь",host._close_windows)
	panel=window.panel
	var header: Node=window.title.get_parent()
	var close_button: Node=header.get_child(1)
	host._icon(header,"money",27)
	_header_budget=host._label(header,"",20,host.GOLD)
	_header_speeds=host._hbox(header,4)
	header.move_child(close_button,header.get_child_count()-1)
	var columns: HBoxContainer=host._hbox(window.body,18)
	columns.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var rail: VBoxContainer=host._vbox(columns,7)
	rail.custom_minimum_size.x=174
	for id in TABS:
		var button: Button=host._button(rail,TABS[id],func():show_tab(id),Vector2(174,46),TAB_ICONS[id])
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		_rail_buttons[id]=button
	_content=host._vbox(columns,10)
	_content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_page_title=host._label(_content,"",25,host.GOLD)
	_page_title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	_page_subtitle=host._wrapped(_content,"",20,host.MUTED)
	_subnav=host._hbox(_content,6)
	_page=host._vbox(_content,10)
	_page.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_build_page()


func update_model(data: Dictionary) -> void:
	var previous_id := str(model.get("selected",{}).get("id",""))
	model=data
	_refresh_header()
	if previous_id!=str(model.get("selected",{}).get("id","")):
		_draft_owner=""
		_form_key=""
		_record_key=-1
		if panel.visible and tab=="profile":
			_build_page()
	if panel.visible:
		_refresh()


func show_tab(id: String,subtab: String="") -> void:
	if not TABS.has(id):
		return
	tab=id
	if id=="profile" and not subtab.is_empty():
		profile_tab=subtab
	_record_id=""
	_record_key=-1
	_detail_record_id="__none__"
	_list_identity=""
	_search_text=""
	_build_page()
	_refresh()
	host._settle_window_layout.call_deferred()


func refresh_visible() -> void:
	_refresh_header()
	_refresh()


func _refresh_header() -> void:
	var summary: Dictionary=model.get("summary",{})
	_header_budget.text=_money(summary.get("funds",0))+" "+str(summary.get("currency",""))
	var actions: Array=summary.get("speed_actions",[])
	if hash(actions)!=_header_speed_key:
		_header_speed_key=hash(actions)
		host._clear(_header_speeds)
		_header_speed_buttons.clear()
		for action in actions:
			var button: Button=host._button(_header_speeds,str(action.get("label","")),func():_emit(action),Vector2(42,40))
			button.disabled=not bool(action.get("enabled",true))
			button.tooltip_text=str(action.get("reason","Скорость жизни"))
			_header_speed_buttons[str(action.get("payload",{}).get("value",action.get("label","")))]=button
	for value in _header_speed_buttons:
		_header_speed_buttons[value].add_theme_stylebox_override("normal",host._style(Color("#29443a"),host.GOLD if is_equal_approx(float(value),float(summary.get("speed",1))) else host.BORDER,5,6))


func _selected() -> Dictionary:
	return model.get("selected",{})


func _row_name(row: Dictionary) -> String:
	return str(row.get("name",row.get("title",row.get("id",""))))


func _details(row: Dictionary) -> String:
	var lines := PackedStringArray()
	for line in row.get("details",[]):
		lines.append(str(line))
	return "\n".join(lines)


func _lookup_name(rows: Array,id: String) -> String:
	for row in rows:
		if str(row.get("id",""))==id:
			return _row_name(row)
	return id


func _build_page() -> void:
	host._clear(_subnav)
	host._clear(_page)
	_need_rows.clear()
	_mood_key=-1
	_care_key=-1
	_timeline_key=-1
	_goals_key=-1
	_record_key=-1
	_detail_record_id="__none__"
	_list_identity=""
	for id in _rail_buttons:
		_rail_buttons[id].add_theme_stylebox_override("normal",host._style(Color("#29443a"),host.GOLD if id==tab else host.BORDER,6,10))
	if tab=="profile":
		for id in PROFILE_TABS:
			var button: Button=host._button(_subnav,PROFILE_TABS[id],func():
				profile_tab=id
				_build_page()
				_refresh(),Vector2(0,43))
			button.add_theme_stylebox_override("normal",host._style(Color("#29443a"),host.GOLD if id==profile_tab else host.BORDER,6,8))
		_build_profile()
	elif tab=="home":
		for entry in [["household","Семья"],["properties","Жильё"],["animals","Животные"],["domestic","Быт"],["buildings","Постройки"]]:
			var id: String=entry[0]
			var button: Button=host._button(_subnav,entry[1],func():
				home_tab=id
				_record_id=""
				_build_page()
				_refresh(),Vector2(0,44))
			button.add_theme_stylebox_override("normal",host._style(Color("#29443a"),host.GOLD if id==home_tab else host.BORDER,6,10))
		var roof_actions: Array=model.get("summary",{}).get("cutaway_actions",[])
		if not roof_actions.is_empty():
			var roofs := MenuButton.new()
			roofs.text="Крыши"
			roofs.flat=false
			roofs.custom_minimum_size=Vector2(120,44)
			roofs.set_meta("base_font_size",20)
			roofs.add_theme_font_size_override("font_size",roundi(20*host._text_scale))
			roofs.add_theme_stylebox_override("normal",host._style(Color("#29443a"),host.BORDER,6,10))
			roofs.add_theme_stylebox_override("hover",host._style(Color("#3b5547"),host.GOLD,6,10))
			_subnav.add_child(roofs)
			var popup := roofs.get_popup()
			popup.add_theme_font_size_override("font_size",roundi(20*host._text_scale))
			popup.add_theme_stylebox_override("panel",host._style(host.PANEL,host.BORDER,6,12))
			for index in range(roof_actions.size()):
				popup.add_item(str(roof_actions[index].get("label","")),index)
				popup.set_item_disabled(index,not bool(roof_actions[index].get("enabled",true)))
			popup.id_pressed.connect(func(index):_emit(roof_actions[index]))
		_build_browser()
	elif tab=="pursuits":
		var choose:=OptionButton.new()
		choose.custom_minimum_size=Vector2(360,45)
		choose.add_theme_font_size_override("font_size",roundi(20*host._text_scale))
		_subnav.add_child(choose)
		for id in PURSUITS:
			choose.add_item(PURSUITS[id])
			if id==pursuit_tab: choose.select(choose.item_count-1)
		choose.item_selected.connect(func(index):
			pursuit_tab=PURSUITS.keys()[index]
			_record_id=""; _build_page(); _refresh())
		_build_browser()
	elif tab=="calendar":
		for entry in [["calendar","Расписание"],["events","События мира"]]:
			var id: String=entry[0]
			var button: Button=host._button(_subnav,entry[1],func():
				calendar_tab=id
				_record_id=""
				_build_page()
				_refresh(),Vector2(0,44))
			button.add_theme_stylebox_override("normal",host._style(Color("#29443a"),host.GOLD if id==calendar_tab else host.BORDER,6,10))
		_build_browser()
	else:
		_build_browser()
	_subnav.visible=_subnav.get_child_count()>0


func _build_profile() -> void:
	var scroll: ScrollContainer=host._scroll(_page)
	var body: VBoxContainer=host._vbox(scroll,13)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	match profile_tab:
		"needs":
			_mood_label=host._label(body,"",24,host.GOLD)
			var grid := GridContainer.new()
			grid.columns=2
			grid.add_theme_constant_override("h_separation",18)
			grid.add_theme_constant_override("v_separation",9)
			grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			body.add_child(grid)
			var needs: Dictionary=_selected().get("needs",{})
			var labels: Dictionary=model.get("catalog",{}).get("need_labels",{})
			var order: Array=[]
			for key in NEED_ICONS:
				if needs.has(key): order.append(key)
			for key in needs:
				if key not in order:order.append(key)
			for key in order:
				var card: PanelContainer=host._panel(grid,11,Color("#20392f"))
				card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
				var box: VBoxContainer=host._vbox(card,7)
				var row: HBoxContainer=host._hbox(box,9)
				host._icon(row,NEED_ICONS.get(key,"mood"),28)
				var label: Label=host._label(row,str(labels.get(key,key)),20)
				label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
				var value: Label=host._label(row,"",20,host.PAPER)
				var bar: ProgressBar=host._progress(box,host.GREEN,8)
				_need_rows[key]={"value":value,"bar":bar}
			host._label(body,"Что влияет на настроение",22,host.GOLD)
			_mood_list=host._vbox(body,8)
			host._label(body,"Позаботиться о себе",22,host.GOLD)
			_care_actions=host._vbox(body,8)
		"personality":
			_build_personality(body)
		"appearance":
			_build_appearance(body)
		"family":
			_family_tree=Tree.new()
			_family_tree.custom_minimum_size.y=280
			_family_tree.size_flags_vertical=Control.SIZE_EXPAND_FILL
			_family_tree.hide_root=false
			_family_tree.columns=1
			_family_tree.add_theme_font_size_override("font_size",roundi(20*host._text_scale))
			_family_tree.set_meta("base_font_size",20)
			_family_tree.add_theme_color_override("font_color",host.PAPER)
			_family_tree.add_theme_stylebox_override("panel",host._style(Color("#20392f"),host.BORDER,6,14))
			body.add_child(_family_tree)
			host._wrapped(body,"Родственные связи принадлежат конкретным людям и сохраняются вместе с историей семьи.",20,host.MUTED)
		_:
			_timeline=host._vbox(body,12)
			_timeline.size_flags_horizontal=Control.SIZE_EXPAND_FILL


func _build_browser() -> void:
	_search=_input(_page,"", "Найти по имени или описанию")
	_search.text=_search_text
	_search.text_changed.connect(func(value):
		_search_text=value
		_list_identity=""
		_refresh_browser())
	var columns: HBoxContainer=host._hbox(_page,16)
	columns.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var list_scroll: ScrollContainer=host._scroll(columns,282)
	_list=host._vbox(list_scroll,7)
	_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var detail_scroll: ScrollContainer=host._scroll(columns)
	detail_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_detail=host._vbox(detail_scroll,12)
	_detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL


func _input(parent: Node,value: String,placeholder: String="") -> LineEdit:
	var input := LineEdit.new()
	input.text=value
	input.placeholder_text=placeholder
	input.custom_minimum_size.y=45
	input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	input.set_meta("base_font_size",20)
	input.add_theme_font_size_override("font_size",roundi(20*host._text_scale))
	input.add_theme_color_override("font_color",host.PAPER)
	input.add_theme_stylebox_override("normal",host._style(Color("#1b332c"),host.BORDER,6,10))
	input.add_theme_stylebox_override("focus",host._style(Color("#1b332c"),host.GOLD,6,10))
	parent.add_child(input)
	return input


func _source_rows() -> Array:
	if tab=="home":return model.get(home_tab,[])
	if tab=="pursuits":return model.get(pursuit_tab,[])
	if tab=="calendar":return model.get(calendar_tab,[])
	return model.get(tab,[])


func _refresh() -> void:
	var selected := _selected()
	var summary: Dictionary=model.get("summary",{})
	var name := str(selected.get("name","Персонаж"))
	_page_title.text=name if tab=="profile" else TABS[tab]
	var profession := str(selected.get("profession",""))
	if not profession.is_empty():profession=_lookup_name(model.get("careers",[]),profession)
	_page_subtitle.text="Выбран: "+name+(" · "+profession if not profession.is_empty() else "")
	if tab=="profile":
		_page_subtitle.text=("Возраст: "+str(floori(float(selected.get("age",0)))) if selected.has("age") else "")+(" · "+profession if not profession.is_empty() else "")
	elif tab=="home":
		_page_subtitle.text="%s · %s %s" % [summary.get("household","Семья"),_money(summary.get("funds",0)),summary.get("currency","")]
	elif tab=="calendar":
		_page_subtitle.text="%s · %s · %s" % [summary.get("date",""),summary.get("season",""),summary.get("weather","")]
	elif tab=="market":
		_page_subtitle.text="Получатель: %s · Бюджет семьи: %s %s" % [name,_money(summary.get("funds",0)),summary.get("currency","")]
	elif tab=="civic":
		_page_subtitle.text="%s · %s · Репутация: %d"%[name,summary.get("status",{}).get("rank_name","Оборванец"),int(summary.get("status",{}).get("reputation",0))]
	if tab=="profile":
		_refresh_profile()
	else:
		_refresh_browser()


func _money(amount: Variant) -> String:
	var number := int(amount)
	if abs(number)>=1000000:return "%.1f млн" % (float(number)/1000000.0)
	return str(number)


func _refresh_profile() -> void:
	var selected := _selected()
	if profile_tab=="needs":
		var needs: Dictionary=selected.get("needs",{})
		if needs.size()!=_need_rows.size():
			_build_page()
		var mood := float(selected.get("mood",0))
		_mood_label.text="Настроение · %+d" % roundi(mood)
		_mood_label.add_theme_color_override("font_color",host.GREEN if mood>=0 else host.RED)
		for key in _need_rows:
			var value := clampf(float(needs.get(key,0)),0,100)
			_need_rows[key].bar.value=value
			_need_rows[key].value.text=str(roundi(value))
			_need_rows[key].value.add_theme_color_override("font_color",host.RED if value<25 else host.PAPER)
		var moodlets: Array=selected.get("moodlets",[])
		if hash(moodlets)!=_mood_key:
			_mood_key=hash(moodlets)
			_render_rows(_mood_list,moodlets,"Сейчас нет отдельных эффектов настроения.")
		var actions: Array=selected.get("actions",[])
		if hash(actions)!=_care_key:
			_care_key=hash(actions)
			host._clear(_care_actions)
			_actions(_care_actions,actions,2)
	elif profile_tab=="memories" or profile_tab=="skills":
		var rows: Array=selected.get(profile_tab,[])
		if hash(rows)!=_timeline_key:
			_timeline_key=hash(rows)
			_render_rows(_timeline,rows,"Важные события ещё впереди." if profile_tab=="memories" else "Опыт появится после первых занятий.")
	elif profile_tab=="personality":
		var goals: Array=selected.get("goals",[])
		if goals.is_empty():
			for goal in model.get("catalog",{}).get("aspirations",[]):
				if str(goal.get("id",""))==str(selected.get("aspiration","")):goals=[goal]
		if hash(goals)!=_goals_key:
			_goals_key=hash(goals)
			_render_rows(_goals_list,goals,"Выберите стремление ниже, чтобы задать направление жизни.")
	elif profile_tab=="family":
		var family: Array=selected.get("family",[])
		var key := hash([selected.get("name",""),family])
		if key==_timeline_key:return
		_timeline_key=key
		_family_tree.clear()
		var root: TreeItem=_family_tree.create_item()
		root.set_text(0,str(selected.get("name","")))
		root.set_custom_color(0,host.GOLD)
		root.set_icon(0,host._texture("family"))
		root.set_icon_max_width(0,28)
		root.set_custom_minimum_height(42)
		for relative in family:
			var item: TreeItem=_family_tree.create_item(root)
			item.set_text(0,_row_name(relative))
			item.set_custom_minimum_height(40)
			for line in relative.get("details",[]):
				var detail: TreeItem=_family_tree.create_item(item)
				detail.set_text(0,str(line))
				detail.set_custom_color(0,host.MUTED)
				detail.set_custom_minimum_height(32)
		if family.is_empty():
			var empty: TreeItem=_family_tree.create_item(root)
			empty.set_text(0,"Родственные связи пока не записаны")
			empty.set_custom_color(0,host.MUTED)


func _refresh_browser() -> void:
	if not is_instance_valid(_list):return
	var rows: Array=[]
	var identities := PackedStringArray()
	for row in _source_rows():
		if not row is Dictionary:continue
		var haystack := (_row_name(row)+" "+_details(row)).to_lower()
		if not _search_text.is_empty() and not _search_text.to_lower() in haystack:continue
		rows.append(row)
		identities.append(str(row.get("id",""))+"|"+_row_name(row))
	var identity := "\n".join(identities)
	var found := false
	for row in rows:
		if str(row.get("id",""))==_record_id:found=true
	if not found:
		_record_id=str(rows[0].get("id","")) if not rows.is_empty() else ""
		_record_key=-1
	if identity!=_list_identity:
		_list_identity=identity
		host._clear(_list)
		_list_buttons.clear()
		for row in rows:
			var id := str(row.get("id",""))
			var button: Button=host._button(_list,"",func():
				_record_id=id
				_record_key=-1
				_refresh_browser(),Vector2(282,74))
			var label: Label=host._wrapped(button,_row_name(row),20)
			label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			label.offset_left=12
			label.offset_right=-12
			label.offset_top=8
			label.offset_bottom=-8
			label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
			button.tooltip_text=_row_name(row)
			_list_buttons[id]=button
	var active: Dictionary={}
	for row in rows:
		var id := str(row.get("id",""))
		if _list_buttons.has(id):
			_list_buttons[id].add_theme_stylebox_override("normal",host._style(Color("#243b31"),host.GOLD if id==_record_id else host.BORDER,6,10))
		if id==_record_id:active=row
	if hash(active)!=_record_key:
		_record_key=hash(active)
		if _detail_record_id!=_record_id:
			_detail_record_id=_record_id
			_detail_action_key=-1
			host._clear(_detail)
			_detail_title=host._wrapped(_detail,"",26,host.GOLD)
			_detail_text=host._wrapped(_detail,"",21)
			_detail_actions=host._vbox(_detail,8)
		_detail_title.text=_row_name(active)
		_detail_text.text="Ничего не найдено. Измените поиск или вернитесь позже." if active.is_empty() else _details(active)
		var actions: Array=active.get("actions",[])
		if hash(actions)!=_detail_action_key:
			_detail_action_key=hash(actions)
			host._clear(_detail_actions)
			_actions(_detail_actions,actions,2)


func _actions(parent: Node,actions: Array,columns: int=2) -> void:
	if actions.is_empty():return
	var grid := GridContainer.new()
	grid.columns=columns
	grid.add_theme_constant_override("h_separation",9)
	grid.add_theme_constant_override("v_separation",10)
	grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(grid)
	for action in actions:
		if not action is Dictionary or str(action.get("id","")).is_empty():continue
		var box: VBoxContainer=host._vbox(grid,6)
		box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var title := str(action.get("label",action.id))
		var button: Button=host._button(box,"",func():_emit(action),Vector2(0,68))
		button.set_meta("action_label",title)
		button.set_meta("life_action",str(action.id))
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.disabled=not bool(action.get("enabled",true))
		var label: Label=host._wrapped(button,title,20,host.MUTED if button.disabled else host.PAPER)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.offset_left=9
		label.offset_right=-9
		label.offset_top=6
		label.offset_bottom=-6
		label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var reason := str(action.get("reason",""))
		button.tooltip_text=title+("\n"+reason if not reason.is_empty() else "")
		if button.disabled and not reason.is_empty():
			host._wrapped(box,reason,20,host.RED)


func _emit(action: Dictionary) -> void:
	if not bool(action.get("enabled",true)):return
	var payload: Dictionary=action.get("payload",{}).duplicate(true)
	host.life_requested.emit(str(action.id),payload)


func _render_rows(parent: Node,rows: Array,empty_text: String) -> void:
	host._clear(parent)
	if rows.is_empty():
		host._wrapped(parent,empty_text,20,host.MUTED)
	for row in rows:
		var card: PanelContainer=host._panel(parent,12,Color("#20392f"))
		var box: VBoxContainer=host._vbox(card,7)
		host._wrapped(box,_row_name(row),22,host.GOLD)
		if not _details(row).is_empty():host._wrapped(box,_details(row),20)
		_actions(box,row.get("actions",[]))


func _ensure_draft() -> void:
	var selected := _selected()
	var id := str(selected.get("id",""))
	if _draft_owner==id:return
	_draft_owner=id
	_draft={"name":str(selected.get("name","")),"traits":selected.get("traits",[]).duplicate(),"preferences":selected.get("preferences",{}).duplicate(true),"aspiration":str(selected.get("aspiration","")),"appearance":selected.get("appearance",{}).duplicate(true)}


func _build_personality(parent: Node) -> void:
	_ensure_draft()
	var catalog: Dictionary=model.get("catalog",{})
	host._label(parent,"Жизненные цели",22,host.GOLD)
	_goals_list=host._vbox(parent,8)
	host._label(parent,"Имя",22,host.GOLD)
	_name_edit=_input(parent,str(_draft.get("name","")))
	_name_edit.max_length=64
	_name_edit.text_changed.connect(func(value):_draft.name=value)
	_trait_count=host._label(parent,"",22,host.GOLD)
	_trait_checks.clear()
	var traits_grid := GridContainer.new()
	traits_grid.columns=2
	traits_grid.add_theme_constant_override("h_separation",14)
	traits_grid.add_theme_constant_override("v_separation",8)
	traits_grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(traits_grid)
	for trait_entry in catalog.get("traits",[]):
		var id := str(trait_entry.get("id",""))
		var box: VBoxContainer=host._vbox(traits_grid,4)
		box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var check: CheckBox=host._check(box,_row_name(trait_entry),func(enabled):_trait_toggled(id,enabled))
		check.set_pressed_no_signal(id in _draft.traits)
		check.tooltip_text=_details(trait_entry)
		_trait_checks[id]=check
		if not _details(trait_entry).is_empty():host._wrapped(box,_details(trait_entry),20,host.MUTED)
	_update_trait_count()
	host._label(parent,"Предпочтения",22,host.GOLD)
	for preference in catalog.get("preferences",[]):
		var id := str(preference.get("id",""))
		_choice(parent,preference,str(_draft.preferences.get(id,"")),func(value):_draft.preferences[id]=value)
	host._label(parent,"Жизненная цель",22,host.GOLD)
	var aspirations: Array=catalog.get("aspirations",[])
	_choice(parent,{"id":"aspiration","name":"Стремление","options":aspirations},str(_draft.get("aspiration","")),func(value):_draft.aspiration=value)
	var aspiration_name := _lookup_name(aspirations,str(_selected().get("aspiration","")))
	if not aspiration_name.is_empty():host._wrapped(parent,"Текущая цель: "+aspiration_name,20,host.MUTED)
	_form_footer(parent,false)


func _trait_toggled(id: String,enabled: bool) -> void:
	var traits: Array=_draft.get("traits",[])
	if enabled and id not in traits:
		if traits.size()>=5:
			_trait_checks[id].set_pressed_no_signal(false)
			host.toast("Можно выбрать до пяти черт характера.")
			return
		traits.append(id)
	elif not enabled:traits.erase(id)
	_draft.traits=traits
	_update_trait_count()


func _update_trait_count() -> void:
	_trait_count.text="Черты характера · %d / 5" % _draft.get("traits",[]).size()


func _choice(parent: Node,definition: Dictionary,value: String,changed: Callable) -> void:
	var box: VBoxContainer=host._vbox(parent,5)
	host._label(box,_row_name(definition),20)
	var option := OptionButton.new()
	option.custom_minimum_size.y=46
	option.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	option.set_meta("base_font_size",20)
	option.add_theme_font_size_override("font_size",roundi(20*host._text_scale))
	option.add_theme_stylebox_override("normal",host._style(Color("#29443a"),host.BORDER,6,10))
	option.add_theme_stylebox_override("hover",host._style(Color("#3b5547"),host.GOLD,6,10))
	option.get_popup().add_theme_font_size_override("font_size",roundi(20*host._text_scale))
	option.get_popup().add_theme_stylebox_override("panel",host._style(host.PANEL,host.BORDER,6,12))
	box.add_child(option)
	var options: Array=definition.get("options",[])
	var selected_index := -1
	for entry in options:
		option.add_item(_row_name(entry))
		var index := option.item_count-1
		option.set_item_metadata(index,str(entry.get("id","")))
		if str(entry.get("id",""))==value:selected_index=index
	if selected_index>=0:option.select(selected_index)
	elif not options.is_empty():option.select(0)
	option.item_selected.connect(func(index):changed.call(str(option.get_item_metadata(index))))
	if not _details(definition).is_empty():host._wrapped(box,_details(definition),20,host.MUTED)


func _build_appearance(parent: Node) -> void:
	_ensure_draft()
	var row: HBoxContainer=host._hbox(parent,14)
	host._icon(row,"appearance",64)
	var intro: Label=host._wrapped(row,"Выберите доступный облик. Изменения применятся к персонажу в игровом мире.",22)
	intro.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var fields: Array=model.get("catalog",{}).get("appearance",[])
	for field in fields:
		var id := str(field.get("id",""))
		_choice(parent,field,str(_draft.appearance.get(id,"")),func(value):_draft.appearance[id]=value)
	_form_footer(parent,true)


func _form_footer(parent: Node,appearance_only: bool) -> void:
	var row: HBoxContainer=host._hbox(parent,10)
	host._button(row,"Применить облик" if appearance_only else "Сохранить характер",func():
		var payload: Dictionary={"actor_id":str(_selected().get("id",""))}
		if appearance_only:payload.appearance=_draft.appearance.duplicate(true)
		else:
			for key in ["name","traits","preferences","aspiration"]:payload[key]=_draft[key]
		host.life_requested.emit("edit_profile",payload),Vector2(230,49),"appearance" if appearance_only else "mood")
	host._button(row,"Сбросить правки",func():
		_draft_owner=""
		_build_page()
		_refresh(),Vector2(205,49))
