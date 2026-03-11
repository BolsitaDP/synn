extends Node
class_name RunManager

signal run_started(state: Dictionary)
signal run_updated(state: Dictionary)
signal reward_offered(rewards: Array)
signal run_ended(victory: bool, reason: String)

@export var max_hp: int = 12
@export var phases_total: int = 3
@export var steps_per_phase: int = 3

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _run_active: bool = false
var _awaiting_reward: bool = false

var _state: Dictionary = {}
var _current_choices: Array = []
var _selected_choice_index: int = -1
var _pending_node: Dictionary = {}
var _pending_rewards: Array = []

func _ready() -> void:
	_rng.randomize()

func start_new_run(seed: int = 0) -> void:
	if seed != 0:
		_rng.seed = seed
	else:
		_rng.randomize()

	_run_active = true
	_awaiting_reward = false
	_pending_rewards.clear()
	_state = {
		"seed": seed,
		"hp": max_hp,
		"max_hp": max_hp,
		"coins": 3,
		"phase": 1,
		"phase_step": 1,
		"floor": 1,
		"floors_total": phases_total * steps_per_phase,
		"base_profile_id": "",
		"last_result": {},
		"last_node_type": "",
	}

	_current_choices = _generate_choices(1, 1)
	if _current_choices.is_empty():
		_current_choices = [_make_node("combat", 1, 1)]

	_selected_choice_index = 0
	_pending_node = (_current_choices[0] as Dictionary).duplicate(true)

	var snapshot: Dictionary = get_state()
	emit_signal("run_started", snapshot)
	emit_signal("run_updated", snapshot)

func get_state() -> Dictionary:
	return {
		"active": _run_active,
		"awaiting_reward": _awaiting_reward,
		"hp": int(_state.get("hp", 0)),
		"max_hp": int(_state.get("max_hp", max_hp)),
		"coins": int(_state.get("coins", 0)),
		"phase": int(_state.get("phase", 1)),
		"phase_step": int(_state.get("phase_step", 1)),
		"floor": int(_state.get("floor", 1)),
		"floors_total": int(_state.get("floors_total", phases_total * steps_per_phase)),
		"base_profile_id": String(_state.get("base_profile_id", "")),
		"selected_choice_index": _selected_choice_index,
		"current_choices": _duplicate_choice_array(),
		"pending_node": _pending_node.duplicate(true),
		"pending_rewards": _duplicate_reward_array(),
		"last_result": (_state.get("last_result", {}) as Dictionary).duplicate(true),
	}

func select_choice(index: int) -> void:
	if not _run_active or _awaiting_reward:
		return
	if index < 0 or index >= _current_choices.size():
		return

	_selected_choice_index = index
	_pending_node = (_current_choices[index] as Dictionary).duplicate(true)
	_emit_update()

func enter_selected_node() -> Dictionary:
	if not _run_active:
		return {"status": "inactive"}
	if _awaiting_reward:
		return {"status": "awaiting_reward"}
	if _pending_node.is_empty():
		return {"status": "no_node"}

	var node: Dictionary = _pending_node.duplicate(true)
	var node_type: String = String(node.get("type", ""))
	_state["last_node_type"] = node_type

	if node_type == "base_seed":
		var base_profile_id: String = String(node.get("base_profile_id", ""))
		_state["base_profile_id"] = base_profile_id
		_advance_position()
		_emit_update()
		return {
			"status": "base_choice",
			"node": node,
			"base_profile_id": base_profile_id,
			"summary": "Base elegida: %s" % String(node.get("label", "Base")),
		}

	if _is_battle_node(node_type):
		return {
			"status": "battle",
			"node": node,
		}

	var summary: String = _resolve_instant_node(node)
	if _run_active and not _awaiting_reward:
		_advance_position()

	_emit_update()
	return {
		"status": "instant",
		"node": node,
		"summary": summary,
	}

func resolve_battle_result(node: Dictionary, victory: bool, battle_score: int, score: int, reason: String) -> Dictionary:
	if not _run_active:
		return {"status": "inactive"}

	var node_type: String = String(node.get("type", "combat"))
	var hp: int = int(_state.get("hp", max_hp))
	var coins: int = int(_state.get("coins", 0))
	var is_final_boss: bool = _is_final_boss_node(node_type)

	if victory:
		coins += _coin_gain_for(node_type)
		_state["coins"] = coins
		_state["last_result"] = {
			"node_type": node_type,
			"victory": true,
			"battle_score": battle_score,
			"score": score,
			"reason": reason,
		}

		if is_final_boss:
			_end_run(true, "Boss final derrotado. Run completada.")
			return {"status": "resolved", "victory": true}

		var rewards: Array = _build_rewards_for(node_type)
		if rewards.is_empty():
			_advance_position()
		else:
			_awaiting_reward = true
			_pending_rewards = rewards
			emit_signal("reward_offered", _duplicate_reward_array())
	else:
		hp = max(0, hp - _damage_for(node_type))
		_state["hp"] = hp
		_state["coins"] = coins + 1
		_state["last_result"] = {
			"node_type": node_type,
			"victory": false,
			"battle_score": battle_score,
			"score": score,
			"reason": reason,
		}

		if hp <= 0:
			_end_run(false, "Derrota: te quedaste sin HP.")
			return {"status": "resolved", "victory": false}

		if node_type == "boss":
			_end_run(false, "Derrota: boss no superado.")
			return {"status": "resolved", "victory": false}

		_advance_position()

	_emit_update()
	return {
		"status": "resolved",
		"victory": victory,
	}

func select_reward(index: int) -> Dictionary:
	if not _run_active:
		return {"status": "inactive"}
	if not _awaiting_reward:
		return {"status": "no_reward"}
	if index < 0 or index >= _pending_rewards.size():
		return {"status": "invalid_index"}

	var reward: Dictionary = (_pending_rewards[index] as Dictionary).duplicate(true)
	var cost: int = int(reward.get("cost", 0))
	var coins: int = int(_state.get("coins", 0))
	if cost > coins:
		return {
			"status": "insufficient_funds",
			"cost": cost,
			"coins": coins,
		}

	_state["coins"] = coins - cost
	var external_reward: Dictionary = {}
	var reward_type: String = String(reward.get("type", ""))

	match reward_type:
		"coins":
			_state["coins"] = int(_state.get("coins", 0)) + int(reward.get("amount", 0))
		"heal":
			var hp: int = int(_state.get("hp", max_hp))
			_state["hp"] = min(max_hp, hp + int(reward.get("amount", 0)))
		_:
			external_reward = reward.duplicate(true)

	_awaiting_reward = false
	_pending_rewards.clear()
	_advance_position()
	_emit_update()

	return {
		"status": "ok",
		"reward": reward,
		"external_reward": external_reward,
	}

func add_coins(amount: int) -> void:
	if not _run_active:
		return
	_state["coins"] = max(0, int(_state.get("coins", 0)) + amount)
	_emit_update()

func heal(amount: int) -> void:
	if not _run_active:
		return
	var hp: int = int(_state.get("hp", max_hp))
	_state["hp"] = clamp(hp + amount, 0, max_hp)
	_emit_update()

func _resolve_instant_node(node: Dictionary) -> String:
	var node_type: String = String(node.get("type", "event"))
	match node_type:
		"rest":
			var hp: int = int(_state.get("hp", max_hp))
			_state["hp"] = min(max_hp, hp + 3)
			return "Descanso: +3 HP"
		"event":
			var gain: int = _rng.randi_range(1, 4)
			_state["coins"] = int(_state.get("coins", 0)) + gain
			var rewards: Array = _build_rewards_for("event")
			if not rewards.is_empty():
				_awaiting_reward = true
				_pending_rewards = rewards
				emit_signal("reward_offered", _duplicate_reward_array())
			return "Evento: +%d coins" % gain
		"shop":
			var shop_rewards: Array = _build_rewards_for("shop")
			_awaiting_reward = true
			_pending_rewards = shop_rewards
			emit_signal("reward_offered", _duplicate_reward_array())
			return "Tienda: elige una compra"
		_:
			return "Nodo resuelto"

func _advance_position() -> void:
	if not _run_active:
		return

	var phase: int = int(_state.get("phase", 1))
	var phase_step: int = int(_state.get("phase_step", 1))

	phase_step += 1
	if phase_step > steps_per_phase:
		phase += 1
		phase_step = 1

	if phase > phases_total:
		_end_run(true, "Run completada.")
		return

	_state["phase"] = phase
	_state["phase_step"] = phase_step
	_state["floor"] = ((phase - 1) * steps_per_phase) + phase_step

	_current_choices = _generate_choices(phase, phase_step)
	if _current_choices.is_empty():
		_current_choices = [_make_node("combat", phase, phase_step)]

	_selected_choice_index = 0
	_pending_node = (_current_choices[0] as Dictionary).duplicate(true)

func _end_run(victory: bool, reason: String) -> void:
	_run_active = false
	_awaiting_reward = false
	_pending_rewards.clear()
	_current_choices.clear()
	_selected_choice_index = -1
	_pending_node.clear()
	emit_signal("run_ended", victory, reason)

func _generate_choices(phase: int, phase_step: int) -> Array:
	if phase == 1 and phase_step == 1 and String(_state.get("base_profile_id", "")).is_empty():
		return _base_seed_choices()

	if phase_step == 3:
		return [_make_node("boss", phase, phase_step)]

	var choices: Array = []
	for _i in range(3):
		var roll: float = _rng.randf()
		var node_type: String = "combat"
		if roll < 0.45:
			node_type = "combat"
		elif roll < 0.62:
			node_type = "event"
		elif roll < 0.76:
			node_type = "rest"
		elif roll < 0.88:
			node_type = "shop"
		else:
			node_type = "elite"
		choices.append(_make_node(node_type, phase, phase_step))

	var has_combat: bool = false
	for choice in choices:
		var item_type: String = String((choice as Dictionary).get("type", ""))
		if item_type == "combat" or item_type == "elite":
			has_combat = true
			break
	if not has_combat and not choices.is_empty():
		choices[0] = _make_node("combat", phase, phase_step)

	return choices

func _base_seed_choices() -> Array:
	return [
		_make_base_seed("pulse_foundry", "Base A // Pulse Foundry", "Kick solido y bajo directo"),
		_make_base_seed("sync_weave", "Base B // Sync Weave", "Ritmo sincopado y hats movidos"),
		_make_base_seed("neon_mist", "Base C // Neon Mist", "Espacio melodico y groove ligero"),
	]

func _make_base_seed(base_profile_id: String, label: String, subtitle: String) -> Dictionary:
	return {
		"type": "base_seed",
		"phase": 1,
		"phase_step": 1,
		"base_profile_id": base_profile_id,
		"label": label,
		"subtitle": subtitle,
	}

func _make_node(node_type: String, phase: int, phase_step: int) -> Dictionary:
	var node: Dictionary = {
		"type": node_type,
		"phase": phase,
		"phase_step": phase_step,
		"label": "%d-%d %s" % [phase, phase_step, node_type.capitalize()],
	}

	match node_type:
		"combat":
			node["boss_id"] = _pick_boss(["groove_test", "syncopation_boss", "minimalism_boss"])
			node["required_score"] = 34 + phase * 5 + phase_step * 2
			node["damage_on_fail"] = 2
			node["label"] = "%d-%d Combat vs %s" % [phase, phase_step, String(node["boss_id"])]
		"elite":
			node["boss_id"] = _pick_boss(["energy_boss", "jazz_boss", "syncopation_boss"])
			node["required_score"] = 48 + phase * 6
			node["damage_on_fail"] = 3
			node["label"] = "%d-%d Elite vs %s" % [phase, phase_step, String(node["boss_id"])]
		"boss":
			node["boss_id"] = _pick_boss(["energy_boss", "jazz_boss"])
			node["required_score"] = 56 + phase * 4
			node["damage_on_fail"] = 4
			node["label"] = "%d-%d BOSS %s" % [phase, phase_step, String(node["boss_id"])]
		"event":
			node["label"] = "%d-%d Evento" % [phase, phase_step]
		"shop":
			node["label"] = "%d-%d Tienda" % [phase, phase_step]
		"rest":
			node["label"] = "%d-%d Descanso" % [phase, phase_step]

	return node

func _build_rewards_for(node_type: String) -> Array:
	match node_type:
		"combat":
			return [
				{"type": "card_draft", "label": "Draft de carta", "cost": 0, "count": 3},
				{"type": "variation", "label": "Mutacion controlada", "cost": 0},
				{"type": "heal", "label": "Recuperar +2 HP", "amount": 2, "cost": 0},
			]
		"elite":
			return [
				{"type": "card_draft", "label": "Draft elite", "cost": 0, "count": 3, "kind_filter": ["passive", "active"]},
				{"type": "randomize_track", "label": "Reforge de track", "cost": 0},
				{"type": "heal", "label": "Recuperar +3 HP", "amount": 3, "cost": 0},
			]
		"boss":
			return [
				{"type": "card_draft", "label": "Draft boss", "cost": 0, "count": 3, "kind_filter": ["passive", "active"]},
				{"type": "heal", "label": "Recuperar +4 HP", "amount": 4, "cost": 0},
				{"type": "coins", "label": "+5 Coins", "amount": 5, "cost": 0},
			]
		"event":
			return [
				{"type": "coins", "label": "+4 Coins", "amount": 4, "cost": 0},
				{"type": "card_draft", "label": "Draft evento", "cost": 0, "count": 3, "kind_filter": ["active", "passive"]},
				{"type": "heal", "label": "Recuperar +1 HP", "amount": 1, "cost": 0},
			]
		"shop":
			return [
				{"type": "card_draft", "label": "Comprar pack de cartas", "cost": 3, "count": 3},
				{"type": "variation", "label": "Comprar mutacion", "cost": 2},
				{"type": "heal", "label": "Comprar +2 HP", "amount": 2, "cost": 2},
			]
		_:
			return []

func _coin_gain_for(node_type: String) -> int:
	match node_type:
		"combat":
			return 2
		"elite":
			return 4
		"boss":
			return 5
		_:
			return 1

func _damage_for(node_type: String) -> int:
	match node_type:
		"combat":
			return 2
		"elite":
			return 3
		"boss":
			return 4
		_:
			return 1

func _pick_boss(options: Array) -> String:
	if options.is_empty():
		return "groove_test"
	var idx: int = _rng.randi_range(0, options.size() - 1)
	return String(options[idx])

func _is_battle_node(node_type: String) -> bool:
	return node_type == "combat" or node_type == "elite" or node_type == "boss"

func _is_final_boss_node(node_type: String) -> bool:
	if node_type != "boss":
		return false
	return int(_state.get("phase", 1)) == phases_total and int(_state.get("phase_step", 1)) == steps_per_phase

func _emit_update() -> void:
	emit_signal("run_updated", get_state())

func _duplicate_choice_array() -> Array:
	var out: Array = []
	for item in _current_choices:
		out.append((item as Dictionary).duplicate(true))
	return out

func _duplicate_reward_array() -> Array:
	var out: Array = []
	for reward in _pending_rewards:
		out.append((reward as Dictionary).duplicate(true))
	return out
