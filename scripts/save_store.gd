extends RefCounted

const DIRECTORY := "user://saves/"
const AUTO_COUNT := 6

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))

func allowed(id: String) -> bool:
	return id in ["manual_1", "manual_2", "manual_3", "realtime", "auto_0", "auto_1", "auto_2", "auto_3", "auto_4", "auto_5"]

func write_slot(id: String, data: Dictionary) -> Error:
	if not allowed(id):
		return ERR_INVALID_PARAMETER
	var record := data.duplicate(true)
	record["saved_at"] = Time.get_datetime_string_from_system(false, true)
	record["save_kind"] = id
	var path := DIRECTORY + id + ".json"
	var pending := path + ".tmp"
	var file := FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(record, "\t"))
	file.flush()
	var err := file.get_error()
	file.close()
	if err != OK:
		return err
	# Keep the previous successful revision until the new file has been decoded.
	var checked = JSON.parse_string(FileAccess.get_file_as_string(pending))
	if not checked is Dictionary or int(checked.get("version", 0)) != 2:
		return ERR_FILE_CORRUPT
	if FileAccess.file_exists(path):
		err = DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak"))
		if err != OK:
			return err
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(pending), ProjectSettings.globalize_path(path))

func read_slot(id: String, validator: Callable = Callable()) -> Dictionary:
	if not allowed(id):
		return {}
	var path := DIRECTORY + id + ".json"
	for filename in [path, path + ".bak"]:
		if FileAccess.file_exists(filename):
			var data = JSON.parse_string(FileAccess.get_file_as_string(filename))
			if data is Dictionary and int(data.get("version", 0)) in [1, 2]:
				if not validator.is_valid() or validator.call(data):
					return data
	return {}

func list_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in ["manual_1", "manual_2", "manual_3", "realtime", "auto_0", "auto_1", "auto_2", "auto_3", "auto_4", "auto_5"]:
		var saved := read_slot(id)
		var label := "Текущее состояние"
		var kind := "realtime"
		if id.begins_with("manual"):
			label = "Ручное сохранение " + id.get_slice("_", 1)
			kind = "manual"
		elif id.begins_with("auto"):
			label = "Автосохранение " + str(int(id.get_slice("_", 1)) + 1)
			kind = "auto"
		result.append({"id": id, "label": label, "kind": kind, "exists": not saved.is_empty(), "date": str(saved.get("saved_at", "Пустая ячейка"))})
	return result
