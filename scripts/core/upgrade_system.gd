extends Node
class_name UpgradeSystem

# Runtime modifiers that can be combined during a run.
signal upgrades_changed

var _upgrade_defs: Dictionary = {
	"swing_mode": {
		"name": "Swing Mode",
		"description": "Desplaza golpes off-beat para una sensacion de swing.",
		"enabled": false,
	},
	"double_kick": {
		"name": "Double Kick",
		"description": "Duplica golpes de kick al paso siguiente.",
		"enabled": false,
	},
	"dense_hats": {
		"name": "Dense Hats",
		"description": "Agrega hi-hats adicionales en subdivisiones.",
		"enabled": false,
	},
	"bass_drive": {
		"name": "Bass Drive",
		"description": "Activa bajo cada vez que hay kick.",
		"enabled": false,
	},
	"echo_melody": {
		"name": "Echo Melody",
		"description": "Replica notas de melodia dos pasos despues.",
		"enabled": false,
	},
	"random_fill": {
		"name": "Random Fill",
		"description": "Agrega fill aleatorio al final del loop.",
		"enabled": false,
	},
}

func get_upgrade_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in _upgrade_defs.keys():
		ids.append(id)
	ids.sort()
	return ids

func get_upgrade_definitions() -> Dictionary:
	return _upgrade_defs.duplicate(true)

func set_upgrade_enabled(upgrade_id: String, enabled: bool) -> void:
	if not _upgrade_defs.has(upgrade_id):
		return
	_upgrade_defs[upgrade_id]["enabled"] = enabled
	emit_signal("upgrades_changed")

func toggle_upgrade(upgrade_id: String) -> void:
	if not _upgrade_defs.has(upgrade_id):
		return
	var enabled = not bool(_upgrade_defs[upgrade_id].get("enabled", false))
	set_upgrade_enabled(upgrade_id, enabled)

func is_upgrade_enabled(upgrade_id: String) -> bool:
	if not _upgrade_defs.has(upgrade_id):
		return false
	return bool(_upgrade_defs[upgrade_id].get("enabled", false))

func get_enabled_map() -> Dictionary:
	var enabled_map: Dictionary = {}
	for id in _upgrade_defs.keys():
		enabled_map[id] = bool(_upgrade_defs[id].get("enabled", false))
	return enabled_map

func disable_all() -> void:
	for id in _upgrade_defs.keys():
		_upgrade_defs[id]["enabled"] = false
	emit_signal("upgrades_changed")

func load_enabled_map(enabled_map: Dictionary, emit_change: bool = true) -> void:
	var changed = false
	for id in _upgrade_defs.keys():
		if not enabled_map.has(id):
			continue
		var enabled = bool(enabled_map[id])
		if bool(_upgrade_defs[id].get("enabled", false)) != enabled:
			_upgrade_defs[id]["enabled"] = enabled
			changed = true
	if changed and emit_change:
		emit_signal("upgrades_changed")

func apply_upgrades(patterns: Dictionary, loop_index: int) -> Dictionary:
	var modified = VariationEngine.clone_patterns(patterns)
	var rng = RandomNumberGenerator.new()
	rng.seed = hash("upgrade_%d" % loop_index)

	# Deterministic ordering keeps debug easier.
	var ordered_ids = get_upgrade_ids()
	for upgrade_id in ordered_ids:
		if not is_upgrade_enabled(upgrade_id):
			continue
		match upgrade_id:
			"swing_mode":
				_apply_swing_mode(modified)
			"double_kick":
				_apply_double_kick(modified)
			"dense_hats":
				_apply_dense_hats(modified)
			"bass_drive":
				_apply_bass_drive(modified)
			"echo_melody":
				_apply_echo_melody(modified)
			"random_fill":
				_apply_random_fill(modified, rng)

	return modified

func _apply_swing_mode(patterns: Dictionary) -> void:
	for track_name in ["hat", "melody"]:
		if not patterns.has(track_name):
			continue
		var original: Array = (patterns[track_name] as Array).duplicate()
		for i in range(original.size()):
			if int(original[i]) != 1:
				continue
			if i % 4 == 2:
				var target = (i + 1) % original.size()
				if int(patterns[track_name][target]) == 0:
					patterns[track_name][i] = 0
					patterns[track_name][target] = 1

func _apply_double_kick(patterns: Dictionary) -> void:
	if not patterns.has("kick"):
		return
	var kick: Array = patterns["kick"]
	for i in range(kick.size()):
		if int(kick[i]) == 1:
			kick[(i + 1) % kick.size()] = 1

func _apply_dense_hats(patterns: Dictionary) -> void:
	if not patterns.has("hat"):
		return
	var hat: Array = patterns["hat"]
	for i in range(hat.size()):
		if i % 2 == 1:
			hat[i] = 1

func _apply_bass_drive(patterns: Dictionary) -> void:
	if not patterns.has("kick") or not patterns.has("bass"):
		return
	var kick: Array = patterns["kick"]
	var bass: Array = patterns["bass"]
	for i in range(min(kick.size(), bass.size())):
		if int(kick[i]) == 1:
			bass[i] = 1

func _apply_echo_melody(patterns: Dictionary) -> void:
	if not patterns.has("melody"):
		return
	var melody: Array = patterns["melody"]
	var original: Array = melody.duplicate()
	for i in range(original.size()):
		if int(original[i]) == 1:
			melody[(i + 2) % melody.size()] = 1

func _apply_random_fill(patterns: Dictionary, rng: RandomNumberGenerator) -> void:
	var candidates = ["snare", "hat", "fx"]
	for track_name in candidates:
		if not patterns.has(track_name):
			continue
		var pattern: Array = patterns[track_name]
		var start: int = max(0, pattern.size() - 4)
		for i in range(start, pattern.size()):
			if rng.randf() < 0.45:
				pattern[i] = 1
