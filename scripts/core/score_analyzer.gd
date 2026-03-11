extends Node
class_name ScoreAnalyzer

# Computes musical metrics used by battles and UI feedback.
func analyze(patterns: Dictionary, steps_per_loop: int, upgrades_enabled: Dictionary = {}) -> Dictionary:
	var metrics = {
		"density": 0.0,
		"syncopation": 0.0,
		"groove": 0.0,
		"variety": 0.0,
		"energy": 0.0,
		"complexity": 0.0,
		"score": 0,
		"total_hits": 0,
		"track_hits": {},
		"explanation": "",
	}
	if patterns.is_empty():
		metrics["explanation"] = "No hay patrones activos."
		return metrics

	var track_hits: Dictionary = {}
	var total_hits = 0
	var offbeat_hits = 0

	for track_name in patterns.keys():
		var pattern: Array = patterns[track_name]
		var hits = 0
		for step in range(min(steps_per_loop, pattern.size())):
			if int(pattern[step]) == 1:
				hits += 1
				total_hits += 1
				if step % 4 != 0:
					offbeat_hits += 1
		track_hits[track_name] = hits

	var track_count: int = max(1, patterns.size())
	var max_hits: float = float(track_count * steps_per_loop)
	var density_denominator: float = max_hits if max_hits > 1.0 else 1.0
	var syncopation_denominator: float = float(total_hits) if total_hits > 0 else 1.0
	var density: float = float(total_hits) / density_denominator
	var syncopation: float = float(offbeat_hits) / syncopation_denominator
	var groove: float = _compute_groove(patterns, steps_per_loop)
	var variety: float = _compute_variety(patterns, steps_per_loop)
	var energy: float = _compute_energy(track_hits, steps_per_loop)
	var complexity: float = float(clamp(density * 0.4 + syncopation * 0.3 + variety * 0.3, 0.0, 1.0))

	var base_score = int(round((density * 0.2 + syncopation * 0.2 + groove * 0.25 + variety * 0.15 + energy * 0.2) * 100.0))
	var enabled_upgrades = 0
	for upgrade_id in upgrades_enabled.keys():
		if bool(upgrades_enabled[upgrade_id]):
			enabled_upgrades += 1
	var build_bonus: int = min(10, enabled_upgrades * 2)

	metrics["density"] = density
	metrics["syncopation"] = syncopation
	metrics["groove"] = groove
	metrics["variety"] = variety
	metrics["energy"] = energy
	metrics["complexity"] = complexity
	metrics["score"] = clamp(base_score + build_bonus, 0, 100)
	metrics["total_hits"] = total_hits
	metrics["track_hits"] = track_hits
	metrics["explanation"] = "Densidad %.2f | Sync %.2f | Groove %.2f | Variedad %.2f | Energia %.2f" % [density, syncopation, groove, variety, energy]

	return metrics

func _compute_groove(patterns: Dictionary, steps_per_loop: int) -> float:
	var kick: Array = patterns.get("kick", [])
	var snare: Array = patterns.get("snare", [])
	var hat: Array = patterns.get("hat", [])

	var downbeats = [0, 4, 8, 12]
	var backbeats = [4, 12]
	var kick_hits = 0
	var snare_hits = 0

	for beat_step in downbeats:
		if beat_step < steps_per_loop and beat_step < kick.size() and int(kick[beat_step]) == 1:
			kick_hits += 1
	for beat_step in backbeats:
		if beat_step < steps_per_loop and beat_step < snare.size() and int(snare[beat_step]) == 1:
			snare_hits += 1

	var hat_density = 0.0
	if not hat.is_empty():
		var hat_hits = 0
		for i in range(min(steps_per_loop, hat.size())):
			if int(hat[i]) == 1:
				hat_hits += 1
		hat_density = float(hat_hits) / max(1.0, float(steps_per_loop))

	var kick_ratio = float(kick_hits) / 4.0
	var snare_ratio = float(snare_hits) / 2.0
	return clamp(kick_ratio * 0.45 + snare_ratio * 0.35 + min(1.0, hat_density * 1.25) * 0.20, 0.0, 1.0)

func _compute_variety(patterns: Dictionary, steps_per_loop: int) -> float:
	var transitions_accum = 0.0
	var unique_patterns: Dictionary = {}
	var track_count: int = max(1, patterns.size())

	for track_name in patterns.keys():
		var pattern: Array = patterns[track_name]
		var transitions = 0
		for i in range(min(steps_per_loop - 1, pattern.size() - 1)):
			if int(pattern[i]) != int(pattern[i + 1]):
				transitions += 1
		transitions_accum += float(transitions) / max(1.0, float(steps_per_loop - 1))
		unique_patterns[str(pattern)] = true

	var transition_score = transitions_accum / float(track_count)
	var uniqueness_score = float(unique_patterns.size()) / float(track_count)
	return clamp(transition_score * 0.7 + uniqueness_score * 0.3, 0.0, 1.0)

func _compute_energy(track_hits: Dictionary, steps_per_loop: int) -> float:
	var weights = {
		"kick": 1.8,
		"snare": 1.2,
		"hat": 1.0,
		"bass": 1.3,
		"melody": 0.9,
		"fx": 0.6,
	}
	var weighted_hits = 0.0
	var max_weighted_hits = 0.0

	for track_name in weights.keys():
		var weight = float(weights[track_name])
		weighted_hits += float(track_hits.get(track_name, 0)) * weight
		max_weighted_hits += float(steps_per_loop) * weight

	return clamp(weighted_hits / max(1.0, max_weighted_hits), 0.0, 1.0)
