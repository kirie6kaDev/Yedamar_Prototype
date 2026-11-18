extends RefCounted
## Original small household props. Only click layers: no new broad navigation blockers.
var owner: Node3D
var game
var nodes: Dictionary = {}
var flames: Dictionary = {}
var cloths: Dictionary = {}
var _materials: Dictionary = {}

func configure(parent: Node3D, owner_game) -> void:
	owner=parent
	game=owner_game

func _mat(color: Color) -> StandardMaterial3D:
	var key:=color.to_html()
	if not _materials.has(key):
		var m:=StandardMaterial3D.new()
		m.albedo_color=color
		m.roughness=.9
		_materials[key]=m
	return _materials[key]

func box(parent: Node3D, p: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh:=BoxMesh.new()
	mesh.size=size
	var n:=MeshInstance3D.new()
	n.mesh=mesh
	n.material_override=_mat(color)
	n.position=p
	parent.add_child(n)
	return n

func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x,float(game.world.sample_height(p.x,p.y)),p.y)

func safe_point(p: Vector2, from: Vector3) -> Vector3:
	for radius: float in [0.0,3.0,6.0,9.0,13.0]:
		for i in 12:
			var q:=p+Vector2(cos(float(i)*TAU/12),sin(float(i)*TAU/12))*radius
			if not game.navigation.is_walkable(q): continue
			var point:=_ground(q)
			var path:PackedVector3Array=game.navigation.path(from,point)
			if not path.is_empty() and path[-1].distance_to(point)<2.0: return point
	return from

func add_fixture(id: String, kind: String, home: String, desired: Vector2, entry: Vector3) -> Dictionary:
	if nodes.has(id): return {}
	var approach:=safe_point(desired,entry)
	var p:=_ground(Vector2(approach.x,approach.z)-Vector2(0,1.25))
	var root:=Node3D.new()
	root.name=id
	owner.add_child(root)
	root.global_position=p
	nodes[id]=root
	var wood:=Color(.32,.19,.10)
	var linen:=Color(.86,.82,.68)
	match kind:
		"drying_line":
			for x: float in [-2.0,2.0]: box(root,Vector3(x,1.35,0),Vector3(.16,2.7,.16),wood)
			box(root,Vector3(0,2.4,0),Vector3(4.1,.035,.035),Color(.25,.19,.12))
			var cloth:=Node3D.new()
			root.add_child(cloth)
			for x: float in [-1.25,0.0,1.25]: box(cloth,Vector3(x,1.7,0),Vector3(.9,1.3,.035),linen)
			cloth.visible=false
			cloths[id]=cloth
		"cradle":
			box(root,Vector3(0,.42,0),Vector3(1.1,.12,1.8),wood)
			box(root,Vector3(0,.52,0),Vector3(.9,.12,1.5),linen)
			for x: float in [-.52,.52]: box(root,Vector3(x,.7,0),Vector3(.10,.6,1.8),wood)
			for z: float in [-.85,.85]:
				box(root,Vector3(0,.65,z),Vector3(1.1,.45,.10),wood)
				box(root,Vector3(0,.12,z),Vector3(1.35,.16,.16),wood)
		"wash_tub":
			var mesh:=CylinderMesh.new()
			mesh.top_radius=.85; mesh.bottom_radius=.70; mesh.height=.55
			var tub:=MeshInstance3D.new()
			tub.mesh=mesh; tub.material_override=_mat(wood); tub.position.y=.3; root.add_child(tub)
			var water:=CylinderMesh.new()
			water.top_radius=.76; water.bottom_radius=.76; water.height=.02
			var surface:=MeshInstance3D.new()
			surface.mesh=water; surface.material_override=_mat(Color(.25,.44,.48)); surface.position.y=.58; root.add_child(surface)
			var board:=box(root,Vector3(.35,.77,0),Vector3(.35,.06,1.1),Color(.62,.44,.24))
			board.rotation.x=-.4
		_:
			box(root,Vector3(0,.4,0),Vector3(.85,.75,.85),Color(.52,.35,.17))
			for i in 5: box(root,Vector3(0,.12+i*.14,.438),Vector3(.9,.025,.025),Color(.23,.14,.07))
			box(root,Vector3(0,.8,0),Vector3(.72,.15,.7),linen)
	var body:=StaticBody3D.new()
	body.collision_layer=2; body.collision_mask=0
	body.set_meta("object_id",id)
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(4.3,2.8,.5) if kind=="drying_line" else Vector3(1.5,1.5,1.8)
	collision.shape=shape; collision.position.y=shape.size.y*.5
	body.add_child(collision); root.add_child(body)
	var title:String=preload("res://scripts/domestic_catalog.gd").NAMES[kind]
	game.world.objects[id]={"id":id,"type":"domestic","name":title,"position":p,"approach":approach,"description":"Домашнее хозяйство","node":root,"surface_radius":.8,"domestic_id":id}
	return {"id":id,"kind":kind,"name":title,"home":home,"position":[p.x,p.y,p.z],"approach":[approach.x,approach.y,approach.z]}

func update_fire(id: String, point: Vector3, amount: float) -> void:
	if amount<=0:
		if flames.has(id): flames[id].visible=false
		return
	if not flames.has(id):
		var root:=Node3D.new()
		owner.add_child(root)
		var material:=StandardMaterial3D.new()
		material.albedo_color=Color(1,.27,.025)
		material.emission_enabled=true
		material.emission=Color(1,.15,.01)
		material.emission_energy_multiplier=1.3
		for i in 3:
			var cone:=CylinderMesh.new()
			cone.top_radius=.03; cone.bottom_radius=.35; cone.height=1.6+float(i)*.3
			var mesh:=MeshInstance3D.new()
			mesh.mesh=cone; mesh.material_override=material
			mesh.position=Vector3((i-1)*.42,.8+float(i)*.15,0)
			root.add_child(mesh)
		var light:=OmniLight3D.new()
		light.light_color=Color(1,.33,.08); light.light_energy=1.5; light.omni_range=7
		light.position.y=1.5; root.add_child(light)
		flames[id]=root
	flames[id].visible=true
	flames[id].global_position=point+Vector3(0,.55,.9)
	flames[id].scale=Vector3.ONE*(.65+amount/140)

func set_laundry(id: String, visible: bool) -> void:
	if cloths.has(id): cloths[id].visible=visible

func clear_fires() -> void:
	for node: Node3D in flames.values(): node.queue_free()
	flames.clear()

func remove_fixture(id: String) -> void:
	if nodes.has(id):
		var node:Node3D=nodes[id]
		if is_instance_valid(node):
			if node.get_parent(): node.get_parent().remove_child(node)
			node.queue_free()
		nodes.erase(id)
	cloths.erase(id)
	game.world.objects.erase(id)
