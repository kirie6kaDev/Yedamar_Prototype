extends CanvasLayer
## Presentation only. All inventory, travel and gameplay changes are signal requests.

signal action_requested(action: String, target_id: String)
signal character_requested(role: String)
signal craft_requested(recipe: String)
signal item_requested(item: String)
signal save_requested
signal load_requested
signal map_requested
signal dialogue_next
signal pause_requested
signal resume_requested
signal quit_requested
signal queue_cancel_requested(index: int)
signal queue_clear_requested
signal hotbar_requested(slot: int)
signal hotbar_assign_requested(slot: int, item: String)
signal transfer_requested(item: String, destination: String, count: int)
signal slot_save_requested(slot: String)
signal slot_load_requested(slot: String)
signal travel_requested(site_id: String)
signal map_visibility_changed(visible: bool)
signal work_requested(mode: String)
signal new_plots_toggled(enabled: bool)
signal follow_toggled(enabled: bool)
signal build_requested(kind: String)
signal life_requested(action: String, payload: Dictionary)

const PAPER := Color("#f5f1e1")
const MUTED := Color("#c1cfc1")
const GOLD := Color("#e2c287")
const GREEN := Color("#a7cb91")
const RED := Color("#edaa99")
const PANEL := Color("#142725fc")
const BORDER := Color("#657b6c")
const Campaign = preload("res://scripts/campaign.gd")
const LifeUI = preload("res://scripts/life_ui.gd")
const ITEM_NAMES = Campaign.ITEMS
const USABLE = Campaign.CONSUMABLES
const TOOLS = Campaign.EQUIPMENT
const STATIONS := {"campfire":"Костёр", "workbench":"Верстак", "sawmill":"Пилорама", "smelter":"Плавильная печь", "anvil":"Наковальня", "cauldron":"Алхимический котёл"}
const STAT_ICONS := ["health", "stamina", "ration", "thirst", "sleep"]
const STAT_COLORS := [Color("#d99080"), Color("#dfc27d"), Color("#b0c68b"), Color("#83beca"), Color("#b3a6d5")]
const STAT_NAMES := ["Здоровье", "Выносливость", "Сытость", "Запас воды", "Выспался"]

var _root: Control
var _font: Font
var _icons: Dictionary = {}
var _state: Dictionary = {}
var _inventory: Dictionary = {}
var _selected_role := "brother"
var _inspected_item := ""
var _inventory_tab := "person"
var _active_window := ""
var _pause_visible := false
var _text_scale := 1.0
var _ui_scale := 1.0
var _screen := Vector2(1280, 800)
var _last_inventory_hash := -1
var _last_craft_hash := -1
## Contextual crafting: hand recipes are always listed; station recipes only for
## the station the hero stands at ({"kind","id"} from main.gd, or an override set
## when the window is opened from a station's context menu).
var _craft_override: Dictionary = {}
var _craft_hint: Label
var _last_queue_key := ""
var _last_slots_hash := -1
var _journal_text := ""
var _hotbar_items: Array = []
var _header: PanelContainer
var _region_label: Label
var _clock_label: Label
var _combat_label: Label
var _quest_panel: PanelContainer
var _quest_objective: Label
var _family: HBoxContainer
var _family_buttons: Dictionary = {}
var _family_names: Dictionary = {}
var _family_stats: Dictionary = {}
var _animal_panel: PanelContainer
var _animal_name: Label
var _animal_status: Label
var _animal_stats: Array = []
var _hotbar: HBoxContainer
var _hotbar_cells: Array = []
var _quick_actions: HBoxContainer
var _queue_panel: PanelContainer
var _queue_title: Label
var _queue_empty: Label
var _queue_list: VBoxContainer
var _queue_rows: Array = []
var _queue_clear: Button
var _context: PanelContainer
var _context_body: VBoxContainer
var _context_scroll: ScrollContainer
var _context_target := ""
var _context_screen := Vector2.ZERO
var _inventory_window: PanelContainer
var _inventory_title: Label
var _inventory_list: VBoxContainer
var _inventory_detail: VBoxContainer
var _inventory_summary: Label
var _inventory_tabs: Dictionary = {}
var _craft_window: PanelContainer
var _craft_list: VBoxContainer
var _craft_detail: VBoxContainer
var _recipe_buttons: Dictionary = {}
var _selected_recipe := "stone_pickaxe"
var _recipe_rows: Dictionary = {}
var _journal_window: PanelContainer
var _journal_body: RichTextLabel
var _map_window: PanelContainer
var _map_points_box: VBoxContainer
var _map_texture: TextureRect
var _map_surface: Control
var _map_overlay: Control
var _map_viewport: SubViewport
var _map_camera: Camera3D
var _map_world: World3D
var _map_bounds := Rect2(2000,3166.666667,3166.666667,2000)
var _map_center := Vector2(3583.333333,4166.666667)
var _map_span := 2200.0
var _map_fit_span := 2200.0
var _map_refresh := 0.0
var _map_dragging := false
var _map_fit_pending := true
var _map_live_markers: Dictionary = {}
var _map_zoom_label: Label
var _work_window: PanelContainer
var _work_title: Label
var _work_garden: VBoxContainer
var _work_companions: VBoxContainer
var _work_status: Label
var _work_hint: Label
var _work_stop: Button
var _new_plots_check: CheckBox
var _follow_check: CheckBox
var _work_tab := "garden"
var _companion_hash := -1
var _companion_rows: Dictionary = {}
var _skills_window: PanelContainer
var _skills_title: Label
var _skill_rows: Dictionary = {}
var _build_window: PanelContainer
var _build_list: VBoxContainer
var _build_hash := -1
var _work_actions: HBoxContainer
var _map_markers: Array[Dictionary] = []
var _dialogue: PanelContainer
var _dialogue_name: Label
var _dialogue_text: Label
var _dialogue_next_button: Button
var _dialogue_open := false
var _toast_box: VBoxContainer
var _toast_order: Array[Control] = []
var _pause_shade: ColorRect
var _pause_panel: PanelContainer
var _slots_list: VBoxContainer
var _pause_font_label: Label
var _slot_rows: Dictionary = {}
var _life_ui
var _life_data: Dictionary = {}
var _life_strip: PanelContainer
var _life_funds: Label
var _life_speeds: HBoxContainer
var _life_speed_buttons: Dictionary = {}
var _life_speed_key := -1
var _weather_label: Label
var _character_names: Dictionary = {}
var _household_roles: Array = ["brother","sister"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_font = load("res://assets/ui/Lato-Regular.ttf")
	_root = Control.new()
	_root.name = "YedamarHUD"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var skin := Theme.new()
	skin.default_font = _font
	skin.default_font_size = 20
	skin.set_color("font_color", "Label", PAPER)
	skin.set_color("font_color", "Button", PAPER)
	skin.set_color("font_hover_color", "Button", Color.WHITE)
	skin.set_color("font_pressed_color", "Button", PAPER)
	skin.set_color("font_disabled_color", "Button", Color("#9aaa9d"))
	skin.set_color("font_color", "TooltipLabel", PAPER)
	skin.set_font_size("font_size", "TooltipLabel", 20)
	skin.set_stylebox("panel", "TooltipPanel", _style(PANEL, GOLD, 6, 12))
	skin.set_stylebox("scroll", "VScrollBar", _style(Color("#203731"), Color("#203731"), 3, 3))
	skin.set_stylebox("grabber", "VScrollBar", _style(Color("#8aa18a"), Color("#8aa18a"), 3, 4))
	_root.theme = skin
	_build_header()
	_build_tracker()
	_build_family()
	_build_animal()
	_build_hotbar()
	_build_queue()
	_build_context()
	_build_inventory()
	_build_crafting()
	_build_journal()
	_build_map()
	_build_work()
	_build_skills()
	_build_construction()
	_build_life()
	_build_dialogue()
	_build_pause()
	_toast_box = _vbox(_root, 8)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.z_index = 20
	get_viewport().size_changed.connect(_layout)
	_layout()
	update_state({})


func _style(background: Color, border: Color = BORDER, radius: int = 8, padding: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func _panel(parent: Node, padding: int = 14, color: Color = PANEL) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _style(color, BORDER, 9, padding))
	parent.add_child(panel)
	return panel


func _label(parent: Node, text: String, size: int = 20, color: Color = PAPER) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta("base_font_size", size)
	label.add_theme_font_size_override("font_size", roundi(size * _text_scale))
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _wrapped(parent: Node, text: String, size: int = 20, color: Color = PAPER) -> Label:
	var label := _label(parent, text, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(parent: Node, text: String, callback: Callable, minimum: Vector2 = Vector2(0, 44), icon: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.set_meta("base_font_size", 20)
	button.add_theme_font_size_override("font_size", roundi(20 * _text_scale))
	button.add_theme_stylebox_override("normal", _style(Color("#29443a"), Color("#7b9678"), 6, 10))
	button.add_theme_stylebox_override("hover", _style(Color("#3a5644"), GOLD, 6, 10))
	button.add_theme_stylebox_override("pressed", _style(Color("#172f25"), GOLD, 6, 10))
	button.add_theme_stylebox_override("disabled", _style(Color("#20322d"), Color("#4b6053"), 6, 10))
	if not icon.is_empty():
		button.icon = _texture(icon)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 28)
		button.add_theme_constant_override("h_separation", 8)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _texture(name: String) -> Texture2D:
	if not _icons.has(name):
		var path := "res://assets/ui/icons/" + name + ".png"
		_icons[name] = load(path) if ResourceLoader.exists(path) else null
	return _icons[name]


func _icon(parent: Node, name: String, size: int = 34) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = _texture(name)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(size, size)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(picture)
	return picture


func _vbox(parent: Node, spacing: int = 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", spacing)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(box)
	return box


func _hbox(parent: Node, spacing: int = 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", spacing)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(box)
	return box


func _spacer(parent: Node) -> void:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(spacer)


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _scroll(parent: Node, minimum_width: float = 0) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.x = minimum_width
	parent.add_child(scroll)
	return scroll


func _progress(parent: Node, color: Color, height: int = 7) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, height)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _style(Color("#071612"), Color("#071612"), 2, 0))
	bar.add_theme_stylebox_override("fill", _style(color, color, 2, 0))
	parent.add_child(bar)
	return bar


func _stat_row(parent: Node, index: int) -> Dictionary:
	var row := _hbox(parent, 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.tooltip_text = STAT_NAMES[index]
	_icon(row, STAT_ICONS[index], 24)
	var bar := _progress(row, STAT_COLORS[index])
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var number := _label(row, "100", 20)
	number.custom_minimum_size.x = 38
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return {"bar":bar, "number":number, "row":row}


func _build_header() -> void:
	_header = _panel(_root, 12)
	var row := _hbox(_header, 14)
	var title := _vbox(row, 0)
	title.custom_minimum_size.x = 310
	_label(title, "Noctis Live", 26, GOLD)
	_region_label = _label(title, "Равнины Лиора", 20)
	_region_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_spacer(row)
	_combat_label = _label(row, "Бой", 20, RED)
	_combat_label.hide()
	var clock_box := _vbox(row,0)
	_clock_label = _label(clock_box, "День 1 · 08:00", 20, MUTED)
	_weather_label = _label(clock_box, "", 20, MUTED)
	_weather_label.hide()
	_button(row, "Карта", _request_map, Vector2(126, 47), "map").tooltip_text = "Карта · M"
	_button(row, "Журнал", _toggle_journal, Vector2(145, 47), "journal").tooltip_text = "Журнал · J"
	_button(row, "Меню", func(): pause_requested.emit(), Vector2(127, 47), "pause").tooltip_text = "Пауза · Esc"


func _build_tracker() -> void:
	_quest_panel = _panel(_root, 14)
	var box := _vbox(_quest_panel, 9)
	_label(box, "Текущая цель", 22, GOLD)
	_quest_objective = _wrapped(box, "", 20)


func _build_family() -> void:
	_family = _hbox(_root, 8)
	_family.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for role in ["brother", "sister"]:
		var card := _button(_family, "", func(): character_requested.emit(role), Vector2(196, 204))
		card.add_theme_stylebox_override("normal", _style(PANEL, BORDER, 8, 0))
		var content := VBoxContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 12
		content.offset_right = -12
		content.offset_top = 10
		content.offset_bottom = -10
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 5)
		card.add_child(content)
		_family_names[role] = _label(content, _role_name(role), 22)
		_family_names[role].text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		var rows: Array = []
		for index in range(5):
			rows.append(_stat_row(content, index))
		_family_buttons[role] = card
		_family_stats[role] = rows


func _build_animal() -> void:
	_animal_panel = _panel(_root, 12)
	var box := _vbox(_animal_panel, 5)
	var row := _hbox(box, 7)
	_icon(row, "animal", 31)
	_animal_name = _label(row, "Вьючное животное", 22)
	_animal_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_animal_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_animal_status = _label(box, "Отдыхает", 20, MUTED)
	_animal_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for index in range(4):
		_animal_stats.append(_stat_row(box, index))


func _build_hotbar() -> void:
	_hotbar = _hbox(_root, 6)
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for slot in range(6):
		var button := _button(_hotbar, "", func(): hotbar_requested.emit(slot), Vector2(70, 90))
		var picture := _icon(button, "", 34)
		picture.position = Vector2(18, 28)
		picture.size = Vector2(34, 34)
		var digit := _label(button, str(slot + 1), 20, MUTED)
		digit.position = Vector2(7, 3)
		var count := _label(button, "", 20, PAPER)
		count.position = Vector2(8, 64)
		count.size = Vector2(54, 24)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_hotbar_cells.append({"button":button, "picture":picture, "count":count})
	_quick_actions = _hbox(_root, 8)
	_quick_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button(_quick_actions, "Рюкзак", _toggle_inventory, Vector2(145, 55), "inventory").tooltip_text = "Рюкзак · I"
	_button(_quick_actions, "Ремесло", _toggle_crafting, Vector2(153, 55), "craft").tooltip_text = "Ремесло · C"
	_work_actions = _hbox(_root, 8)
	_work_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button(_work_actions, "Дела", func(): _toggle_work(), Vector2(145, 48), "garden").tooltip_text = "Работа и спутники · G"
	_button(_work_actions, "Навыки", func(): _toggle_skills(), Vector2(153, 48), "skills").tooltip_text = "Навыки · K"


func _build_queue() -> void:
	_queue_panel = _panel(_root, 13)
	var box := _vbox(_queue_panel, 8)
	var title := _hbox(box)
	_queue_title = _label(title, "Очередь · Брат", 22, GOLD)
	_queue_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_clear = _button(title, "Очистить", func(): queue_clear_requested.emit(), Vector2(0, 38))
	var scroll := _scroll(box)
	scroll.custom_minimum_size.y = 30
	_queue_list = _vbox(scroll, 9)
	_queue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_empty = _label(box, "Свободен", 20, MUTED)


func _build_context() -> void:
	_context = _panel(_root, 15)
	_context.z_index = 30
	_context_scroll = _scroll(_context)
	_context_body = _vbox(_context_scroll, 9)
	_context_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_context.hide()


func _window(title: String, close: Callable) -> Dictionary:
	var panel := _panel(_root, 20)
	panel.z_index = 10
	panel.hide()
	var box := _vbox(panel, 16)
	var header := _hbox(box, 10)
	var label := _label(header, title, 28, PAPER)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(header, "", close, Vector2(44,44), "close").tooltip_text = "Закрыть"
	return {"panel":panel, "body":box, "title":label}


func _build_inventory() -> void:
	var window := _window("Рюкзак · Брат", func(): set_inventory_visible(false))
	_inventory_window = window.panel
	_inventory_title = window.title
	var tabs := _hbox(window.body)
	for role in ["brother", "sister"]:
		_inventory_tabs[role] = _button(tabs, _role_name(role),
			func():
				_inventory_tab = "person"
				character_requested.emit(role)
				_refresh_inventory(), Vector2(165,44), "inventory")
	_inventory_tabs.cart = _button(tabs, "Повозка",
		func():
			_inventory_tab = "cart"
			_refresh_inventory(), Vector2(190,44), "cart")
	_inventory_summary = _label(window.body, "", 20, MUTED)
	var content := _hbox(window.body, 20)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list_scroll := _scroll(content, 370)
	_inventory_list = _vbox(list_scroll, 8)
	_inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var detail_scroll := _scroll(content)
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_detail = _vbox(detail_scroll, 13)
	_inventory_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _build_crafting() -> void:
	var window := _window("Ремесло и алхимия", func(): set_crafting_visible(false))
	_craft_window = window.panel
	var content := _hbox(window.body, 22)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list_scroll := _scroll(content, 350)
	_craft_list = _vbox(list_scroll, 8)
	_craft_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_craft_hint = _label(_craft_list, "", 18, MUTED)
	_craft_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_craft_hint.custom_minimum_size = Vector2(340, 0)
	var detail_scroll := _scroll(content)
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_craft_detail = _vbox(detail_scroll, 13)
	_craft_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for recipe_id in Campaign.RECIPES:
		var recipe: Dictionary = Campaign.RECIPES[recipe_id]
		var button := _button(_craft_list, recipe.name,
			func():
				_selected_recipe = recipe_id
				_refresh_recipes(), Vector2(350,65), recipe.item)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_recipe_buttons[recipe_id] = button


func _build_journal() -> void:
	var window := _window("Журнал путешествия", _close_windows)
	_journal_window = window.panel
	_journal_body = RichTextLabel.new()
	_journal_body.bbcode_enabled = false
	_journal_body.selection_enabled = true
	_journal_body.scroll_active = true
	_journal_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal_body.add_theme_color_override("default_color", PAPER)
	_journal_body.add_theme_font_size_override("normal_font_size", 22)
	_journal_body.set_meta("base_rich_size", 22)
	_journal_body.add_theme_constant_override("line_separation", 10)
	window.body.add_child(_journal_body)




func _build_dialogue() -> void:
	_dialogue = _panel(_root, 17)
	_dialogue.z_index = 25
	_dialogue.hide()
	var box := _vbox(_dialogue, 12)
	_dialogue_name = _label(box, "", 24, GOLD)
	_dialogue_text = _wrapped(box, "", 22)
	_dialogue_text.custom_minimum_size.x = 606
	_dialogue_next_button = _button(box, "Далее  ↵", func(): dialogue_next.emit(), Vector2(0,46))


func _build_pause() -> void:
	_pause_shade = ColorRect.new()
	_pause_shade.color = Color("#07130fe8")
	_pause_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_shade.z_index = 100
	_root.add_child(_pause_shade)
	_pause_shade.hide()
	_pause_panel = _panel(_pause_shade, 23)
	var body := _vbox(_pause_panel, 14)
	var header := _hbox(body, 12)
	_label(header, "Пауза", 32, GOLD)
	_spacer(header)
	_button(header, "Продолжить", func(): resume_requested.emit(), Vector2(190,48))
	_button(header, "Выйти", func(): quit_requested.emit(), Vector2(125,48))
	var options := _hbox(body, 12)
	_label(options, "Размер текста", 20)
	_button(options, "−", func(): _set_text_scale(-0.1), Vector2(44,42))
	_pause_font_label = _label(options, "20 px", 20, GOLD)
	_button(options, "+", func(): _set_text_scale(0.1), Vector2(44,42))
	_spacer(options)
	_label(options, "Сохранения", 24)
	var scroll := _scroll(body)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_list = _vbox(scroll, 10)
	_slots_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_ui_scale = clampf(minf(viewport_size.x/1280.0, viewport_size.y/800.0), 0.75, 1.30)
	_root.scale = Vector2.ONE * _ui_scale
	_screen = viewport_size / _ui_scale
	_root.size = _screen
	_header.position = Vector2(18,16)
	_header.size = Vector2(_screen.x-36,76)
	_quest_panel.position = Vector2(_screen.x-352,108)
	_quest_panel.size = Vector2(334,0)
	_queue_panel.position = Vector2(18,108)
	_queue_panel.size = Vector2(416,238 if not _queue_rows.is_empty() else 104)
	var family_height := 204 + 130 * (_text_scale-1.0)
	_family.position = Vector2(18,_screen.y-family_height-18)
	_family.size = Vector2(400,family_height)
	for card in _family_buttons.values():
		card.custom_minimum_size.y = family_height
	_animal_panel.position = Vector2(_screen.x-252,_screen.y-402)
	_animal_panel.size = Vector2(234,0)
	_hotbar.position = Vector2(448,_screen.y-108)
	_hotbar.size = Vector2(450,90)
	_quick_actions.position = Vector2(_screen.x-324,_screen.y-73)
	_quick_actions.size = Vector2(306,55)
	_work_actions.position = Vector2(_screen.x-324,_screen.y-132)
	_work_actions.size = Vector2(306,48)
	for window in [_inventory_window,_craft_window,_journal_window,_work_window,_skills_window,_build_window]:
		window.position = Vector2((_screen.x-1070)/2,107)
		window.size = Vector2(1070,_screen.y-215)
	_map_window.position = Vector2(46,107)
	_map_window.size = Vector2(_screen.x-92,_screen.y-215)
	if _life_ui!=null:
		_life_ui.panel.position=Vector2(46,107)
		_life_ui.panel.size=Vector2(_screen.x-92,_screen.y-215)
		_life_strip.position=Vector2(448,_screen.y-166)
		_life_strip.size=Vector2(488,50)
	_dialogue.size = Vector2(640,0)
	if _dialogue.visible:
		_place_dialogue.call_deferred()
	var toast_left := 450.0
	var toast_right := _screen.x-368.0
	var toast_width := minf(470.0,toast_right-toast_left)
	_toast_box.position = Vector2(toast_left+(toast_right-toast_left-toast_width)*0.5,108)
	_toast_box.size = Vector2(toast_width,0)
	_pause_shade.position = Vector2.ZERO
	_pause_shade.size = _screen
	_pause_panel.position = Vector2((_screen.x-1040)/2,40)
	_pause_panel.size = Vector2(1040,_screen.y-80)
	if _context.visible:
		_position_context.call_deferred()


func _role_name(role: String) -> String:
	return str(_character_names.get(role,"Сестра" if role=="sister" else ("Брат" if role=="brother" else "Житель")))


func update_state(state: Dictionary) -> void:
	var previous_role := _selected_role
	_state = state.duplicate()
	_selected_role = str(state.get("selected","brother"))
	_inventory = state.get("selected_inventory",state.get("inventory",{}))
	_hotbar_items = state.get("hotbar",[])
	if previous_role != _selected_role:
		_inventory_tab = "person"
		_inspected_item = ""
	_region_label.text = str(state.get("region","Равнины Лиора"))
	_clock_label.text = str(state.get("game_time","День 1 · 08:00"))
	_combat_label.visible = bool(state.get("in_combat",false))
	for role in ["brother","sister"]:
		var maximum := float(state.get(role+"_max_health",80 if role=="sister" else 100))
		var health := clampf(float(state.get(role+"_health",maximum)),0,maximum)
		var values := [health, float(state.get(role+"_stamina",100)),
			float(state.get(role+"_hunger",state.get("hunger",100))),
			float(state.get(role+"_thirst",state.get("thirst",100))),
			float(state.get(role+"_sleep",state.get("sleep",100) if role==_selected_role else 100))]
		var card: Button = _family_buttons[role]
		card.add_theme_stylebox_override("normal",_style(PANEL,GOLD if role==_selected_role else BORDER,8,0))
		_family_names[role].text = str(state.get(role+"_name",_role_name(role)))
		card.tooltip_text = "%s · Tab\nЗдоровье %d/%d\nВыносливость %d\nСытость %d\nЗапас воды %d\nВыспался %d" % [
			_role_name(role),roundi(health),roundi(maximum),roundi(values[1]),roundi(values[2]),roundi(values[3]),roundi(values[4])]
		if role in state.get("cart",{}).get("passengers",[]):
			card.tooltip_text += "\nОтдыхает в повозке"
		for i in range(5):
			var row: Dictionary = _family_stats[role][i]
			row.bar.max_value = maximum if i==0 else 100
			row.bar.value = values[i]
			row.number.text = str(roundi(values[i]))
	_update_animal()
	_update_hotbar()
	_update_queue()
	_update_work()
	_update_skills()
	_update_build_options()
	_update_map_live_markers()
	_quest_objective.text = str(state.get("objective","Осмотритесь и найдите фермера."))
	_quest_panel.visible = _active_window.is_empty()
	if state.has("journal_text"):
		_journal_text = str(state.journal_text)
	if _journal_window.visible:
		_journal_body.text = _journal_text if not _journal_text.is_empty() else _default_journal()
	_dialogue_next_button.text = "Далее  ↵" if bool(state.get("dialogue_more",false)) else "Закрыть  ↵"
	var cart: Dictionary = state.get("cart",{})
	var inventory_key := hash([_inventory,_selected_role,_hotbar_items,cart.get("storage",{}),cart.get("available",false)])
	if inventory_key != _last_inventory_hash:
		_last_inventory_hash = inventory_key
		_refresh_inventory()
	var craft_key := hash([_inventory,state.get("alchemy_learned",false),state.get("near_cauldron",false),state.get("near_stations",[]),_selected_role,craft_context(),_active_window=="craft"])
	if craft_key != _last_craft_hash:
		_last_craft_hash = craft_key
		_refresh_recipes()
	if _pause_visible:
		var slots: Array = state.get("save_slots",[])
		if hash(slots) != _last_slots_hash:
			_refresh_slots(slots)


func _update_animal() -> void:
	var animal: Dictionary = _state.get("animal",{})
	_animal_panel.visible = not animal.is_empty()
	if animal.is_empty():
		return
	_animal_name.text = str(animal.get("name","Животное"))
	_animal_status.text = str(animal.get("status","Отдыхает"))
	_animal_panel.tooltip_text = str(animal.get("food_description","Сено, морковь и ягоды."))
	_animal_status.tooltip_text = _animal_status.text
	var keys := ["health","stamina","hunger","thirst"]
	for i in range(4):
		var value := clampf(float(animal.get(keys[i],100)),0,100)
		_animal_stats[i].bar.value = value
		_animal_stats[i].number.text = str(roundi(value))


func _update_hotbar() -> void:
	for i in range(6):
		var item := str(_hotbar_items[i]) if i < _hotbar_items.size() else ""
		var cell: Dictionary = _hotbar_cells[i]
		var count := int(_inventory.get(item,0))
		cell.picture.texture = _texture(item) if not item.is_empty() else null
		cell.picture.modulate.a = 1.0 if count>0 else 0.35
		cell.count.text = str(count) if not item.is_empty() else ""
		var selected := not item.is_empty() and item==str(_state.get("selected_item",""))
		cell.button.add_theme_stylebox_override("normal",_style(PANEL,GOLD if selected else BORDER,7,4))
		cell.button.tooltip_text = "%d · %s" % [i+1,ITEM_NAMES.get(item,"Пустой слот — назначьте предмет в рюкзаке")]


func _update_queue() -> void:
	_queue_title.text = "Очередь · " + _role_name(_selected_role)
	var orders: Array = _state.get("queue",[])
	var keys := PackedStringArray([_selected_role])
	for order in orders:
		keys.append(str(order.get("id",""))+str(order.get("label","")))
	var key := "|".join(keys)
	if key != _last_queue_key:
		_last_queue_key = key
		_clear(_queue_list)
		_queue_rows.clear()
		for index in range(orders.size()):
			var row := _hbox(_queue_list,8)
			var body := _vbox(row,4)
			body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var label := _wrapped(body,"",20)
			var bar := _progress(body,GOLD,5)
			var cancel := _button(row,"",func():queue_cancel_requested.emit(index),Vector2(40,42),"close")
			cancel.tooltip_text = "Отменить это действие"
			cancel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			_queue_rows.append({"label":label,"bar":bar})
		_queue_panel.size.y = 238 if not orders.is_empty() else 104
	for i in range(orders.size()):
		var order: Dictionary = orders[i]
		var status := _queue_status_text(str(order.get("status","")))
		_queue_rows[i].label.text = str(order.get("label","Действие")) + (" · "+status if not status.is_empty() else "")
		_queue_rows[i].bar.value = clampf(float(order.get("progress",0)),0,1)*100
		_queue_rows[i].bar.visible = i==0
	_queue_clear.disabled = orders.is_empty()
	_queue_empty.visible = orders.is_empty()
	_queue_empty.text = str(_state.get("action_text","Свободен"))
	if _queue_empty.text.is_empty():
		_queue_empty.text = "Свободен"


func _queue_status_text(status: String) -> String:
	match status:
		"waiting": return "Ожидает"
		"walking": return "В пути"
		"working": return "Выполняется"
		_: return status


func _inventory_source() -> Dictionary:
	if _inventory_tab == "cart":
		return _state.get("cart",{}).get("storage",{})
	return _inventory


func _refresh_inventory() -> void:
	if not is_instance_valid(_inventory_list):
		return
	_clear(_inventory_list)
	var source := _inventory_source()
	if int(source.get(_inspected_item,0))<=0:
		_inspected_item = ""
		for key in source:
			if int(source[key])>0:
				_inspected_item = str(key)
				break
	_inventory_title.text = "Припасы в повозке" if _inventory_tab=="cart" else "Рюкзак · "+_role_name(_selected_role)
	for key in _inventory_tabs:
		var active: bool = key=="cart" if _inventory_tab=="cart" else key==_selected_role
		_inventory_tabs[key].add_theme_stylebox_override("normal",_style(Color("#29443a"),GOLD if active else BORDER,6,10))
	var total := 0
	var kinds := 0
	for key in ITEM_NAMES:
		var count := int(source.get(key,0))
		if count<=0:
			continue
		kinds += 1
		total += count
		var button := _button(_inventory_list,"",
			func():
				_inspected_item = key
				_refresh_inventory(),Vector2(360,69))
		button.add_theme_stylebox_override("normal",_style(Color("#20392f"),GOLD if key==_inspected_item else BORDER,6,8))
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left=10; row.offset_right=-10; row.offset_top=8; row.offset_bottom=-8
		row.add_theme_constant_override("separation",10)
		row.mouse_filter=Control.MOUSE_FILTER_IGNORE
		button.add_child(row)
		_icon(row,key,44)
		var name_label := _wrapped(row,ITEM_NAMES[key],20)
		name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_label(row,"×"+str(count),20,GOLD)
	_inventory_summary.text = "%d видов · %d предметов" % [kinds,total]
	if kinds==0:
		_wrapped(_inventory_list,"Здесь пока пусто.",22,MUTED)
	_render_item_detail()


func _render_item_detail() -> void:
	_clear(_inventory_detail)
	if _inspected_item.is_empty():
		_wrapped(_inventory_detail,"Выберите предмет, чтобы использовать, передать или назначить его на панель.",22,MUTED)
		return
	var item := _inspected_item
	var count := int(_inventory_source().get(item,0))
	var head := _hbox(_inventory_detail,15)
	_icon(head,item,72)
	var labels := _vbox(head,5)
	labels.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_wrapped(labels,str(ITEM_NAMES.get(item,item)),26,GOLD)
	_label(labels,"В наличии · "+str(count),20)
	if _inventory_tab=="cart":
		_wrapped(_inventory_detail,"Получатель · "+_role_name(_selected_role),20,MUTED)
		_button(_inventory_detail,"Забрать 1",func():action_requested.emit("cart_take",item),Vector2(0,48),"inventory")
		return
	if item in USABLE or item in TOOLS or item=="hay":
		var verb := "Взять в руки" if item in TOOLS else "Использовать"
		if item in ["hay","carrot"]:
			verb="Покормить животное"
		_button(_inventory_detail,verb,func():item_requested.emit(item),Vector2(0,48),item)
	else:
		_wrapped(_inventory_detail,"Посылка для поручения." if item=="parcel" else "Материал для ремесла.",20,MUTED)
	_label(_inventory_detail,"Назначить на быстрый слот",20)
	var slots := _hbox(_inventory_detail,7)
	for slot in range(6):
		var assign := _button(slots,str(slot+1),func():hotbar_assign_requested.emit(slot,item),Vector2(49,46))
		assign.tooltip_text="Назначить "+str(ITEM_NAMES.get(item,item))+" · "+str(slot+1)
	_label(_inventory_detail,"Передать предметы",22,GOLD)
	var destinations: Array=_household_roles.filter(func(role):return role!=_selected_role)
	destinations.append("cart")
	for destination in destinations:
		var row := _hbox(_inventory_detail,8)
		var title := "В повозку" if destination=="cart" else _role_name(destination)
		var one := _button(row,title+" · 1",func():transfer_requested.emit(item,destination,1),Vector2(0,46))
		one.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var all_items := _button(row,"Всё · "+str(count),func():transfer_requested.emit(item,destination,count),Vector2(135,46))
		var cart_missing: bool = destination=="cart" and not bool(_state.get("cart",{}).get("available",false))
		one.disabled=cart_missing
		all_items.disabled=cart_missing


## Station the crafting window is bound to: {"kind": station type or "", "id": object id}.
func craft_context() -> Dictionary:
	if not _craft_override.is_empty():
		return _craft_override
	return _state.get("craft_context", {"kind":"", "id":""})


func _recipe_available_here(recipe: Dictionary) -> bool:
	var station := str(recipe.get("station",""))
	return station.is_empty() or station==str(craft_context().get("kind",""))


func _refresh_recipes() -> void:
	_clear(_craft_detail)
	_recipe_rows.clear()
	var context_kind := str(craft_context().get("kind",""))
	if is_instance_valid(_craft_hint):
		_craft_hint.text = "Здесь: в руках" + (" + " + str(STATIONS.get(context_kind, context_kind)) if not context_kind.is_empty() else "") + ".\nРецепты станков появляются, когда герой стоит у станка."
	if not _selected_recipe.is_empty() and Campaign.RECIPES.has(_selected_recipe) and not _recipe_available_here(Campaign.RECIPES[_selected_recipe]):
		_selected_recipe = ""
	for recipe_id in Campaign.RECIPES:
		_recipe_buttons[recipe_id].visible = _recipe_available_here(Campaign.RECIPES[recipe_id])
	for recipe_id in Campaign.RECIPES:
		var recipe: Dictionary = Campaign.RECIPES[recipe_id]
		if not _recipe_available_here(recipe):
			continue
		var selected: bool = recipe_id==_selected_recipe
		_recipe_buttons[recipe_id].add_theme_stylebox_override("normal",_style(Color("#243b31"),GOLD if selected else BORDER,6,10))
		if not selected:
			continue
		var row := _hbox(_craft_detail,14)
		_icon(row,recipe.item,72)
		var title := _wrapped(row,recipe.name,28,GOLD)
		var title_count := int(recipe.get("count",1))
		if title_count>1:
			title.text += " × "+str(title_count)
		title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_wrapped(_craft_detail,recipe.get("description",""),21)
		var station := str(recipe.get("station",""))
		var location := str(STATIONS.get(station,"Вручную"))
		_wrapped(_craft_detail,"%s · %d сек. · %s +%d опыта" % [location,roundi(float(recipe.get("duration",0))),Campaign.SKILLS.get(recipe.get("skill","crafting"),"Ремесло"),int(recipe.get("xp",0))],20,MUTED)
		_label(_craft_detail,"Материалы",22,GOLD)
		var enough := true
		for ingredient in recipe.cost:
			var have := int(_inventory.get(ingredient,0))
			var need := int(recipe.cost[ingredient])
			enough = enough and have>=need
			var cost_row := _hbox(_craft_detail,10)
			_icon(cost_row,ingredient,31)
			var name_label := _label(cost_row,ITEM_NAMES.get(ingredient,ingredient),20)
			name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			_label(cost_row,"%d / %d" % [have,need],22,GREEN if have>=need else RED)
		var allowed := enough
		var reason := "" if enough else "Нужно больше материалов в рюкзаке выбранного героя."
		var needed_tool := str(recipe.get("needs_tool",""))
		if not needed_tool.is_empty():
			var has_tool := int(_inventory.get(needed_tool,0))>0
			_wrapped(_craft_detail,"Инструмент: "+str(ITEM_NAMES.get(needed_tool,needed_tool))+" · сохраняется",20,GREEN if has_tool else RED)
			if not has_tool:
				allowed=false
				reason="Нужный инструмент должен быть в личном рюкзаке."
		if recipe.get("skill","")=="alchemy" and not bool(_state.get("alchemy_learned",false)):
			allowed=false
			reason="Сначала изучите алхимию у травницы."
		if not station.is_empty():
			_wrapped(_craft_detail,"Станок рядом: "+str(STATIONS.get(station,station))+".",20,GREEN)
		var button := _button(_craft_detail,"В очередь",func():craft_requested.emit(recipe_id),Vector2(0,50),"craft")
		button.disabled=not allowed
		button.tooltip_text=reason
		_recipe_rows[recipe_id]={"button":button}
		if not reason.is_empty():
			_wrapped(_craft_detail,reason,20,RED)


func show_context(screen_position: Vector2,target_id: String,title: String,actions: Array) -> void:
	_clear(_context_body)
	_context_target=target_id
	_context_screen=screen_position
	var head := _hbox(_context_body)
	var name_label := _wrapped(head,title,24,GOLD)
	name_label.custom_minimum_size.x=282
	name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_button(head,"",hide_context,Vector2(42,42),"close")
	for action in actions:
		var id := str(action.get("id","inspect"))
		var button := _button(_context_body,str(action.get("label",id)),
			func():
				var target := _context_target
				hide_context()
				action_requested.emit(id,target),Vector2(0,46),_action_icon(id))
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		button.disabled=not bool(action.get("enabled",true))
		button.tooltip_text=str(action.get("reason",""))
		if button.disabled and not button.tooltip_text.is_empty():
			var reason := _wrapped(_context_body,button.tooltip_text,20,MUTED)
			reason.custom_minimum_size.x=320
	_context.custom_minimum_size.x=380
	_context.size=Vector2(380,0)
	_context.show()
	_sync_dialogue_visibility()
	_position_context.call_deferred()


func _action_icon(action: String) -> String:
	match action:
		"inspect","talk","search": return "view"
		"mine": return "pickaxe"
		"attack": return "sword"
		"drink","fill","water","water_animal": return "water"
		"rest","hide": return "stamina"
		"sleep": return "sleep"
		"chop": return "axe"
		"garden","till","plant","harvest": return "hoe"
		"build": return "build"
		"cook": return "ration"
		"brew": return "healing_potion"
		"feed": return "hay"
		"cart_storage","pull_cart","disembark": return "cart"
		"travel","ride","board","ride_cart": return "travel"
		_: return "inventory"


func _position_context() -> void:
	if not _context.visible:
		return
	await get_tree().process_frame
	_context.size=Vector2(maxf(380,_context.get_combined_minimum_size().x),minf(_screen.y-136,_context_body.get_combined_minimum_size().y+30))
	var where := _context_screen/_ui_scale+Vector2(12,10)
	where.x=clampf(where.x,12,maxf(12,_screen.x-_context.size.x-12))
	where.y=clampf(where.y,12,maxf(12,_screen.y-_context.size.y-124))
	_context.position=where


func hide_context() -> void:
	if is_instance_valid(_context):
		_context.hide()
	_sync_dialogue_visibility()


func _open_window(which: String) -> void:
	var map_was_open := _active_window=="map"
	if which!="craft":
		_craft_override = {}
	_active_window=which
	hide_context()
	_inventory_window.visible=which=="inventory"
	_craft_window.visible=which=="craft"
	_journal_window.visible=which=="journal"
	_map_window.visible=which=="map"
	_work_window.visible=which=="work"
	_skills_window.visible=which=="skills"
	_build_window.visible=which=="build"
	if _life_ui!=null:_life_ui.panel.visible=which=="life"
	_quest_panel.visible=which.is_empty()
	if map_was_open != (which=="map"):
		map_visibility_changed.emit(which=="map")
		_map_dragging=false
		if which=="map":
			_map_refresh=0.0
			_sync_map_view.call_deferred()
		else:
			_map_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	_sync_dialogue_visibility()
	_settle_window_layout.call_deferred()


func _settle_window_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_layout()


func _close_windows() -> void:
	_open_window("")


func _toggle_inventory() -> void:
	set_inventory_visible(_active_window!="inventory")


func show_inventory() -> void:
	set_inventory_visible(true)


func show_cart_storage() -> void:
	_inventory_tab = "cart"
	_refresh_inventory()
	set_inventory_visible(true)


func set_inventory_visible(value: bool) -> void:
	_open_window("inventory" if value else "")


func _toggle_crafting() -> void:
	set_crafting_visible(_active_window!="craft")


func show_crafting() -> void:
	set_crafting_visible(true)


## Open the crafting window bound to a specific station (campfire, cauldron...).
func show_crafting_at(kind: String, target_id: String) -> void:
	_craft_override = {"kind": kind, "id": target_id}
	_open_window("craft")
	_refresh_recipes()


func set_crafting_visible(value: bool) -> void:
	_open_window("craft" if value else "")


func _default_journal() -> String:
	return "%s\n\n%s\n\nУправление\nЛКМ — добавить действие или идти\nTab — переключить героя\n1–6 — использовать быстрый предмет\nI — рюкзак · C — ремесло · M — карта\nG — дела · K — навыки · B — строительство\nWASD — камера · колесо — масштаб\nСредняя кнопка — вращение\nПравая кнопка — сдвиг камеры\nПробел — камера к герою\nEnter — следующая реплика\nEsc — меню паузы" % [
		str(_state.get("quest","Дорога через Лиору")),str(_state.get("objective","Осмотритесь."))]


func _toggle_journal() -> void:
	if _active_window=="journal":
		_close_windows()
	else:
		show_journal(_journal_text)


func show_journal(content: String) -> void:
	_journal_text=content
	_journal_body.text=content if not content.is_empty() else _default_journal()
	_open_window("journal")


func _request_map() -> void:
	if _active_window=="map":
		_close_windows()
	else:
		map_requested.emit()






func show_dialogue(speaker: String,text: String) -> void:
	_dialogue_name.text=speaker
	_dialogue_text.text=text
	_dialogue_open=true
	_dialogue.size=Vector2(640,0)
	_sync_dialogue_visibility()


func hide_dialogue() -> void:
	_dialogue_open=false
	_dialogue.hide()


func _dismiss_dialogue() -> void:
	hide_dialogue()


func is_dialogue_suspended() -> bool:
	return _pause_visible or not _active_window.is_empty() or (is_instance_valid(_context) and _context.visible)


func _sync_dialogue_visibility() -> void:
	if not is_instance_valid(_dialogue):
		return
	_dialogue.visible=_dialogue_open and not is_dialogue_suspended()
	if _dialogue.visible:
		_place_dialogue.call_deferred()


func _place_dialogue() -> void:
	await get_tree().process_frame
	_dialogue.size=Vector2(640,0)
	await get_tree().process_frame
	_dialogue.position=Vector2((_screen.x-640)/2,maxf(110,_family.position.y-14-_dialogue.size.y))


func show_pause(slots: Array = []) -> void:
	_pause_visible=true
	hide_context()
	_refresh_slots(slots)
	_pause_shade.show()
	_sync_dialogue_visibility()


func hide_pause() -> void:
	_pause_visible=false
	_pause_shade.hide()
	_sync_dialogue_visibility()


func _refresh_slots(slots: Array) -> void:
	_last_slots_hash=hash(slots)
	_clear(_slots_list)
	_slot_rows.clear()
	var indexed: Dictionary={}
	for slot in slots:
		indexed[str(slot.get("id",""))]=slot
	var ids: Array[String]=["manual_1","manual_2","manual_3","realtime","auto_0","auto_1","auto_2","auto_3","auto_4","auto_5"]
	for id in ids:
		var slot: Dictionary=indexed.get(id,{})
		var exists := bool(slot.get("exists",false))
		var manual := id.begins_with("manual_")
		var label := str(slot.get("label",_slot_name(id)))
		var panel := _panel(_slots_list,12,Color("#20392f"))
		var row := _hbox(panel,12)
		var texts := _vbox(row,5)
		texts.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_wrapped(texts,label,22,GOLD)
		_wrapped(texts,str(slot.get("date","Дата неизвестна")) if exists else "Пустой слот",20,MUTED)
		if manual:
			_button(row,"Сохранить",func():slot_save_requested.emit(id),Vector2(155,47))
		var load_button := _button(row,"Загрузить",func():slot_load_requested.emit(id),Vector2(151,47))
		load_button.disabled=not exists
		_slot_rows[id]={"load":load_button,"panel":panel}


func _slot_name(id: String) -> String:
	if id.begins_with("manual_"):
		return "Ручное сохранение "+id.trim_prefix("manual_")
	if id=="realtime":
		return "Текущее состояние"
	return "Автосохранение "+str(int(id.trim_prefix("auto_"))+1)


func _set_text_scale(delta: float) -> void:
	_text_scale=clampf(snappedf(_text_scale+delta,0.1),1.0,1.2)
	_root.theme.default_font_size=roundi(20*_text_scale)
	_root.theme.set_font_size("font_size","TooltipLabel",roundi(20*_text_scale))
	for node in _root.find_children("*","Control",true,false):
		if node.has_meta("base_font_size"):
			node.add_theme_font_size_override("font_size",roundi(float(node.get_meta("base_font_size"))*_text_scale))
		if node.has_meta("base_rich_size"):
			node.add_theme_font_size_override("normal_font_size",roundi(float(node.get_meta("base_rich_size"))*_text_scale))
	_pause_font_label.text=str(roundi(20*_text_scale))+" px"
	_layout.call_deferred()


func toast(text: String) -> void:
	if text.is_empty():
		return
	var panel := _panel(_toast_box,12,Color("#233d30fa"))
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var label := _wrapped(panel,text,20)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_toast_order.append(panel)
	while _toast_order.size()>2:
		var oldest: Control=_toast_order.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var tween := create_tween().bind_node(panel)
	tween.tween_interval(4.5)
	tween.tween_property(panel,"modulate:a",0.0,0.4)
	tween.tween_callback(func():
		_toast_order.erase(panel)
		if is_instance_valid(panel):
			panel.queue_free())


func is_modal_open() -> bool:
	return _pause_visible or not _active_window.is_empty()


func dismiss_all() -> void:
	hide_dialogue()
	_close_windows()
	hide_context()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode==KEY_ESCAPE:
		if _pause_visible:
			resume_requested.emit()
		else:
			pause_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if _pause_visible:
		get_viewport().set_input_as_handled()
		return
	if event.physical_keycode>=KEY_1 and event.physical_keycode<=KEY_6:
		hotbar_requested.emit(event.physical_keycode-KEY_1)
		get_viewport().set_input_as_handled()
		return
	match event.physical_keycode:
		KEY_I: _toggle_inventory()
		KEY_C: _toggle_crafting()
		KEY_J: _toggle_journal()
		KEY_M: _request_map()
		KEY_G: _toggle_work()
		KEY_K: _toggle_skills()
		KEY_B: _toggle_construction()
		KEY_L: _toggle_life()
		KEY_ENTER,KEY_KP_ENTER:
			if not _dialogue.visible:
				return
			dialogue_next.emit()
		_: return
	get_viewport().set_input_as_handled()


func _build_map() -> void:
	var window := _window("Живая карта Лиоры", _close_windows)
	_map_window = window.panel
	var toolbar := _hbox(window.body,8)
	_button(toolbar,"−",func(): _zoom_map(1.35),Vector2(44,44)).tooltip_text="Отдалить · колесо вниз"
	_button(toolbar,"+",func(): _zoom_map(1.0/1.35),Vector2(44,44)).tooltip_text="Приблизить · колесо вверх"
	_button(toolbar,"К герою",_focus_map_character,Vector2(142,44),"view")
	_button(toolbar,"Весь участок",_fit_map,Vector2(172,44),"map")
	_map_zoom_label=_label(toolbar,"",20,MUTED)
	_spacer(toolbar)
	_label(toolbar,"↑ Север",20,GOLD)
	var row := _hbox(window.body,16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_surface = Control.new()
	_map_surface.clip_contents=true
	_map_surface.mouse_filter=Control.MOUSE_FILTER_STOP
	_map_surface.mouse_default_cursor_shape=Control.CURSOR_DRAG
	_map_surface.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_map_surface.size_flags_vertical=Control.SIZE_EXPAND_FILL
	row.add_child(_map_surface)
	var background := ColorRect.new()
	background.color=Color("#253a30")
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_map_surface.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_viewport=SubViewport.new()
	_map_viewport.name="LiveMapViewport"
	_map_viewport.size=Vector2i(800,500)
	_map_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	_map_viewport.handle_input_locally=false
	_map_viewport.gui_disable_input=true
	_map_viewport.msaa_3d=Viewport.MSAA_DISABLED
	_root.add_child(_map_viewport)
	_map_camera=Camera3D.new()
	_map_camera.name="LiveMapCamera"
	_map_camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	_map_camera.keep_aspect=Camera3D.KEEP_HEIGHT
	_map_camera.rotation_degrees=Vector3(-90,0,0)
	_map_camera.near=0.1
	_map_camera.far=8000.0
	_map_viewport.add_child(_map_camera)
	_map_camera.current=true
	_map_texture=TextureRect.new()
	_map_texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_map_texture.stretch_mode=TextureRect.STRETCH_SCALE
	_map_texture.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_map_surface.add_child(_map_texture)
	_map_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_overlay=Control.new()
	_map_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_map_surface.add_child(_map_overlay)
	_map_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_surface.gui_input.connect(_map_input)
	_map_surface.resized.connect(_sync_map_view)
	var scroll := _scroll(row,340)
	_map_points_box=_vbox(scroll,14)
	_map_points_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if _map_world != null:
		bind_map_world(_map_world,_map_bounds)
	else:
		_map_texture.texture=_map_viewport.get_texture()


func bind_map_world(world_3d: World3D,bounds: Rect2) -> void:
	_map_world=world_3d
	_map_bounds=bounds
	_map_center=bounds.get_center()
	_map_fit_pending=true
	if not is_instance_valid(_map_viewport):
		return
	_map_viewport.world_3d=world_3d
	_map_texture.texture=_map_viewport.get_texture()
	_sync_map_view.call_deferred()


func _process(delta: float) -> void:
	if _active_window!="map" or _pause_visible:
		return
	_map_refresh-=delta
	if _map_refresh<=0:
		_request_map_render()


func _request_map_render() -> void:
	if not is_instance_valid(_map_viewport) or _active_window!="map" or _map_world==null:
		return
	# The camera's fog-free environment is a fresh copy; the game's lighting stays intact.
	if _map_world.environment != null:
		var map_environment: Environment=_map_world.environment.duplicate()
		map_environment.fog_enabled=false
		map_environment.volumetric_fog_enabled=false
		_map_camera.environment=map_environment
	_map_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	_map_refresh=0.4


func _sync_map_view() -> void:
	if not is_instance_valid(_map_surface) or _map_surface.size.x<2 or _map_surface.size.y<2:
		return
	var display_size := _map_surface.size
	var resolution_scale := minf(_ui_scale,1280.0/display_size.x)
	_map_viewport.size=Vector2i(maxi(2,roundi(display_size.x*resolution_scale)),maxi(2,roundi(display_size.y*resolution_scale)))
	var aspect := display_size.x/display_size.y
	_map_fit_span=maxf(_map_bounds.size.y,_map_bounds.size.x/aspect)*1.04
	if _map_fit_pending:
		_map_span=_map_fit_span
		_map_center=_map_bounds.get_center()
		_map_fit_pending=false
	_map_span=clampf(_map_span,45.0,_map_fit_span)
	_map_center=_map_center.clamp(_map_bounds.position,_map_bounds.end)
	_map_camera.position=Vector3(_map_center.x,2400.0,_map_center.y)
	_map_camera.size=_map_span
	_map_zoom_label.text="Обзор · %.0f м" % _map_span
	_position_map_markers()
	_request_map_render()


func _fit_map() -> void:
	_map_fit_pending=true
	_sync_map_view()


func _focus_map_character() -> void:
	for person in _state.get("map_characters",[]):
		if bool(person.get("selected",false)) or str(person.get("id",""))==_selected_role:
			var point: Vector3=person.get("position",Vector3.ZERO)
			_map_center=Vector2(point.x,point.z)
			_map_span=minf(_map_span,250.0)
			_sync_map_view()
			return


func _zoom_map(factor: float,anchor: Vector2=Vector2(-1,-1)) -> void:
	var old_span := _map_span
	_map_span=clampf(_map_span*factor,45.0,_map_fit_span)
	if anchor.x>=0 and _map_surface.size.y>0:
		var offset := (anchor-_map_surface.size*0.5)/_map_surface.size.y
		_map_center+=offset*(old_span-_map_span)
	_sync_map_view()


func _map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_map(1.0/1.22,event.position)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_map(1.22,event.position)
		elif event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			_map_dragging=event.pressed
		_map_surface.accept_event()
	elif event is InputEventMouseMotion and _map_dragging:
		if event.button_mask==0:
			_map_dragging=false
		else:
			_map_center-=event.relative*(_map_span/maxf(1,_map_surface.size.y))
			_sync_map_view()
			_map_surface.accept_event()


func show_map(points: Array) -> void:
	_clear(_map_points_box)
	_clear(_map_overlay)
	_map_live_markers.clear()
	_map_markers.clear()
	_wrapped(_map_points_box,"Нажмите на остановку, чтобы отправиться. Колесо — масштаб, перетаскивание — обзор.",20,MUTED)
	for point in points:
		var id := str(point.get("id",""))
		var name_text := str(point.get("name",point.get("title",id)))
		if point.get("position") is Vector3:
			var leader := _map_leader()
			var marker := _button(_map_overlay,"",func(): _travel_to(id),Vector2(32,32),"travel")
			marker.size=Vector2(32,32)
			marker.add_theme_constant_override("icon_max_width",20)
			marker.add_theme_stylebox_override("normal",_style(Color("#1c3b30"),GOLD,16,3))
			marker.add_theme_stylebox_override("hover",_style(Color("#697e4b"),Color.WHITE,16,3))
			marker.add_theme_stylebox_override("pressed",_style(Color("#223b2b"),Color.WHITE,16,3))
			marker.tooltip_text=name_text+" · отправиться"
			marker.z_index=2
			_map_markers.append({"button":marker,"line":leader,"world_position":point.position})
		var panel := _panel(_map_points_box,12,Color("#20392f"))
		var box := _vbox(panel,10)
		_wrapped(box,name_text,23,GOLD)
		var row := _hbox(box,8)
		var travel := _button(row,"Идти / ехать",func(): _travel_to(id),Vector2(0,46),"travel")
		travel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_button(row,"",func():
			_close_windows()
			action_requested.emit("view_site",id),Vector2(46,46),"view").tooltip_text="Посмотреть камерой"
	_open_window("map")
	_update_map_live_markers()
	_sync_map_view.call_deferred()


func _travel_to(id: String) -> void:
	_close_windows()
	travel_requested.emit(id)


func _update_map_live_markers() -> void:
	if not is_instance_valid(_map_overlay):
		return
	var entries: Array=_state.get("map_characters",[]).duplicate()
	if _state.get("cart_position") is Vector3:
		entries.append({"id":"cart","name":"Повозка","position":_state.cart_position,"selected":false})
	var alive: Array=[]
	for entry in entries:
		var id := str(entry.get("id",""))
		if id.is_empty() or not entry.get("position") is Vector3:
			continue
		alive.append(id)
		if not _map_live_markers.has(id):
			var leader := _map_leader()
			var marker := _button(_map_overlay,"",func():
				var p: Vector3=_map_live_markers[id].world_position
				_map_center=Vector2(p.x,p.z)
				_map_span=minf(_map_span,180.0)
				_sync_map_view(),Vector2(38,38),id if id in ["brother","sister","cart"] else "follow")
			marker.size=Vector2(38,38)
			marker.add_theme_constant_override("icon_max_width",28)
			marker.z_index=4
			_map_live_markers[id]={"button":marker,"line":leader,"world_position":entry.position}
		var marker: Button=_map_live_markers[id].button
		var selected := bool(entry.get("selected",false))
		marker.tooltip_text=str(entry.get("name",id))+(" · выбран" if selected else "")+" · приблизить"
		marker.add_theme_stylebox_override("normal",_style(Color("#1b3734"),GOLD if selected else Color("#d1e9ee"),19,3))
		_map_live_markers[id].world_position=entry.position
	for id in _map_live_markers.keys():
		if id not in alive:
			_map_live_markers[id].button.queue_free()
			_map_live_markers[id].line.queue_free()
			_map_live_markers.erase(id)
	_position_map_markers()


func _position_map_markers() -> void:
	if not is_instance_valid(_map_camera) or not _map_camera.is_inside_tree() or _map_surface.size.y<=0:
		return
	var entries: Array=_map_markers.duplicate()
	entries.append_array(_map_live_markers.values())
	var occupied: Array[Rect2]=[]
	var limits := Rect2(Vector2.ZERO,_map_surface.size)
	var offsets: Array[Vector2]=[Vector2.ZERO]
	for radius in [44.0,88.0,132.0,176.0]:
		for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,-1),Vector2(-1,-1),Vector2(1,1),Vector2(-1,1)]:
			offsets.append(direction*radius)
	for entry in entries:
		var point: Vector3=entry.world_position
		var projected := _map_camera.unproject_position(point)*_map_surface.size/Vector2(_map_viewport.size)
		var button: Button=entry.button
		button.visible=limits.has_point(projected)
		var leader: Line2D=entry.line
		leader.visible=false
		if not button.visible:
			continue
		var center := projected
		for offset in offsets:
			var candidate := Rect2(projected+offset-button.size*0.5,button.size).grow(2)
			if not limits.encloses(candidate):
				continue
			var free := true
			for taken in occupied:
				if taken.intersects(candidate):
					free=false
					break
			if free:
				center=projected+offset
				break
		button.position=center-button.size*0.5
		occupied.append(Rect2(button.position,button.size).grow(2))
		if center.distance_to(projected)>1:
			leader.points=PackedVector2Array([projected,center])
			leader.visible=true


func _map_leader() -> Line2D:
	var line := Line2D.new()
	line.width=1.5
	line.default_color=Color("#e7d8adbb")
	line.z_index=1
	_map_overlay.add_child(line)
	return line


func _role_switcher(parent: Node) -> void:
	var row := _hbox(parent,8)
	for role in ["brother","sister"]:
		_button(row,_role_name(role),func():character_requested.emit(role),Vector2(165,44),role)


func _check(parent: Node,text: String,callback: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text=text
	box.focus_mode=Control.FOCUS_NONE
	box.mouse_filter=Control.MOUSE_FILTER_STOP
	box.custom_minimum_size.y=44
	box.set_meta("base_font_size",20)
	box.add_theme_font_size_override("font_size",roundi(20*_text_scale))
	box.add_theme_icon_override("checked",_texture("checked"))
	box.add_theme_icon_override("unchecked",_texture("unchecked"))
	box.add_theme_constant_override("h_separation",10)
	box.toggled.connect(callback)
	parent.add_child(box)
	return box


func _build_work() -> void:
	var window := _window("Дела · Брат",_close_windows)
	_work_window=window.panel
	_work_title=window.title
	var tabs := _hbox(window.body,8)
	_button(tabs,"Огород и отдых",func():_select_work_tab("garden"),Vector2(230,44),"garden")
	_button(tabs,"Спутники",func():_select_work_tab("companions"),Vector2(180,44),"follow")
	_spacer(tabs)
	_button(tabs,"Строить · B",show_construction,Vector2(190,44),"build")
	var scroll := _scroll(window.body)
	var body := _vbox(scroll,14)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_work_garden=_vbox(body,15)
	_role_switcher(_work_garden)
	_work_status=_wrapped(_work_garden,"Сейчас свободен",23,GOLD)
	_work_hint=_wrapped(_work_garden,"Герой сам подходит к грядкам: поливает, собирает урожай и сеет заново. Припасы и мотыга берутся из его личного рюкзака.",21)
	var actions := _hbox(_work_garden,10)
	_button(actions,"Огород: один обход",func():work_requested.emit("garden_once"),Vector2(300,52),"hoe")
	_button(actions,"Работать до вечера",func():work_requested.emit("garden_day"),Vector2(300,52),"garden")
	_work_stop=_button(actions,"Остановить",func():work_requested.emit("stop"),Vector2(190,52),"close")
	_new_plots_check=_check(_work_garden,"★ Разрешить новые грядки только на участках заданий",func(enabled):new_plots_toggled.emit(enabled))
	_wrapped(_work_garden,"Без галочки герой ухаживает только за уже существующими грядками. Произвольная земля не распахивается.",20,MUTED)
	_follow_check=_check(_work_garden,"Следовать за вторым героем",func(enabled):follow_toggled.emit(enabled))
	_wrapped(_work_garden,"Следование выключено по умолчанию. Каждый герой сохраняет свою работу и очередь действий.",20,MUTED)
	_work_companions=_vbox(body,14)
	_work_companions.hide()


func _select_work_tab(tab: String) -> void:
	_work_tab=tab
	_work_garden.visible=tab=="garden"
	_work_companions.visible=tab=="companions"
	_update_work()
	_settle_window_layout.call_deferred()


func _toggle_work() -> void:
	if _active_window=="work":
		_close_windows()
	else:
		show_work()


func show_work() -> void:
	_update_work()
	_open_window("work")


func _update_work() -> void:
	_work_title.text="Дела · "+_role_name(_selected_role)
	var mode := str(_state.get("work_mode",""))
	var sleep_value := roundi(float(_state.get("sleep",_state.get(_selected_role+"_sleep",100))))
	var mode_text := "Свободен"
	match mode:
		"garden_once": mode_text="Огород · один обход"
		"garden_day": mode_text="Огород · до вечера"
		"sleep": mode_text="Спит"
	_work_status.text=mode_text+" · выспался на "+str(sleep_value)+"%"
	_work_stop.disabled=mode.is_empty()
	_new_plots_check.set_pressed_no_signal(bool(_state.get("allow_new_plots",false)))
	_follow_check.set_pressed_no_signal(bool(_state.get("follow_enabled",_state.get("follow",false))))
	var companions: Array=_state.get("companions",[])
	var identities: Array=[]
	for c in companions:
		identities.append([c.get("id",""),c.get("name",""),c.get("recruited",false)])
	var key := hash(identities)
	if key==_companion_hash:
		_update_companion_values(companions)
		return
	_companion_hash=key
	_clear(_work_companions)
	_companion_rows.clear()
	if companions.is_empty():
		_wrapped(_work_companions,"Встретьте жителей Лиоры и пригласите их присоединиться к отряду.",22,MUTED)
	for companion in companions:
		var id := str(companion.get("id",""))
		var recruited := bool(companion.get("recruited",false))
		var panel := _panel(_work_companions,15,Color("#20392f"))
		var box := _vbox(panel,9)
		var header := _hbox(box,10)
		_icon(header,"follow",38)
		_label(header,str(companion.get("name",id)),24,GOLD)
		_spacer(header)
		_button(header,"Отпустить" if recruited else "Пригласить",func():action_requested.emit("dismiss" if recruited else "recruit",id),Vector2(170,44))
		_companion_rows[id]=_wrapped(box,"",20,MUTED)
		if recruited:
			var actions := _hbox(box,9)
			_button(actions,"Охранять",func():action_requested.emit("assign_guard",id),Vector2(200,44),"sword")
			_button(actions,"Огород",func():action_requested.emit("assign_garden",id),Vector2(200,44),"hoe")
			_button(actions,"Следовать",func():action_requested.emit("assign_follow",id),Vector2(200,44),"follow")
	_update_companion_values(companions)


func _update_companion_values(companions: Array) -> void:
	for companion in companions:
		var id := str(companion.get("id",""))
		if not _companion_rows.has(id):
			continue
		var task := str(companion.get("task","Свободен"))
		var task_names := {"guard":"Охраняет","garden":"Работает в огороде","follow":"Следует за отрядом","idle":"Свободен","":"Свободен"}
		_companion_rows[id].text="Здоровье %d · выспался %d%% · %s" % [roundi(float(companion.get("health",100))),roundi(float(companion.get("sleep",100))),task_names.get(task,task)]


func _build_skills() -> void:
	var window := _window("Навыки · Брат",_close_windows)
	_skills_window=window.panel
	_skills_title=window.title
	_role_switcher(window.body)
	_wrapped(window.body,"Опыт растёт от выполненной работы. Каждые 100 очков дают новый уровень в отдельном деле.",21,MUTED)
	var scroll := _scroll(window.body)
	var grid := GridContainer.new()
	grid.columns=2
	grid.add_theme_constant_override("h_separation",14)
	grid.add_theme_constant_override("v_separation",14)
	grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var skill_icons := {"crafting":"craft","woodcutting":"axe","carpentry":"saw","blacksmithing":"iron_ingot","weapon_smith":"iron_sword","armor_smith":"iron_armor","farming":"hoe","alchemy":"healing_potion","cooking":"ration","herbalism":"herb","animal_husbandry":"animal","mining":"pickaxe"}
	for skill in Campaign.SKILLS:
		var panel := _panel(grid,14,Color("#20392f"))
		panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var box := _vbox(panel,8)
		var row := _hbox(box,10)
		_icon(row,skill_icons.get(skill,"skills"),35)
		var title := _wrapped(row,Campaign.SKILLS[skill],23,GOLD)
		title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var value := _label(box,"Уровень 0 · 0 / 100 опыта",20)
		var bar := _progress(box,GREEN,9)
		_skill_rows[skill]={"value":value,"bar":bar}


func _toggle_skills() -> void:
	if _active_window=="skills":
		_close_windows()
	else:
		show_skills()


func show_skills() -> void:
	_update_skills()
	_open_window("skills")


func _update_skills() -> void:
	_skills_title.text="Навыки · "+_role_name(_selected_role)
	var skills: Dictionary=_state.get("skills",{})
	for skill in _skill_rows:
		var raw: Variant=skills.get(skill,{})
		var xp := 0.0
		var level := 0
		if raw is Dictionary:
			xp=float(raw.get("xp",0))
			level=int(raw.get("level",floori(xp/100.0)))
		else:
			xp=float(raw)
			level=floori(xp/100.0)
		var remainder := fmod(xp,100.0)
		_skill_rows[skill].value.text="Уровень %d · %d / 100 опыта" % [level,floori(remainder)]
		_skill_rows[skill].value.tooltip_text="Всего опыта: "+str(floori(xp))
		_skill_rows[skill].bar.value=remainder


func _build_construction() -> void:
	var window := _window("Строительство",_close_windows)
	_build_window=window.panel
	_wrapped(window.body,"Выберите постройку, затем укажите место в мире. Материалы берутся из рюкзака выбранного героя.",21,MUTED)
	var scroll := _scroll(window.body)
	_build_list=_vbox(scroll,12)
	_build_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL


func _toggle_construction() -> void:
	if _active_window=="build":
		_close_windows()
	else:
		show_construction()


func show_construction() -> void:
	_update_build_options()
	_open_window("build")


func _update_build_options() -> void:
	var options: Array=_state.get("build_options",[])
	var key := hash([options,_inventory])
	if key==_build_hash:
		return
	_build_hash=key
	_clear(_build_list)
	if options.is_empty():
		_wrapped(_build_list,"Список построек появится после подготовки участка.",22,MUTED)
	var icons := {"fence":"plank","fences":"plank","shelter":"build","workbench":"craft","sawmill":"saw","smelter":"iron_ingot","anvil":"iron_blank","cauldron":"healing_potion","stable":"animal","bed":"sleep","storage":"cart"}
	for option in options:
		var id := str(option.get("id",""))
		var panel := _panel(_build_list,14,Color("#20392f"))
		var row := _hbox(panel,14)
		_icon(row,icons.get(id,"build"),52)
		var box := _vbox(row,7)
		box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_wrapped(box,str(option.get("name",id)),24,GOLD)
		var costs := PackedStringArray()
		var cost: Dictionary=option.get("cost",{})
		for material in cost:
			costs.append("%s %d/%d" % [ITEM_NAMES.get(material,material),int(_inventory.get(material,0)),int(cost[material])])
		_wrapped(box," · ".join(costs),20)
		var reason := str(option.get("reason",""))
		if not bool(option.get("enabled",true)) and not reason.is_empty():
			_wrapped(box,reason,20,RED)
		var build := _button(row,"Разместить",func():
			_close_windows()
			build_requested.emit(id),Vector2(172,50),"build")
		build.disabled=not bool(option.get("enabled",true))
		build.tooltip_text=reason
		build.size_flags_vertical=Control.SIZE_SHRINK_CENTER


func _build_life() -> void:
	_life_ui=LifeUI.new(self)
	_life_strip=_panel(_root,7)
	# Control input follows tree order; keep the strip below every modal window.
	_root.move_child(_life_strip,_hotbar.get_index()+1)
	_life_strip.hide()
	var row := _hbox(_life_strip,5)
	_button(row,"Жизнь",_toggle_life,Vector2(107,38),"life").tooltip_text="Персонаж, люди, работа и дом · L"
	_icon(row,"money",25)
	_life_funds=_label(row,"0",20,GOLD)
	_life_funds.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_life_funds.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	_life_speeds=_hbox(row,4)


func update_life(data: Dictionary) -> void:
	_life_data=data
	if _life_ui==null:return
	_life_strip.visible=not data.is_empty()
	var summary: Dictionary=data.get("summary",{})
	var funds := int(summary.get("funds",0))
	_life_funds.text=_life_ui._money(funds)
	_life_funds.tooltip_text="Семейный бюджет · %s %s" % [funds,summary.get("currency","")]
	var weather := str(summary.get("weather",""))
	var season := str(summary.get("season",""))
	_weather_label.text=season+(" · " if not season.is_empty() and not weather.is_empty() else "")+weather
	_weather_label.visible=not _weather_label.text.is_empty()
	_character_names.clear()
	_household_roles=["brother","sister"]
	for member in data.get("household",[]):
		var id := str(member.get("id",""))
		if id.is_empty():continue
		var selectable := false
		for action in member.get("actions",[]):
			if str(action.get("id",""))=="select_member":selectable=true
		if not selectable:continue
		_character_names[id]=str(member.get("name",id))
		if id not in _household_roles:_household_roles.append(id)
	var selected: Dictionary=data.get("selected",{})
	if selected.has("id"):_character_names[str(selected.id)]=str(selected.get("name",selected.id))
	for role in _family_names:
		_family_names[role].text=_role_name(role)
		_family_names[role].tooltip_text=_role_name(role)
	_queue_title.text="Очередь · "+_role_name(_selected_role)
	var speed_actions: Array=summary.get("speed_actions",[])
	var key := hash(speed_actions)
	if key!=_life_speed_key:
		_life_speed_key=key
		_clear(_life_speeds)
		_life_speed_buttons.clear()
		for action in speed_actions:
			var button := _button(_life_speeds,str(action.get("label","")),func():
				life_requested.emit(str(action.get("id","set_speed")),action.get("payload",{}).duplicate(true)),Vector2(40,38))
			button.disabled=not bool(action.get("enabled",true))
			button.tooltip_text=str(action.get("reason","Скорость жизни"))
			_life_speed_buttons[str(action.get("payload",{}).get("value",action.get("label","")))]=button
	var speed := float(summary.get("speed",1))
	for value in _life_speed_buttons:
		_life_speed_buttons[value].add_theme_stylebox_override("normal",_style(Color("#29443a"),GOLD if is_equal_approx(float(value),speed) else BORDER,5,6))
	_life_ui.update_model(data)


func show_life(tab: String="wellbeing") -> void:
	if _life_ui==null:return
	var aliases := {"wellbeing":"needs","needs":"needs","personality":"personality","skills":"skills","memories":"memories","family":"family","appearance":"appearance"}
	if aliases.has(tab):_life_ui.show_tab("profile",aliases[tab])
	elif tab in ["household","properties","animals"]:
		_life_ui.home_tab=tab
		_life_ui.show_tab("home")
	else:_life_ui.show_tab("careers" if tab=="career" else tab)
	_open_window("life")
	_life_ui.refresh_visible()


func _toggle_life() -> void:
	if _active_window=="life":_close_windows()
	else:show_life()
