extends CharacterBody3D

signal arrived
signal movement_failed

const CHARACTER_VISUAL=preload("res://scripts/character_visual.gd")

const MODELS := {
	"brother": "res://assets/actors/Knight.glb",
	"sister": "res://assets/actors/Rogue.glb",
	"enemy": "res://assets/actors/Rogue_Hooded.glb",
	"boss": "res://assets/actors/Barbarian.glb",
}
const ACTIONS := {
	"attack": "1H_Melee_Attack_Slice_Diagonal", "hit": "Hit_A",
	"death": "Death_A", "interact": "Interact", "pickup": "PickUp",
	"mine": "1H_Melee_Attack_Chop", "chop": "1H_Melee_Attack_Chop",
	"dig": "1H_Melee_Attack_Chop", "saw_work": "1H_Melee_Attack_Stab", "forge_work": "1H_Melee_Attack_Chop",
	"craft": "Interact", "drink": "Use_Item", "eat": "Use_Item",
	"hide": "Sit_Floor_Down", "cheer": "Cheer", "idle": "Idle",
}
var display_name: String = "Путник"
var role: String = "brother"
var health: float = 100.0
var max_health: float = 100.0
var hidden_in_cover: bool = false
var move_speed: float = 6.0
var weapon_equipped: bool = false
var armor_equipped: bool = false
var selected: bool = false:
	set(value):
		selected = value
		if is_instance_valid(_ring):
			_ring.visible = value and not hidden_in_cover
var _height: Callable
var _nav: RefCounted
var _model: Node3D
var _animation: AnimationPlayer
var _ring: MeshInstance3D
var _label: Label3D
var _bar: MeshInstance3D
var _bar_material: StandardMaterial3D
var _path := PackedVector3Array()
var _cursor := 0
var _action_left := 0.0
var _body_height := 1.8
var _configured := false
var _death_played := false
var _target := Vector3.ZERO
var _animation_names: Dictionary = {}
var _health_last := -1.0
var _recoveries := 0
var _pickaxe: BoneAttachment3D
var _sword: MeshInstance3D
var _mining := false
var _work_clip := ""
var _work_tools: Dictionary = {}
var _tool_mode := ""
var _armor: BoneAttachment3D
var _appearance_key:=""
var _visual_profile:Dictionary={}
var _visual_identity:String=""
var _appearance_base_scale:=Vector3.ONE


func _build_character_model()->void:
	var modern:bool=role not in ["enemy","boss"]
	_model = CHARACTER_VISUAL.build(role,_visual_profile) if modern else (load(MODELS.get(role, MODELS.brother)) as PackedScene).instantiate() as Node3D
	_visual_identity=CHARACTER_VISUAL.key(role,_visual_profile) if modern else "legacy"
	_model.name = "Персонаж"
	var native_height := {"brother": 2.3145, "sister": 2.187, "enemy": 2.187, "boss": 2.1863}
	_model.scale = Vector3.ONE * _body_height / (1.84 if modern else float(native_height.get(role, 2.2)))
	_appearance_base_scale=_model.scale
	add_child(_model)
	var accessories := ["1H_Sword_Offhand", "Rectangle_Shield", "Round_Shield", "Spike_Shield", "Badge_Shield", "2H_Sword", "Knight_Helmet", "Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Throwable", "Knife", "Spellbook", "Spellbook_open", "1H_Wand", "2H_Staff", "1H_Axe_Offhand", "Barbarian_Round_Shield", "2H_Axe", "Mug"]
	for node: Node in _model.find_children("*", "", true, false):
		if node is MeshInstance3D and String(node.name) in accessories:
			node.visible = role == "enemy" and String(node.name) == "Knife"
		if node is AnimationPlayer:
			_animation = node
		if node is MeshInstance3D and String(node.name) == "1H_Sword":
			_sword = node
	if _animation:
		for clip in _animation.get_animation_list():
			var base := String(clip).get_slice("/", String(clip).get_slice_count("/") - 1)
			_animation_names[base] = clip
			if base in ["Idle", "Walking_A", "Running_A", "Sit_Floor_Idle"]:
				_animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_play("Idle")
	_build_pickaxe()
	_build_work_tools()
	_build_armor()
	if modern:_build_human_sword()
	_model.visible=not hidden_in_cover
	if not _work_clip.is_empty():
		_show_work_tool(_tool_mode)
		if _animation.has_animation(_work_clip):_animation.play(_work_clip,.1)
		_model.position.y=.35 if _work_clip=="Lie_Idle" else 0.0


func configure(actor_role: String, actor_name: String, height_sampler: Callable, nav: RefCounted) -> void:
	role = actor_role
	display_name = actor_name
	_height = height_sampler
	_nav = nav
	_configured = true
	if is_node_ready():
		_build_visual()


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	set_meta("actor_role", role)
	if _configured:
		_build_visual()


func _build_visual() -> void:
	if is_instance_valid(_model):
		return
	set_meta("actor_role", role)
	_body_height = 1.8
	if role == "sister":
		_body_height = 1.38
	elif role == "boss":
		_body_height = 2.25
	_build_character_model()
	var shape := CapsuleShape3D.new()
	shape.height = _body_height
	shape.radius = 0.38
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = _body_height * 0.5
	add_child(collider)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.62
	torus.outer_radius = 0.71
	torus.rings = 32
	torus.ring_segments = 8
	_ring.mesh = torus
	_ring.position.y = 0.08
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color("#eacb73")
	_ring.material_override = ring_material
	_ring.visible = selected
	add_child(_ring)
	_label = Label3D.new()
	_label.text = display_name
	_label.font_size = 48
	_label.outline_size = 10
	_label.pixel_size = 0.007
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position.y = _body_height + 0.45
	_label.modulate = Color("#ffe5a0") if role in ["brother", "sister"] else Color("#f7bdab")
	add_child(_label)
	_bar = MeshInstance3D.new()
	var bar_mesh := QuadMesh.new()
	bar_mesh.size = Vector2(1.0, 0.07)
	_bar.mesh = bar_mesh
	_bar.position.y = _body_height + 0.2
	_bar_material = StandardMaterial3D.new()
	_bar_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_bar_material.no_depth_test = true
	_bar_material.albedo_color = Color("#8eb58a") if role in ["brother", "sister"] else Color("#c55649")
	_bar.material_override = _bar_material
	add_child(_bar)
	_update_health()
	set_weapon_equipped(weapon_equipped)
	set_armor_equipped(armor_equipped)
	set_hidden_in_cover(hidden_in_cover)


func navigate_to(target: Vector3) -> bool:
	if not _configured or not is_instance_valid(_nav) or health <= 0.0:
		return false
	if not _work_clip.is_empty():
		end_work()
	var route: PackedVector3Array = _nav.path(global_position, target)
	if route.is_empty():
		stop_moving()
		movement_failed.emit()
		return false
	_target = target
	if _mining:
		_action_left = 0.0
		_show_mining_tool(false)
	_path = route
	_cursor = 0
	_recoveries = 0
	set_hidden_in_cover(false)
	return true


func is_moving() -> bool:
	return _cursor < _path.size() and health > 0.0


func stop_moving() -> void:
	_path.clear()
	_cursor = 0
	velocity = Vector3.ZERO
	if _action_left <= 0.0 and not hidden_in_cover:
		_play("Idle")


func play_action(action: String) -> void:
	if not is_instance_valid(_animation):
		return
	if not _work_clip.is_empty():
		end_work()
	var clip := String(ACTIONS.get(action, action))
	_show_mining_tool(action == "mine")
	if _mining:
		clip = "Mining"
	if action == "attack" and role == "brother" and not weapon_equipped:
		clip = "Unarmed_Melee_Attack_Punch_A"
	if action == "death":
		stop_moving()
		_death_played = true
		_action_left = INF
	elif action == "idle":
		_action_left = 0.0
	else:
		var key: String = _animation_names.get(clip, "")
		_action_left = 2.8 if _mining else (_animation.get_animation(key).length if not key.is_empty() else 0.65)
	_play(clip, true)

func begin_work(action:String)->void:
	if not is_instance_valid(_animation):
		return
	stop_moving()
	var clip:=str(ACTIONS.get(action,action))
	if action=="mine": clip="Mining"
	elif _animation_names.has("Work_"+action): clip="Work_"+action
	var key:String=_animation_names.get(clip,"")
	if key.is_empty(): key=_animation_names.get("Interact","")
	if not key.is_empty():
		_animation.get_animation(key).loop_mode=Animation.LOOP_LINEAR
		_animation.play(key,.2)
	_work_clip=key
	_action_left=INF
	_show_work_tool(action)
	if is_instance_valid(_model): _model.position.y=.35 if action=="Lie_Idle" else 0.0

func end_work()->void:
	_work_clip=""
	_action_left=0
	_show_work_tool("")
	if is_instance_valid(_model): _model.position.y=0
	_play("Idle")


func set_weapon_equipped(value: bool) -> void:
	weapon_equipped = value
	if is_instance_valid(_sword) and role not in ["enemy","boss"]:
		_sword.visible = value and _tool_mode.is_empty()


func set_armor_equipped(value: bool) -> void:
	armor_equipped = value
	if is_instance_valid(_armor):
		_armor.visible = value

func apply_appearance(data:Dictionary,stage:String="adult")->void:
	if not is_instance_valid(_model): return
	var key:String=JSON.stringify(data)+stage
	if key==_appearance_key: return
	_appearance_key=key
	if role not in ["enemy","boss"] and CHARACTER_VISUAL.key(role,data)!=_visual_identity:
		_model.queue_free()
		_model=null
		_animation=null
		_pickaxe=null
		_sword=null
		_armor=null
		_work_tools.clear()
		_animation_names.clear()
		_visual_profile=data.duplicate(true)
		_build_character_model()
	var height:float={"short":.88,"average":1.0,"tall":1.12}.get(str(data.get("height","average")),1.0)
	var width:float={"slim":.88,"average":1.0,"broad":1.16}.get(str(data.get("body","average")),1.0)
	var age_scale:float={"infant":.35,"toddler":.48,"child":.68,"teen":.87,"elder":.96}.get(stage,1.0)
	if role=="sister": age_scale=1.0
	_model.scale=_appearance_base_scale*Vector3(width*age_scale,height*age_scale,width*age_scale)
	if role not in ["enemy","boss"]:
		var cloth_tint:Color={"green":Color(.80,1.0,.75),"blue":Color(.65,.80,1.0),"red":Color(1.0,.70,.65),"brown":Color.WHITE}.get(str(data.get("color","brown")),Color.WHITE)
		for node:MeshInstance3D in _model.find_children("*","MeshInstance3D",true,false):
			if str(node.name).begins_with("Face_"):continue
			for surface in node.mesh.get_surface_count():
				var mat:Material=node.get_surface_override_material(surface)
				if mat is StandardMaterial3D and ("Peasant" in mat.resource_name or "Ranger" in mat.resource_name):mat.albedo_color=cloth_tint
		return
	var palette:Dictionary={"green":Color("#597350"),"blue":Color("#536a91"),"red":Color("#8e4d44"),"brown":Color("#867059")}
	var cloth:Color=palette.get(str(data.get("color","brown")),Color("#867059"))
	var outfit:String=str(data.get("outfit","wanderer"))
	for node in _model.find_children("*","MeshInstance3D",true,false):
		var title:String=str(node.name).to_lower()
		if title in ["knife","knife_offhand"]: node.visible=false
		if title in ["knight_helmet","badge_shield"]: node.visible=outfit=="guard"
		if title in ["mug","spellbook","spellbook_open"]: node.visible=false
		if "body" in title or "cape" in title or "hood" in title or "legs" in title:
			var mat:=StandardMaterial3D.new()
			mat.albedo_color=cloth
			mat.roughness=.95
			node.material_override=mat


func _build_pickaxe() -> void:
	var skeleton := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if not skeleton:
		var skeletons := _model.find_children("*", "Skeleton3D", true, false)
		if skeletons.is_empty():
			return
		skeleton = skeletons[0] as Skeleton3D
	if skeleton.find_bone("handslot.r") < 0:
		return
	_pickaxe = BoneAttachment3D.new()
	_pickaxe.name = "Каменная кирка"
	_pickaxe.bone_name = "handslot.r"
	skeleton.add_child(_pickaxe)
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.045
	shaft_mesh.bottom_radius = 0.055
	shaft_mesh.height = 1.18
	shaft_mesh.radial_segments = 7
	shaft.mesh = shaft_mesh
	shaft.position.y = 0.34
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#654c30")
	wood.roughness = 0.95
	shaft.material_override = wood
	_pickaxe.add_child(shaft)
	var head := MeshInstance3D.new()
	var head_mesh := PrismMesh.new()
	head_mesh.size = Vector3(0.74, 0.19, 0.20)
	head.mesh = head_mesh
	head.position.y = 0.83
	head.rotation.z = -0.12
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#8d9298")
	stone.roughness = 0.84
	head.material_override = stone
	_pickaxe.add_child(head)
	var binding := MeshInstance3D.new()
	var binding_mesh := BoxMesh.new()
	binding_mesh.size = Vector3(0.14, 0.22, 0.25)
	binding.mesh = binding_mesh
	binding.position.y = 0.81
	binding.material_override = wood
	_pickaxe.add_child(binding)
	_pickaxe.hide()
	if _animation_names.has("1H_Melee_Attack_Chop"):
		var animation: Animation = _animation.get_animation(_animation_names["1H_Melee_Attack_Chop"]).duplicate()
		animation.loop_mode = Animation.LOOP_LINEAR
		var library := AnimationLibrary.new()
		library.add_animation("Mining", animation)
		_animation.add_animation_library("tools", library)
		_animation_names["Mining"] = "tools/Mining"


func _show_mining_tool(value: bool) -> void:
	_show_work_tool("mine" if value else "")


func _show_work_tool(action: String) -> void:
	_tool_mode = action if action == "mine" or _work_tools.has(action) else ""
	_mining = action == "mine"
	if is_instance_valid(_pickaxe):
		_pickaxe.visible = _mining
	for key: String in _work_tools:
		_work_tools[key].visible = key == action
	if is_instance_valid(_sword) and role not in ["enemy","boss"]:
		_sword.visible = weapon_equipped and _tool_mode.is_empty()


func _tool_material(color: String, metal: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = 0.55 if metal else 0.9
	material.metallic = 0.55 if metal else 0.0
	return material


func _tool_box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh


func _tool_shaft(parent: Node3D, length: float, center: float, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.043
	cylinder.bottom_radius = 0.052
	cylinder.height = length
	cylinder.radial_segments = 7
	mesh.mesh = cylinder
	mesh.position.y = center
	mesh.material_override = material
	parent.add_child(mesh)


func _build_work_tools() -> void:
	if not is_instance_valid(_pickaxe):
		return
	var skeleton := _pickaxe.get_parent() as Skeleton3D
	var wood := _tool_material("#795834")
	var steel := _tool_material("#9baaa7",true)
	var dark_steel := _tool_material("#566964",true)
	for action in ["chop","dig","saw_work","forge_work"]:
		var attachment := BoneAttachment3D.new()
		attachment.name = "WorkTool_"+action
		attachment.bone_name = "handslot.r"
		skeleton.add_child(attachment)
		_work_tools[action] = attachment
		match action:
			"chop":
				_tool_shaft(attachment,1.05,0.30,wood)
				_tool_box(attachment,Vector3(0.10,0.70,0),Vector3(0.40,0.28,0.18),dark_steel)
				var blade := MeshInstance3D.new()
				var prism := PrismMesh.new()
				prism.size = Vector3(0.40,0.43,0.17)
				blade.mesh = prism
				blade.position = Vector3(0.33,0.70,0)
				blade.rotation.z = -PI*0.5
				blade.material_override = steel
				attachment.add_child(blade)
			"dig":
				_tool_shaft(attachment,1.55,0.50,wood)
				var head := _tool_box(attachment,Vector3(0,1.18,0.15),Vector3(0.43,0.10,0.41),dark_steel)
				head.rotation.x = -0.30
				_tool_box(attachment,Vector3(0,1.11,0.34),Vector3(0.45,0.08,0.08),steel)
			"saw_work":
				_tool_box(attachment,Vector3(0,0.59,0),Vector3(0.27,0.89,0.035),steel)
				for i in range(8):
					var tooth := _tool_box(attachment,Vector3(-0.15,0.22+i*0.10,0),Vector3(0.075,0.075,0.038),steel)
					tooth.rotation.z = PI*0.25
				for x in [-0.15,0.15]:
					_tool_box(attachment,Vector3(x,0.04,0),Vector3(0.075,0.32,0.09),wood)
				for y in [-0.12,0.20]:
					_tool_box(attachment,Vector3(0,y,0),Vector3(0.36,0.075,0.09),wood)
			"forge_work":
				_tool_shaft(attachment,0.72,0.19,wood)
				_tool_box(attachment,Vector3(0,0.52,0),Vector3(0.49,0.24,0.25),dark_steel)
				for x in [-0.25,0.25]:
					_tool_box(attachment,Vector3(x,0.52,0),Vector3(0.07,0.25,0.27),steel)
		attachment.hide()
		var source: String = _animation_names.get(ACTIONS[action],"")
		if not source.is_empty():
			var animation: Animation = _animation.get_animation(source).duplicate()
			animation.loop_mode = Animation.LOOP_LINEAR
			var library := _animation.get_animation_library("tools")
			library.add_animation("Work_"+action,animation)
			_animation_names["Work_"+action] = "tools/Work_"+action


func _build_armor() -> void:
	if role not in ["brother","sister"] or not is_instance_valid(_pickaxe):
		return
	var skeleton := _pickaxe.get_parent() as Skeleton3D
	if skeleton.find_bone("chest") < 0:
		return
	_armor = BoneAttachment3D.new()
	_armor.name = "Кованый нагрудник"
	_armor.bone_name = "chest"
	skeleton.add_child(_armor)
	var iron := _tool_material("#91b1b5",true)
	var trim := _tool_material("#c2aa72",true)
	_tool_box(_armor,Vector3(0,0.04,0.34),Vector3(0.68,0.51,0.13),iron)
	_tool_box(_armor,Vector3(0,0.02,-0.31),Vector3(0.65,0.48,0.12),iron)
	for x in [-0.34,0.34]:
		_tool_box(_armor,Vector3(x,0.29,0.015),Vector3(0.22,0.14,0.48),iron)
	_tool_box(_armor,Vector3(0,-0.19,0.415),Vector3(0.69,0.055,0.035),trim)
	_tool_box(_armor,Vector3(0,0.22,0.415),Vector3(0.44,0.045,0.035),trim)
	_armor.visible = armor_equipped


func set_hidden_in_cover(value: bool) -> void:
	hidden_in_cover = value
	if not is_instance_valid(_model):
		return
	_model.visible = not value
	_ring.visible = selected and not value
	_label.text = display_name + (" · в укрытии" if value else "")
	_bar.visible = not value and health > 0.0
	if value:
		stop_moving()


func _physics_process(delta: float) -> void:
	if not _configured or not is_instance_valid(_model):
		return
	if health != _health_last:
		_update_health()
	if health <= 0.0:
		if not _death_played:
			play_action("death")
		return
	if _death_played:
		_death_played = false
		_action_left = 0.0
		_play("Idle")
	_action_left = maxf(0.0, _action_left - delta)
	if _mining and _action_left <= 0.0:
		_show_mining_tool(false)
	if is_moving() and _action_left <= 0.0:
		var destination := _path[_cursor]
		var offset := Vector3(destination.x - global_position.x, 0.0, destination.z - global_position.z)
		var travel := minf(move_speed * delta, offset.length())
		if offset.length() < 0.1:
			_cursor += 1
			if not is_moving():
				stop_moving()
				arrived.emit()
		else:
			var direction := offset.normalized()
			var next := global_position + direction * travel
			if not _nav.is_walkable(Vector2(next.x, next.z)):
				_recoveries += 1
				if _recoveries > 2:
					stop_moving()
					movement_failed.emit()
					return
				_path = _nav.path(global_position, _target)
				_cursor = 0
				if _path.is_empty():
					stop_moving()
					movement_failed.emit()
				return
			global_position.x = next.x
			global_position.z = next.z
			velocity = direction * move_speed
			_model.rotation.y = lerp_angle(_model.rotation.y, atan2(direction.x, direction.z), minf(1.0, delta * 12.0))
			_play("Running_A" if move_speed > 3.5 else "Walking_A")
	elif _action_left <= 0.0 and not hidden_in_cover:
		_play("Idle")
	global_position.y = float(_height.call(global_position.x, global_position.z))


func _play(name_of_clip: String, restart: bool = false) -> void:
	if not is_instance_valid(_animation):
		return
	var key: String = _animation_names.get(name_of_clip, "")
	if not key.is_empty() and (restart or String(_animation.current_animation) != key):
		_animation.play(key, 0.12)


func _update_health() -> void:
	_health_last = health
	if is_instance_valid(_bar):
		_bar.scale.x = maxf(0.001, clampf(health / maxf(1.0, max_health), 0.0, 1.0))
		_bar.visible = health > 0.0 and not hidden_in_cover


func _build_human_sword()->void:
	if not is_instance_valid(_pickaxe):return
	var attachment:=BoneAttachment3D.new()
	attachment.name="SwordGrip"
	attachment.bone_name="handslot.r"
	_pickaxe.get_parent().add_child(attachment)
	_sword=MeshInstance3D.new()
	_sword.name="1H_Sword"
	var blade:=PrismMesh.new()
	blade.size=Vector3(.105,.82,.045)
	_sword.mesh=blade
	_sword.position.y=.57
	_sword.material_override=_tool_material("#aab9b9",true)
	attachment.add_child(_sword)
	_tool_box(_sword,Vector3(0,-.42,0),Vector3(.33,.045,.08),_tool_material("#b59757",true))
	_tool_box(_sword,Vector3(0,-.53,0),Vector3(.07,.19,.07),_tool_material("#4e392c"))
	_sword.visible=weapon_equipped
