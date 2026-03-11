extends Node
class_name BattleSystem

# Lightweight boss evaluator for validating the gameplay loop.
var _bosses: Dictionary = {
	"groove_test": {
		"name": "Groove Test",
		"description": "Requiere pulso claro y suficientes golpes por loop.",
	},
	"syncopation_boss": {
		"name": "Syncopation Boss",
		"description": "Premia notas fuera del beat.",
	},
	"minimalism_boss": {
		"name": "Minimalism Boss",
		"description": "Castiga exceso de notas.",
	},
	"energy_boss": {
		"name": "Energy Boss",
		"description": "Exige energia ritmica alta y kick dominante.",
	},
	"jazz_boss": {
		"name": "Jazz Boss",
		"description": "Premia swing y variacion.",
	},
}

func get_boss_ids() -> Array[String]:
	var ids: Array[String] = []
	for boss_id in _bosses.keys():
		ids.append(boss_id)
	ids.sort()
	return ids

func get_boss_definitions() -> Dictionary:
	return _bosses.duplicate(true)

func evaluate_battle(boss_id: String, metrics: Dictionary, patterns: Dictionary, upgrades_enabled: Dictionary) -> Dictionary:
	if not _bosses.has(boss_id):
		return {
			"boss_id": boss_id,
			"boss_name": "Desconocido",
			"victory": false,
			"battle_score": 0,
			"reason": "Boss no encontrado.",
		}

	var result = {
		"boss_id": boss_id,
		"boss_name": String(_bosses[boss_id].get("name", boss_id)),
		"victory": false,
		"battle_score": 0,
		"reason": "",
	}

	var track_hits: Dictionary = metrics.get("track_hits", {})
	var total_hits = int(metrics.get("total_hits", 0))
	var density = float(metrics.get("density", 0.0))
	var syncopation = float(metrics.get("syncopation", 0.0))
	var groove = float(metrics.get("groove", 0.0))
	var variety = float(metrics.get("variety", 0.0))
	var energy = float(metrics.get("energy", 0.0))
	var complexity = float(metrics.get("complexity", 0.0))
	var base_score = int(metrics.get("score", 0))

	match boss_id:
		"groove_test":
			var ok = groove >= 0.55 and total_hits >= 16
			result["victory"] = ok
			result["battle_score"] = clamp(base_score + int(round(groove * 25.0)), 0, 150)
			result["reason"] = "Victoria por groove estable." if ok else "Fallo: groove < 0.55 o muy pocos golpes."

		"syncopation_boss":
			var ok = syncopation >= 0.45
			result["victory"] = ok
			result["battle_score"] = clamp(base_score + int(round(syncopation * 35.0)), 0, 150)
			result["reason"] = "Victoria por alta sincopa." if ok else "Fallo: falta de notas fuera del beat."

		"minimalism_boss":
			var ok = density >= 0.14 and density <= 0.38 and complexity <= 0.68
			result["victory"] = ok
			result["battle_score"] = clamp(base_score + int(round((0.4 - abs(density - 0.26)) * 50.0)), 0, 150)
			result["reason"] = "Victoria por arreglo minimalista controlado." if ok else "Fallo: demasiada (o muy poca) densidad."

		"energy_boss":
			var kick_hits = int(track_hits.get("kick", 0))
			var ok = energy >= 0.58 and kick_hits >= 6
			result["victory"] = ok
			result["battle_score"] = clamp(base_score + int(round(energy * 40.0)) + kick_hits, 0, 150)
			result["reason"] = "Victoria por energia y kick fuerte." if ok else "Fallo: energia baja o pocos kicks."

		"jazz_boss":
			var has_swing = bool(upgrades_enabled.get("swing_mode", false))
			var ok = variety >= 0.55 and (syncopation >= 0.35 or has_swing)
			result["victory"] = ok
			result["battle_score"] = clamp(base_score + int(round(variety * 30.0 + syncopation * 20.0)) + (10 if has_swing else 0), 0, 150)
			result["reason"] = "Victoria por variacion y color jazz." if ok else "Fallo: falta variacion/swing."

	return result
