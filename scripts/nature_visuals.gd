extends RefCounted
## CC0 Quaternius meshes, normalized to the existing placement dimensions.
## Only visuals are replaced: heightfield, obstacle radii and interactable IDs stay intact.
const ROOT:="res://assets/environment/quaternius_nature/"
const REPLACEMENTS:={
	"tree_oak":"CommonTree_1", "tree_detailed":"CommonTree_3", "tree_small":"CommonTree_4",
	"tree_pineTallA_detailed":"Pine_2", "tree_pineTallB_detailed":"Pine_4",
	"plant_bushDetailed":"Bush_Common_Flowers", "grass_large":"Grass_Common_Short",
	"grass_leafs":"Fern_1", "flower_yellowA":"Flower_3_Group", "flower_purpleA":"Flower_4_Group",
	"rock_largeA":"Rock_Medium_1", "rock_largeC":"Rock_Medium_3"
}
static func instantiate(asset:String,original:PackedScene)->Node3D:
	if not asset.begins_with("nature-kit/"):return original.instantiate()
	var key:String=asset.get_file()
	if not REPLACEMENTS.has(key):return original.instantiate()
	var fresh:PackedScene=load(ROOT+str(REPLACEMENTS[key])+".gltf")
	if fresh==null:return original.instantiate()
	var old:Node3D=original.instantiate()
	var source:Node3D=fresh.instantiate()
	_materials(source)
	var old_box:AABB=_bounds(old)
	var new_box:AABB=_bounds(source)
	old.free()
	var factor:float=old_box.size.y/maxf(.01,new_box.size.y)
	source.scale*=factor
	source.position.y=old_box.position.y-new_box.position.y*factor
	var wrapper:=Node3D.new()
	wrapper.name="TexturedNature"
	wrapper.add_child(source)
	return wrapper

static func _materials(node:Node)->void:
	if node is MeshInstance3D and node.mesh:
		var mesh:Mesh=node.mesh.duplicate()
		for surface in mesh.get_surface_count():
			var original:Material=mesh.surface_get_material(surface)
			if original is StandardMaterial3D:
				if "Leaves_" in original.resource_name:
					var leaf:=ShaderMaterial.new()
					leaf.shader=load("res://assets/visuals/leaves.gdshader")
					leaf.set_shader_parameter("leaf_texture",original.albedo_texture)
					mesh.surface_set_material(surface,leaf)
				else:
					var mat:StandardMaterial3D=original.duplicate()
					mat.metallic_specular=.15
					mat.roughness=.95
					if "Bark" in original.resource_name:mat.albedo_color=Color("#bfa894")
					mesh.surface_set_material(surface,mat)
		node.mesh=mesh
	for child in node.get_children():_materials(child)

static func _own(node:Node,owner_node:Node)->void:
	node.owner=owner_node
	for child in node.get_children():_own(child,owner_node)

static func _bounds(node:Node3D)->AABB:
	var pieces:Array[AABB]=[]
	_collect(node,Transform3D.IDENTITY,pieces)
	var result:AABB=pieces[0] if not pieces.is_empty() else AABB(Vector3.ZERO,Vector3.ONE)
	for item:AABB in pieces:result=result.merge(item)
	return result

static func _collect(node:Node,transform:Transform3D,pieces:Array[AABB])->void:
	var current:Transform3D=transform*node.transform if node is Node3D else transform
	if node is MeshInstance3D and node.mesh:pieces.append(current*node.mesh.get_aabb())
	for child in node.get_children():_collect(child,current,pieces)
