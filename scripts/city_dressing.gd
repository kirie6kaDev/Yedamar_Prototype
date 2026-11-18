extends RefCounted
## Visual architecture only. No colliders, interaction IDs or gameplay state.
## Each roof/wall keeps its own batched decorations so cutaways remain correct.

var city
var world
var _materials:Dictionary={}
var _groups:Dictionary={}
var _triangles:Array=[]
var _unit:=BoxMesh.new()
var _decorated:=0

func configure(city_node,world_node)->void:
	city=city_node
	world=world_node
	if city.has_meta("medieval_dressing"):return
	city.set_meta("medieval_dressing",true)
	_unit.size=Vector3.ONE
	for index in city._roofs.size():
		var roof:Node3D=city._roofs[index]
		var upper:Node3D=city._full_walls[index]
		var shell:Node3D=roof.get_parent()
		var id:String=str(shell.name)
		if not city._venues.has(id):continue
		var venue:Dictionary=city._venues[id]
		if roof.get_child_count()==0 or not roof.get_child(0) is MeshInstance3D:continue
		var roof_mesh:MeshInstance3D=roof.get_child(0)
		var bounds:AABB=roof_mesh.mesh.get_aabb()
		var half:=Vector2(float(venue.size[0]),float(venue.size[1]))*.5
		var eave:float=bounds.position.y
		var ridge:float=bounds.size.y
		var kind:String=str(venue.kind)
		var variation:int=absi(id.hash())%4
		var civic:bool=kind in ["temple","academy","town_hall","watch","library","bathhouse","clinic"]
		var roof_color:String=["#684b3f","#815441","#775445","#5b6c65"][variation]
		if civic:roof_color=["#465968","#536a68","#486373","#626b62"][variation]
		var roof_material:=ShaderMaterial.new()
		roof_material.shader=load("res://assets/visuals/roof_tiles.gdshader")
		roof_material.set_shader_parameter("base_color",Color(roof_color))
		roof_mesh.material_override=roof_material
		var plaster:String=["#c1b092","#c5b497","#aab39b","#c2a88c"][variation]
		_gable(roof,half,eave,ridge,plaster)
		_facade(upper,half,eave,plaster,variation)
		_back_wall(shell,half)
		_roof_details(roof,half,eave,ridge,variation)
		_porch(upper,half,eave,variation)
		if kind in ["watch","academy","temple","town_hall"]:
			_tower(roof,Vector3(half.x*.58,eave,-half.y*.48),kind,roof_color)
		if kind=="mill":_mill(roof,half,eave,ridge)
		if kind not in ["home","clinic","bathhouse","stable"]:
			_banner(upper,Vector3(-half.x+.9,eave+.7,half.y+.55),variation)
		_decorated+=1
	for id in city._venues:
		var venue:Dictionary=city._venues[id]
		if venue.kind in ["market","square"]:_public_square(venue)
		elif float(venue.center[0])<3800 and float(venue.center[2])<3950:
			_courtyard_props(venue)
	# Underlays sit below the existing street/floor overlays and exactly follow
	# the original terrain triangles. They join the civic buildings into a town.
	city._ground_patch(Vector2(3500,3705),Vector2(270,150),Color("#918775"),.025,"CivicForecourt")
	city._ground_patch(Vector2(3340,3700),Vector2(68,160),Color("#867e6b"),.026,"CraftQuarterYard")
	city._ground_patch(Vector2(3510,3555),Vector2(66,58),Color("#9d937b"),.027,"TownHallCourtyard")
	_flush()
	print("Medieval dressing: ",_decorated," framed buildings with merged cutaway details.")

func _mat(color:String)->StandardMaterial3D:
	if _materials.has(color):return _materials[color]
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color(color)
	material.roughness=.92
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	_materials[color]=material
	return material

func _box(parent:Node3D,position:Vector3,size:Vector3,color:String,basis:Basis=Basis.IDENTITY)->void:
	var key:String=str(parent.get_instance_id())+":"+color
	if not _groups.has(key):_groups[key]={"parent":parent,"color":color,"transforms":[]}
	_groups[key].transforms.append(Transform3D(basis*Basis.from_scale(size),position))

func _beam(parent:Node3D,a:Vector3,b:Vector3,width:float,color:String="#3e3025")->void:
	var delta:Vector3=b-a
	if delta.length()<.01:return
	_box(parent,(a+b)*.5,Vector3(width,delta.length(),width),color,Basis(Quaternion(Vector3.UP,delta.normalized())))

func _triangle(parent:Node3D,a:Vector3,b:Vector3,c:Vector3,color:String)->void:
	_triangles.append({"parent":parent,"points":[a,b,c],"color":color})

func _back_wall(parent:Node3D,half:Vector2)->void:
	var p:Vector3=parent.global_position
	var previous:=Vector3.ZERO
	for index in 9:
		var x:float=lerpf(-half.x,half.x,float(index)/8)
		var y:float=world.sample_height(p.x+x,p.z-half.y)-p.y
		var at:=Vector3(x,y,-half.y+.22)
		_box(parent,at+Vector3(0,1.75,0),Vector3(.22,3.5,.22),"#584432")
		if index>0:
			_beam(parent,previous+Vector3(0,.45,0),at+Vector3(0,.45,0),.25,"#584432")
			_beam(parent,previous+Vector3(0,3.4,0),at+Vector3(0,3.4,0),.22,"#584432")
		previous=at

func _gable(parent:Node3D,half:Vector2,eave:float,ridge:float,plaster:String)->void:
	for sign_z in [-1.0,1.0]:
		var z:float=sign_z*(half.y+.69)
		var a:=Vector3(-half.x-.58,eave+.02,z)
		var b:=Vector3(half.x+.58,eave+.02,z)
		var peak:=Vector3(0,eave+ridge-.02,z)
		_triangle(parent,a,b,peak,plaster)
		_beam(parent,a,peak,.35)
		_beam(parent,b,peak,.35)
		_beam(parent,a,b,.38)
		_beam(parent,Vector3(0,eave,z),peak,.32)
		var middle:float=eave+ridge*.42
		_beam(parent,Vector3(-half.x*.55,middle,z),Vector3(half.x*.55,middle,z),.27)
		for sx in [-1.0,1.0]:
			_beam(parent,Vector3(sx*half.x*.62,eave,z),Vector3(0,eave+ridge*.75,z),.26)
			_window(parent,Vector3(sx*half.x*.27,middle+.55,z+sign_z*.10),Vector2(1.7,1.55),0,false)

func _facade(parent:Node3D,half:Vector2,eave:float,plaster:String,variation:int)->void:
	var wood:String="#49392a"
	for side in [-1.0,1.0]:
		var x:float=side*(half.x+.24)
		var low:float=maxf(1.25,eave-3.1)
		for z:float in [-half.y*.75,-half.y*.25,half.y*.25,half.y*.75]:
			_beam(parent,Vector3(x,.9,z),Vector3(x,eave,z),.23,wood)
			_window(parent,Vector3(x,eave-1.7,z+1.7),Vector2(1.6,1.65),PI*.5,true)
			_beam(parent,Vector3(x,low,z-1.7),Vector3(x,eave-.35,z+1.7),.19,wood)
		_beam(parent,Vector3(x,1.2,-half.y),Vector3(x,1.2,half.y),.22,wood)
		_beam(parent,Vector3(x,eave-.1,-half.y-.6),Vector3(x,eave-.1,half.y+.6),.38,wood)
	for x:float in [-half.x+2.8,half.x-2.8]:
		_window(parent,Vector3(x,eave-1.65,half.y+.27),Vector2(1.8,1.7),0,true)
		_box(parent,Vector3(x,eave-2.75,half.y+.65),Vector3(2.3,.42,.7),"#654b35")
		_box(parent,Vector3(x,eave-2.48,half.y+.65),Vector3(1.95,.22,.50),["#607448","#8a6d63","#728252","#7c7970"][variation])
	# Long buildings sit on sloping terrain: frame the full exposed facade, not
	# only its top edge, and keep the existing 13 m central access opening clear.
	for side in [-1.0,1.0]:
		var center:Vector3=parent.get_parent().global_position
		for step in 3:
			var x:float=side*lerpf(6.7,half.x,float(step)/2)
			var low:float=world.sample_height(center.x+x,center.z+half.y)-center.y
			_beam(parent,Vector3(x,low+.15,half.y+.32),Vector3(x,eave,half.y+.32),.27)
		var midx:float=side*(half.x+6.7)*.5
		var ground:float=world.sample_height(center.x+midx,center.z+half.y)-center.y
		_window(parent,Vector3(midx,ground+2.25,half.y+.32),Vector2(2.1,1.8),0,true)
		_beam(parent,Vector3(side*6.7,ground+3.5,half.y+.34),Vector3(side*half.x,ground+3.5,half.y+.34),.23)
	# The front opening stays completely clear below the existing lintel.
	_box(parent,Vector3(0,eave-.30,half.y+.28),Vector3(13.0,.45,.45),wood)
	for x:float in [-6.35,6.35]:_box(parent,Vector3(x,1.55,half.y+.22),Vector3(.32,3.1,.45),wood)

func _window(parent:Node3D,at:Vector3,size:Vector2,angle:float,shutters:bool)->void:
	var basis:=Basis(Vector3.UP,angle)
	_box(parent,at,Vector3(size.x+.25,size.y+.25,.20),"#40372d",basis)
	_box(parent,at+basis*Vector3(0,0,.13),Vector3(size.x,size.y,.11),"#6c9293",basis)
	for offset in [Vector3(0,0,.23),Vector3(0,0,.24)]:
		var bar:=Vector3(.12,size.y,.12) if offset.z<.24 else Vector3(size.x,.12,.12)
		_box(parent,at+basis*offset,bar,"#d0b58a",basis)
	if shutters:
		for side in [-1.0,1.0]:
			_box(parent,at+basis*Vector3(side*(size.x*.5+.42),0,.08),Vector3(.58,size.y,.16),"#687c67",basis)

func _roof_details(parent:Node3D,half:Vector2,eave:float,ridge:float,variation:int)->void:
	_beam(parent,Vector3(0,eave+ridge+.10,-half.y-.85),Vector3(0,eave+ridge+.10,half.y+.85),.42,"#504236")
	for side in [-1.0,1.0]:
		_beam(parent,Vector3(side*(half.x+.65),eave,-half.y-.75),Vector3(side*(half.x+.65),eave,half.y+.75),.38)
	# A chimney penetrates the roof and follows its visibility as one group.
	var x:float=(-1.0 if variation%2==0 else 1.0)*half.x*.56
	var top:float=eave+ridge*.52+3.2
	_box(parent,Vector3(x,top-2.6,-half.y*.36),Vector3(1.45,5.2,1.65),"#8d8071")
	_box(parent,Vector3(x,top,-half.y*.36),Vector3(1.85,.42,2.05),"#5c544c")
	_box(parent,Vector3(x,top+.25,-half.y*.36),Vector3(1.08,.11,1.25),"#302e2a")
	# Shallow dormers break the wide roof plane without adding inaccessible rooms.
	for z:float in [-half.y*.43,half.y*.36]:
		var dx:float=half.x*.50
		var y:float=eave+ridge*.52
		var zrot:float=PI*.5
		_box(parent,Vector3(dx,y+.75,z),Vector3(2.1,1.65,3.1),"#b5a78d")
		_window(parent,Vector3(dx+1.1,y+.8,z),Vector2(1.55,1.2),zrot,false)
		_box(parent,Vector3(dx,y+1.75,z),Vector3(3.0,.25,3.6),"#4e5d58",Basis(Vector3.FORWARD,-.12))

func _porch(parent:Node3D,half:Vector2,eave:float,variation:int)->void:
	var height:float=maxf(3.05,eave-.25)
	var depth:=3.2
	for x:float in [-4.7,4.7]:
		_box(parent,Vector3(x,height*.5,half.y+depth),Vector3(.30,height,.30),"#4c3a29")
	_box(parent,Vector3(0,height,half.y+depth*.45),Vector3(10.2,.28,depth+1.2),["#7c5945","#4f6c70","#6d7a55","#795947"][variation],Basis(Vector3.RIGHT,.10))
	_beam(parent,Vector3(-4.8,height-.25,half.y+depth),Vector3(4.8,height-.25,half.y+depth),.28)
	for x:float in [-4.7,4.7]:
		_beam(parent,Vector3(x,height-1.2,half.y+depth),Vector3(x*.72,height-.30,half.y+depth),.20)

func _banner(parent:Node3D,at:Vector3,variation:int)->void:
	_box(parent,at+Vector3(.8,.2,0),Vector3(1.9,.16,.16),"#42372c")
	var color:String=["#8b4c3d","#3f6574","#626f40","#80604a"][variation]
	_box(parent,at+Vector3(1.4,-1.15,0),Vector3(1.1,2.5,.10),color)
	_box(parent,at+Vector3(1.4,-1.1,.075),Vector3(.62,.62,.08),"#dbba77",Basis(Vector3.FORWARD,PI*.25))

func _tower(parent:Node3D,at:Vector3,kind:String,roof_color:String)->void:
	var h:float=13.5 if kind in ["academy","town_hall"] else 10.0
	var w:float=5.8
	_box(parent,at+Vector3(0,h*.5,0),Vector3(w,h,w),"#a2a18d")
	for y:float in [1.5,h-1.6,h]:_box(parent,at+Vector3(0,y,0),Vector3(w+.45,.40,w+.45),"#5c5e52")
	for side in [-1.0,1.0]:
		_window(parent,at+Vector3(side*1.4,h-3.1,w*.5+.15),Vector2(.75,2.1),0,false)
	var a:=at+Vector3(-w*.64,h+.2,-w*.64)
	var b:=at+Vector3(w*.64,h+.2,-w*.64)
	var c:=at+Vector3(-w*.64,h+.2,w*.64)
	var d:=at+Vector3(w*.64,h+.2,w*.64)
	var top:=at+Vector3(0,h+6.1,0)
	for face in [[a,b,top],[b,d,top],[d,c,top],[c,a,top]]:_triangle(parent,face[0],face[1],face[2],roof_color)
	_box(parent,top+Vector3(0,1.1,0),Vector3(.18,2.3,.18),"#bfa26a")
	if kind=="town_hall":
		_box(parent,at+Vector3(0,h-2.9,w*.5+.35),Vector3(2.2,2.2,.14),"#d0bd87")
		_beam(parent,at+Vector3(0,h-2.9,w*.5+.48),at+Vector3(.75,h-2.9,w*.5+.48),.12)
		_beam(parent,at+Vector3(0,h-2.9,w*.5+.48),at+Vector3(0,h-2.1,w*.5+.48),.12)

func _mill(parent:Node3D,half:Vector2,eave:float,ridge:float)->void:
	var hub:=Vector3(0,eave+ridge*.48,half.y+1.4)
	for angle:float in [.45,.45+PI*.5]:
		var direction:=Vector3(sin(angle),cos(angle),0)
		_beam(parent,hub-direction*9,hub+direction*9,.38)
		for side in [-1.0,1.0]:
			_box(parent,hub+direction*side*5.5,Vector3(1.7,6.5,.18),"#c7ba95",Basis(Vector3.FORWARD,-angle))

func _public_square(venue:Dictionary)->void:
	var anchor:=Node3D.new()
	anchor.name="Dressing_"+str(venue.id)
	city.add_child(anchor)
	anchor.position=Vector3(float(venue.center[0]),float(venue.center[1]),float(venue.center[2]))
	if venue.kind=="market":
		for x:float in [-11,11]:
			for z:float in [-7,6]:
				var ground:float=world.sample_height(anchor.position.x+x,anchor.position.z+z)-anchor.position.y
				var base:=Vector3(x,ground,z)
				for px:float in [-3.6,3.6]:
					for pz:float in [-2.4,2.4]:_box(anchor,base+Vector3(px,1.9,pz),Vector3(.24,3.8,.24),"#5c4430")
				for stripe in 6:
					var color:String="#b6b08b" if stripe%2 else ("#6e8b87" if x<0 else "#a36a4e")
					_box(anchor,base+Vector3(-3.2+stripe*1.28,4.0,0),Vector3(1.29,.15,5.7),color,Basis(Vector3.RIGHT,.10))
				for i in 3:_crate(anchor,base+Vector3(-3.0+i*.85,.0,-3.4))
				_barrel(anchor,base+Vector3(3.8,0,-3.1))
	else:
		var half:=Vector2(float(venue.size[0]),float(venue.size[1]))*.5
		var center:=Vector2(anchor.position.x,anchor.position.z)
		# A low stone surround, canopy and banner embellish the existing well,
		# whose navigation footprint is retained. The free centre stays walkable.
		var well:=Vector3(-half.x*.60,0,0)
		well.y=world.sample_height(center.x+well.x,center.y)-anchor.position.y
		city._ground_patch(center+Vector2(well.x,0),Vector2(5,5),Color("#b8ad8d"),.11,"WellStoneSurround")
		for x:float in [-.68,.68]:
			_box(anchor,well+Vector3(x,2.35,-.20),Vector3(.16,4.7,.16),"#55402d")
		_box(anchor,well+Vector3(0,4.7,0),Vector3(2.0,.25,2.0),"#4e6b70",Basis(Vector3.RIGHT,.08))
		_banner(anchor,well+Vector3(-.3,5.2,0),0)
		for step in range(-1,2):
			for across in range(-1,2):
				var tint:=Color("#b4aa8e") if (step+across)%2==0 else Color("#857f6d")
				city._ground_patch(center+Vector2(step*2.7,across*2.7),Vector2(2.62,2.62),tint,.115,"SquareInlay")
		for sign_x in [-1.0,1.0]:
			for sign_z in [-1.0,1.0]:
				var local:=Vector3(sign_x*(half.x-3.5),0,sign_z*(half.y-3.5))
				local.y=world.sample_height(anchor.position.x+local.x,anchor.position.z+local.z)-anchor.position.y
				_box(anchor,local+Vector3(0,.35,0),Vector3(3.0,.7,3.0),"#8c8a72")
				world._model("nature-kit/tree_oak",anchor,local+Vector3(0,.65,0),Vector3.ONE*3.0,sign_x*.4)
				_banner(anchor,local+Vector3(2.1,3.8,0),1)

func _courtyard_props(venue:Dictionary)->void:
	var kind:String=str(venue.kind)
	if kind in ["farm","graveyard","mine","quarry","logging_camp","fishery"]:return
	var anchor:=Node3D.new()
	anchor.name="FacadeGoods_"+str(venue.id)
	city.add_child(anchor)
	anchor.position=Vector3(float(venue.center[0]),float(venue.center[1]),float(venue.center[2]))
	var half:=Vector2(float(venue.size[0]),float(venue.size[1]))*.5
	for side in [-1.0,1.0]:
		var at:=Vector3(side*(half.x-2),0,half.y+.70)
		at.y=world.sample_height(anchor.position.x+at.x,anchor.position.z+at.z)-anchor.position.y
		_box(anchor,at+Vector3(0,.30,0),Vector3(3.3,.60,.8),"#87765b")
		_box(anchor,at+Vector3(0,.65,0),Vector3(3.0,.25,.60),"#748651")
		for offset:float in [-1.1,-.55,.15,.8]:
			_box(anchor,at+Vector3(offset,.85,.05),Vector3(.28,.22,.30),"#d2ae6b" if side>0 else "#9e6962")
	if kind not in ["home","temple","academy","clinic","bathhouse","library","school"]:
		var at:=Vector3(-half.x+.8,0,half.y-1.9)
		at.y=world.sample_height(anchor.position.x+at.x,anchor.position.z+at.z)-anchor.position.y
		_crate(anchor,at)
		_crate(anchor,at+Vector3(1.0,0,0))
		_crate(anchor,at+Vector3(.45,1.1,0))

func _crate(parent:Node3D,at:Vector3)->void:
	_box(parent,at+Vector3(0,.55,0),Vector3(.82,1.1,.85),"#97744d")
	for y:float in [.12,.95]:_box(parent,at+Vector3(0,y,.46),Vector3(.92,.12,.1),"#54402d")
	_beam(parent,at+Vector3(-.35,.1,.47),at+Vector3(.35,1,.47),.10,"#b18f5e")

func _barrel(parent:Node3D,at:Vector3)->void:
	_box(parent,at+Vector3(0,.8,0),Vector3(1.15,1.6,1.15),"#896540",Basis(Vector3.UP,.2))
	for y:float in [.22,1.35]:_box(parent,at+Vector3(0,y,0),Vector3(1.24,.14,1.24),"#454c43",Basis(Vector3.UP,.2))

func _flush()->void:
	var parents:Dictionary={}
	for group:Dictionary in _groups.values():
		var key:int=group.parent.get_instance_id()
		if not parents.has(key):
			var surface:=SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			parents[key]={"node":group.parent,"surface":surface}
		var surface:SurfaceTool=parents[key].surface
		for transform:Transform3D in group.transforms:
			_cube(surface,transform,Color(group.color))
	for triangle:Dictionary in _triangles:
		var key:int=triangle.parent.get_instance_id()
		if not parents.has(key):
			var surface:=SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			parents[key]={"node":triangle.parent,"surface":surface}
		var surface:SurfaceTool=parents[key].surface
		var points:Array=triangle.points
		var normal:Vector3=(points[1]-points[0]).cross(points[2]-points[0]).normalized()
		for point:Vector3 in points:
			surface.set_color(Color(triangle.color))
			surface.set_normal(normal)
			surface.add_vertex(point)
	var material:=StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.vertex_color_is_srgb=false
	material.roughness=.92
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	for entry:Dictionary in parents.values():
		var instance:=MeshInstance3D.new()
		instance.name="MedievalDetail"
		instance.mesh=entry.surface.commit()
		instance.material_override=material
		instance.visibility_range_end=850
		instance.visibility_range_end_margin=80
		entry.node.add_child(instance)

func _cube(surface:SurfaceTool,transform:Transform3D,color:Color)->void:
	var corners:Array[Vector3]=[
		Vector3(-.5,-.5,-.5),Vector3(.5,-.5,-.5),Vector3(.5,.5,-.5),Vector3(-.5,.5,-.5),
		Vector3(-.5,-.5,.5),Vector3(.5,-.5,.5),Vector3(.5,.5,.5),Vector3(-.5,.5,.5)]
	var faces:Array=[[0,3,2,1],[4,5,6,7],[0,4,7,3],[1,2,6,5],[3,7,6,2],[0,1,5,4]]
	var normals:Array[Vector3]=[Vector3.BACK*-1,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT,Vector3.UP,Vector3.DOWN]
	var normal_basis:Basis=transform.basis.inverse().transposed()
	for i in range(6):
		var face:Array=faces[i]
		for index in [0,1,2,0,2,3]:
			surface.set_color(color)
			surface.set_normal((normal_basis*normals[i]).normalized())
			surface.add_vertex(transform*corners[face[index]])
