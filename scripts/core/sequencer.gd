extends Node
class_name Sequencer

# Sequencer pipeline:
# base pattern -> upgrades -> optional procedural variation -> per-step trigger.
signal step_processed(step_index: int, loop_index: int)
signal patterns_rebuilt(effective_patterns: Dictionary, variation_description: String)
signal base_pattern_changed(track_name: String, pattern: Array)

@export var steps_per_loop: int = 16
@export var auto_variation_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var auto_variation_chance: float = 0.35

var layers: Dictionary = {}
var track_to_layer: Dictionary = {}
var base_patterns: Dictionary = {}
var effective_patterns: Dictionary = {}
var last_variation_description: String = "Sin variacion"

var _upgrade_system: UpgradeSystem
var _rng = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func configure(
		layer_map: Dictionary,
		track_layer_map: Dictionary,
		initial_patterns: Dictionary,
		upgrade_system: UpgradeSystem,
		loop_steps: int
	) -> void:
	layers = layer_map
	track_to_layer = track_layer_map
	steps_per_loop = loop_steps
	_upgrade_system = upgrade_system

	base_patterns.clear()
	for track_name in initial_patterns.keys():
		base_patterns[track_name] = (initial_patterns[track_name] as Array).duplicate()

	effective_patterns = VariationEngine.clone_patterns(base_patterns)

func process_step(step_index: int, loop_index: int) -> void:
	if effective_patterns.is_empty() or step_index == 0:
		rebuild_now(loop_index)

	for track_name in effective_patterns.keys():
		var pattern: Array = effective_patterns[track_name]
		if step_index >= pattern.size() or int(pattern[step_index]) == 0:
			continue
		var layer_id: String = String(track_to_layer.get(track_name, ""))
		if not layers.has(layer_id):
			continue
		var layer: InstrumentLayer = layers[layer_id]
		if layer.is_active:
			layer.trigger_track(track_name, step_index)

	emit_signal("step_processed", step_index, loop_index)

func rebuild_now(loop_index: int) -> void:
	_rebuild_effective_patterns(loop_index)

func get_track_names() -> Array[String]:
	var names: Array[String] = []
	for track_name in base_patterns.keys():
		names.append(track_name)
	names.sort()
	return names

func get_pattern(track_name: String, use_effective: bool = false) -> Array:
	var source = effective_patterns if use_effective else base_patterns
	if not source.has(track_name):
		return []
	return (source[track_name] as Array).duplicate()

func get_base_patterns() -> Dictionary:
	return VariationEngine.clone_patterns(base_patterns)

func get_effective_patterns() -> Dictionary:
	return VariationEngine.clone_patterns(effective_patterns)

func get_active_effective_patterns() -> Dictionary:
	var filtered: Dictionary = {}
	for track_name in effective_patterns.keys():
		var layer_id: String = String(track_to_layer.get(track_name, ""))
		if not layers.has(layer_id):
			continue
		var layer: InstrumentLayer = layers[layer_id]
		if layer.is_active:
			filtered[track_name] = (effective_patterns[track_name] as Array).duplicate()
	return filtered

func load_base_patterns(patterns: Dictionary, emit_change: bool = true) -> void:
	for track_name in patterns.keys():
		if not base_patterns.has(track_name):
			continue
		base_patterns[track_name] = (patterns[track_name] as Array).duplicate()
		if emit_change:
			emit_signal("base_pattern_changed", track_name, (base_patterns[track_name] as Array).duplicate())

func set_step(track_name: String, step_index: int, is_on: bool) -> void:
	if not base_patterns.has(track_name):
		return
	var pattern: Array = base_patterns[track_name]
	if step_index < 0 or step_index >= pattern.size():
		return
	pattern[step_index] = 1 if is_on else 0
	emit_signal("base_pattern_changed", track_name, pattern.duplicate())

func toggle_step(track_name: String, step_index: int) -> void:
	if not base_patterns.has(track_name):
		return
	var pattern: Array = base_patterns[track_name]
	if step_index < 0 or step_index >= pattern.size():
		return
	pattern[step_index] = 0 if int(pattern[step_index]) == 1 else 1
	emit_signal("base_pattern_changed", track_name, pattern.duplicate())

func set_pattern(track_name: String, pattern: Array) -> void:
	if not base_patterns.has(track_name):
		return
	base_patterns[track_name] = pattern.duplicate()
	emit_signal("base_pattern_changed", track_name, pattern.duplicate())

func randomize_base_patterns() -> void:
	var density_targets = {
		"kick": 0.22,
		"snare": 0.18,
		"hat": 0.75,
		"bass": 0.28,
		"melody": 0.24,
		"fx": 0.14,
	}

	for track_name in base_patterns.keys():
		var pattern: Array = base_patterns[track_name]
		var target = float(density_targets.get(track_name, 0.25))
		for i in range(pattern.size()):
			pattern[i] = 1 if _rng.randf() < target else 0
		if not pattern.has(1):
			pattern[_rng.randi_range(0, pattern.size() - 1)] = 1
		emit_signal("base_pattern_changed", track_name, pattern.duplicate())

func apply_variation_to_base() -> String:
	var result = VariationEngine.apply_controlled_variation(base_patterns, _rng, steps_per_loop)
	base_patterns = result.get("patterns", base_patterns)
	for track_name in base_patterns.keys():
		emit_signal("base_pattern_changed", track_name, (base_patterns[track_name] as Array).duplicate())
	return String(result.get("description", "Sin variacion"))

func _rebuild_effective_patterns(loop_index: int) -> void:
	# Rebuild once per loop so runtime toggles stay stable while still supporting mutation.
	var current = VariationEngine.clone_patterns(base_patterns)
	if _upgrade_system != null:
		current = _upgrade_system.apply_upgrades(current, loop_index)

	last_variation_description = "Sin variacion"
	if auto_variation_enabled and _rng.randf() < auto_variation_chance:
		var variation = VariationEngine.apply_controlled_variation(current, _rng, steps_per_loop)
		current = variation.get("patterns", current)
		last_variation_description = String(variation.get("description", "Sin variacion"))

	effective_patterns = current
	emit_signal("patterns_rebuilt", get_effective_patterns(), last_variation_description)
