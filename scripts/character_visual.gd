extends RefCounted
## Original integration of three CC0 Quaternius packs. All characters are clothed.
const ROOT:="res://assets/actors/quaternius/"
const CLIPS:={"Idle":"Idle","Walking_A":"Walk","Running_A":"Jog_Fwd",
	"1H_Melee_Attack_Slice_Diagonal":"Sword_Attack","1H_Melee_Attack_Chop":"Sword_Attack",
	"1H_Melee_Attack_Stab":"Punch_Jab","Hit_A":"Hit_Chest","Death_A":"Death01",
	"Interact":"Interact","PickUp":"PickUp_Table","Use_Item":"Idle_Talking",
	"Sit_Floor_Down":"Sitting_Enter","Sit_Floor_Idle":"Sitting_Idle","Cheer":"Dance",
	"Sit_Chair_Idle":"Sitting_Idle","Lie_Idle":"Death01","Unarmed_Melee_Attack_Punch_A":"Punch_Jab"}

static func key(role:String,profile:Dictionary)->String:
	var sex:String="Female" if str(profile.get("gender","female" if role=="sister" else "male"))=="female" else "Male"
	var outfit:String="Ranger" if str(profile.get("outfit","wanderer")) in ["wanderer","ranger","guard"] else "Peasant"
	var hair:String=str(profile.get("hair","long" if sex=="Female" else "short"))
	return sex+":"+outfit+":"+hair

static func build(role:String,profile:Dictionary)->Node3D:
	var identity:String=key(role,profile)
	var sex:String=identity.get_slice(":",0)
	var outfit:String=identity.get_slice(":",1)
	var root:Node3D=load(ROOT+sex+"_"+outfit+".gltf").instantiate()
	root.name="HumanVisual"
	var skeleton:Skeleton3D=root.find_children("*","Skeleton3D",true,false)[0]
	var body:Node3D=load(ROOT+"Superhero_"+sex+"_FullBody.gltf").instantiate()
	var source_skeleton:Skeleton3D=body.find_children("*","Skeleton3D",true,false)[0]
	var head_rest:Transform3D=source_skeleton.get_bone_global_rest(source_skeleton.find_bone("Head"))
	for node:MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
		var mesh:=ArrayMesh.new()
		for surface in node.mesh.get_surface_count():
			var arrays:Array=node.mesh.surface_get_arrays(surface)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var clipped:=PackedInt32Array()
			for i in range(0,indices.size(),3):
				if vertices[indices[i]].y>1.515 and vertices[indices[i+1]].y>1.515 and vertices[indices[i+2]].y>1.515:
					clipped.append_array(PackedInt32Array([indices[i],indices[i+1],indices[i+2]]))
			if clipped.is_empty():continue
			arrays[Mesh.ARRAY_INDEX]=clipped
			for channel in [Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1,Mesh.ARRAY_CUSTOM2,Mesh.ARRAY_CUSTOM3]:arrays[channel]=null
			var flags:int=Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if arrays[Mesh.ARRAY_BONES].size()==vertices.size()*8 else 0
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},flags)
			mesh.surface_set_material(mesh.get_surface_count()-1,node.mesh.surface_get_material(surface))
		if mesh.get_surface_count()==0:continue
		var head:=MeshInstance3D.new()
		head.name="Face_"+str(node.name)
		head.mesh=mesh
		head.skin=node.skin
		head.skeleton=NodePath("..")
		skeleton.add_child(head)
	body.free()
	var hair_id:String={"short":"Hair_SimpleParted","buzzed":"Hair_Buzzed","long":"Hair_Long","buns":"Hair_Buns"}.get(identity.get_slice(":",2),"Hair_Long" if sex=="Female" else "Hair_SimpleParted")
	var attachment:=BoneAttachment3D.new()
	attachment.name="Hairstyle"
	attachment.bone_name="Head"
	skeleton.add_child(attachment)
	var hair:Node3D=load(ROOT+"hair/"+hair_id+".gltf").instantiate()
	hair.transform=head_rest.affine_inverse()*hair.transform
	attachment.add_child(hair)
	for node:MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		if "Hood" in str(node.name) or "Pauldron" in str(node.name):node.visible=false
		for surface in node.mesh.get_surface_count():
			var original:Material=node.mesh.surface_get_material(surface)
			if original is StandardMaterial3D:
				var mat:StandardMaterial3D=original.duplicate()
				mat.roughness=.82
				mat.metallic=0
				mat.metallic_specular=.25
				if "Hair" in original.resource_name:mat.albedo_color=Color("#694438") if sex=="Male" else Color("#7c4934")
				if mat.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:
					mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					mat.alpha_scissor_threshold=.35
				node.set_surface_override_material(surface,mat)
	_add_socket(skeleton,"handslot.r","hand_r",Transform3D(Basis(Vector3.RIGHT,PI*.5),Vector3(0,.075,0)))
	_add_socket(skeleton,"chest","spine_03",Transform3D.IDENTITY)
	_animations(root,skeleton)
	_own(root,root)
	return root

static func _add_socket(sk:Skeleton3D,name:String,parent:String,rest:Transform3D)->void:
	if sk.find_bone(name)>=0:return
	sk.add_bone(name)
	var index:int=sk.find_bone(name)
	sk.set_bone_parent(index,sk.find_bone(parent))
	sk.set_bone_rest(index,rest)
	sk.set_bone_pose_position(index,rest.origin)
	sk.set_bone_pose_rotation(index,rest.basis.get_rotation_quaternion())

static func _animations(root:Node3D,target:Skeleton3D)->void:
	var source:Node3D=load(ROOT+"UAL1_Standard.glb").instantiate()
	var source_sk:Skeleton3D=source.find_children("*","Skeleton3D",true,false)[0]
	var source_player:AnimationPlayer=source.find_children("*","AnimationPlayer",true,false)[0]
	var player:=AnimationPlayer.new()
	player.name="AnimationPlayer"
	root.add_child(player)
	var library:=AnimationLibrary.new()
	for alias:String in CLIPS:
		var animation:Animation=source_player.get_animation(CLIPS[alias]).duplicate(true)
		for track in animation.get_track_count():
			var path:NodePath=animation.track_get_path(track)
			if path.get_subname_count()==0:continue
			var bone:String=path.get_subname(0)
			var a:int=source_sk.find_bone(bone)
			var b:int=target.find_bone(bone)
			if a<0 or b<0:continue
			var src_rest:Transform3D=source_sk.get_bone_rest(a)
			var dst_rest:Transform3D=target.get_bone_rest(b)
			var correction:Quaternion=dst_rest.basis.get_rotation_quaternion()*src_rest.basis.get_rotation_quaternion().inverse()
			for frame in animation.track_get_key_count(track):
				if animation.track_get_type(track)==Animation.TYPE_ROTATION_3D:
					animation.track_set_key_value(track,frame,correction*animation.track_get_key_value(track,frame))
				elif animation.track_get_type(track)==Animation.TYPE_POSITION_3D:
					var point:Vector3=animation.track_get_key_value(track,frame)
					animation.track_set_key_value(track,frame,dst_rest.origin+(point-src_rest.origin))
			animation.track_set_path(track,NodePath(str(root.get_path_to(target))+":"+bone))
		if alias=="Lie_Idle":
			for track in animation.get_track_count():
				var value=animation.track_get_key_value(track,animation.track_get_key_count(track)-1)
				while animation.track_get_key_count(track)>0:animation.track_remove_key(track,0)
				animation.track_insert_key(track,0,value)
			animation.length=1.0
			animation.loop_mode=Animation.LOOP_LINEAR
		if alias in ["Idle","Walking_A","Running_A","Sit_Floor_Idle","Sit_Chair_Idle"]:animation.loop_mode=Animation.LOOP_LINEAR
		library.add_animation(alias,animation)
	player.add_animation_library("",library)
	source.free()

static func _own(node:Node,root:Node)->void:
	if node!=root:node.owner=root
	for child in node.get_children():_own(child,root)
