extends RefCounted
class_name VariationEngine

# Utility functions for procedural pattern mutations.
static func clone_patterns(patterns: Dictionary) -> Dictionary:
	var copy: Dictionary = {}
	for track_name in patterns.keys():
		copy[track_name] = (patterns[track_name] as Array).duplicate()
	return copy

static func apply_controlled_variation(patterns: Dictionary, rng: RandomNumberGenerator, steps_per_loop: int) -> Dictionary:
	var mutated = clone_patterns(patterns)
	if mutated.is_empty():
		return {"patterns": mutated, "description": "Sin variacion"}

	var track_names = mutated.keys()
	var selected_track: String = String(track_names[rng.randi_range(0, track_names.size() - 1)])
	var pattern: Array = mutated[selected_track]
	if pattern.is_empty():
		return {"patterns": mutated, "description": "Sin variacion"}

	var actions = [
		"invert",
		"shift_right",
		"duplicate_hits",
		"add_silence",
		"final_fill",
	]
	var action: String = String(actions[rng.randi_range(0, actions.size() - 1)])

	match action:
		"invert":
			for i in range(pattern.size()):
				pattern[i] = 0 if int(pattern[i]) == 1 else 1
		"shift_right":
			pattern = _shift_pattern(pattern, 1)
		"duplicate_hits":
			for i in range(pattern.size()):
				if int(pattern[i]) == 1 and rng.randf() < 0.25:
					pattern[(i + 1) % pattern.size()] = 1
		"add_silence":
			for i in range(pattern.size()):
				if int(pattern[i]) == 1 and rng.randf() < 0.2:
					pattern[i] = 0
		"final_fill":
			var start: int = max(0, steps_per_loop - 4)
			var end: int = min(steps_per_loop, pattern.size())
			for i in range(start, end):
				if rng.randf() < 0.55:
					pattern[i] = 1

	mutated[selected_track] = pattern
	return {
		"patterns": mutated,
		"description": "Variacion %s en %s" % [action, selected_track],
	}

static func _shift_pattern(pattern: Array, amount: int) -> Array:
	var shifted: Array = []
	shifted.resize(pattern.size())
	for i in range(pattern.size()):
		var target = (i + amount) % pattern.size()
		shifted[target] = int(pattern[i])
	return shifted
