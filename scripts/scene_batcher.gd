extends RefCounted
## Static presentation optimization only: object IDs, picking, reservations and
## navigation remain on the original scene nodes. Roofs stay independently movable.
static func bake(root:Node3D,excluded:Array=[])->Dictionary:
	var unit_box:=BoxMesh.new()
	unit_box.size=Vector3.ONE
	var groups:Dictionary={}
	var records:Dictionary=root.get("_records") if root.get("_records") is Dictionary else {}
	for item in root.find_children("*","MeshInstance3D",true,false):
		var node:MeshInstance3D=item
		if node.mesh==null or not node.visible or node.skin!=null: continue
		var ancestor:Node=node
		var skip:=false
		var furniture:=false
		while ancestor and ancestor!=root:
			if excluded.has(ancestor): skip=true; break
			if records.has(str(ancestor.name)) and str(records[str(ancestor.name)].get("kind","")) in ["furniture","workplace"]: furniture=true
			ancestor=ancestor.get_parent()
		if skip: continue
		var mesh:Mesh=node.mesh
		var transform:Transform3D=node.global_transform
		var geometry_key:String=str(mesh.get_rid().get_id())
		if mesh is BoxMesh:
			transform=transform*Transform3D(Basis.from_scale(mesh.size),Vector3.ZERO)
			mesh=unit_box
			geometry_key="box"
		var material:Material=node.material_override
		if material==null and node.mesh is PrimitiveMesh: material=node.mesh.material
		var cell:=Vector2i(floori(transform.origin.x/128),floori(transform.origin.z/128))
		var key:String=geometry_key+":"+str(material.get_rid().get_id() if material else 0)+":"+str(cell)+":"+str(node.cast_shadow)+":"+str(furniture)
		if not groups.has(key): groups[key]={"mesh":mesh,"material":material,"nodes":[],"transforms":[],"origin":Vector3(cell.x*128+64,transform.origin.y,cell.y*128+64),"shadows":node.cast_shadow,"furniture":furniture}
		if furniture:
			node.visibility_range_end=180
			node.visibility_range_end_margin=25
		groups[key].nodes.append(node)
		groups[key].transforms.append(transform)
	var hidden:=0
	var batches:=0
	for group:Dictionary in groups.values():
		if group.nodes.size()<3: continue
		var multi:=MultiMesh.new()
		multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.mesh=group.mesh
		multi.instance_count=group.nodes.size()
		for index in group.transforms.size():
			var transform:Transform3D=group.transforms[index]
			transform.origin-=Vector3(group.origin)
			multi.set_instance_transform(index,transform)
		var instance:=MultiMeshInstance3D.new()
		instance.name="Статическая_геометрия_"+str(batches)
		instance.multimesh=multi
		instance.material_override=group.material
		instance.cast_shadow=group.shadows
		root.add_child(instance)
		instance.global_position=group.origin
		instance.visibility_range_end=260 if group.furniture else 950
		instance.visibility_range_end_margin=30 if group.furniture else 100
		for original:MeshInstance3D in group.nodes: original.hide(); hidden+=1
		batches+=1
	print("City batching: ",hidden," meshes in ",batches," draw groups; roofs remain independent.")
	return {"original_meshes":hidden,"batches":batches}
