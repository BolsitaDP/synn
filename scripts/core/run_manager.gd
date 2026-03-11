extends Node
class_name RunManager

signal run_started(state: Dictionary)
signal run_updated(state: Dictionary)
signal reward_offered(rewards: Array)
signal run_ended(victory: bool, reason: String)

@export var max_hp: int = 12
@export var phases_total: int = 1
@export var steps_per_phase: int = 4

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
		"streak": 0,
		"battles_won": 0,
		"visited_nodes": [],
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
		"streak": int(_state.get("streak", 0)),
		"battles_won": int(_state.get("battles_won", 0)),
		"visited_nodes": _duplicate_visited_nodes(),
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
		_record_node_visit(node_type)
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
	_record_node_visit(node_type)
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
	var streak: int = int(_state.get("streak", 0))
	var battles_won: int = int(_state.get("battles_won", 0))
	var damage_on_fail: int = int(node.get("damage_on_fail", _damage_for(node_type)))
	var is_final_boss: bool = _is_final_boss_node(node_type)

	if victory:
		coins += _coin_gain_for(node_type)
		streak += 1
		if streak >= 2:
			coins += 1
		battles_won += 1
		_state["coins"] = coins
		_state["streak"] = streak
		_state["battles_won"] = battles_won
		_state["last_result"] = {
			"node_type": node_type,
			"victory": true,
			"battle_score": battle_score,
			"score": score,
			"reason": reason,
		}
		_record_node_visit(node_type)

		if is_final_boss:
			_end_run(true, "Miniboss derrotado. Acto 1 completado.")
			return {"status": "resolved", "victory": true}

		var rewards: Array = _build_rewards_for(node_type)
		if rewards.is_empty():
			_advance_position()
		else:
			_awaiting_reward = true
			_pending_rewards = rewards
			emit_signal("reward_offered", _duplicate_reward_array())
	else:
		hp = max(0, hp - damage_on_fail)
		coins += 1
		streak = 0
		_state["hp"] = hp
		_state["coins"] = coins
		_state["streak"] = streak
		_state["last_result"] = {
			"node_type": node_type,
			"victory": false,
			"battle_score": battle_score,
			"score": score,
			"reason": reason,
		}
		_record_node_visit(node_type)

		if hp <= 0:
			_end_run(false, "Derrota: te quedaste sin HP.")
			return {"status": "resolved", "victory": false}

		if is_final_boss:
			_end_run(false, "Derrota: no superaste el miniboss.")
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

	if phase == 1 and phase_step == 2:
		var base_profile_id: String = String(_state.get("base_profile_id", ""))
		return [
			_make_first_enemy_node(base_profile_id),
			_make_node("shop", phase, phase_step),
			_make_node("event", phase, phase_step),
		]

	if phase == 1 and phase_step == 3:
		var won_battles: int = int(_state.get("battles_won", 0))
		if won_battles >= 1:
			return [
				_make_node("elite", phase, phase_step),
				_make_node("rest", phase, phase_step),
				_make_node("event", phase, phase_step),
			]
		return [
			_make_node("combat", phase, phase_step),
			_make_node("shop", phase, phase_step),
			_make_node("event", phase, phase_step),
		]

	if phase == 1 and phase_step == 4:
		return [_make_miniboss_node(String(_state.get("base_profile_id", "")))]

	if phase_step == steps_per_phase:
		return [_make_node("boss", phase, phase_step)]

	var choices: Array = []
	for _i in range(3):
		var roll: float = _rng.randf()
		var node_type: String = "combat"
		if roll < 0.48:
			node_type = "combat"
		elif roll < 0.65:
			node_type = "event"
		elif roll < 0.79:
			node_type = "rest"
		elif roll < 0.90:
			node_type = "shop"
		else:
			node_type = "elite"
		choices.append(_make_node(node_type, phase, phase_step))
	return choices

func _base_seed_choices() -> Array:
	return [
		_make_base_seed("drum_seed", "Carta A // Drum Pulse", "Unico instrumento: kick simple"),
		_make_base_seed("trumpet_seed", "Carta B // Brass Call", "Unico instrumento: trompeta sintetica"),
		_make_base_seed("bass_seed", "Carta C // Bass March", "Unico instrumento: bajo basico"),
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

func _make_first_enemy_node(base_profile_id: String) -> Dictionary:
	var required_track: String = _base_track_for_profile(base_profile_id)
	var min_hits: int = 6
	var track_label: String = _base_track_label_for_profile(base_profile_id)
	return {
		"type": "first_enemy",
		"phase": 1,
		"phase_step": 2,
		"label": "1-2 Combate // Dummy Groove",
		"enemy_name": "Dummy Groove",
		"enemy_visual": "( >_< )",
		"required_track": required_track,
		"required_track_label": track_label,
		"min_hits": min_hits,
		"goal_type": "track_hits",
		"goal_track": required_track,
		"goal_min_hits": min_hits,
		"objective": "Objetivo: >= %d golpes en %s" % [min_hits, track_label],
		"subtitle": "Entrena tu base para abrir ruta",
		"required_score": 0,
		"damage_on_fail": 2,
	}

func _make_miniboss_node(base_profile_id: String) -> Dictionary:
	var boss_id: String = "energy_boss"
	match base_profile_id:
		"trumpet_seed":
			boss_id = "jazz_boss"
		"bass_seed":
			boss_id = "groove_test"
		_:
			boss_id = "energy_boss"

	return {
		"type": "miniboss",
		"phase": 1,
		"phase_step": 4,
		"label": "1-4 MINIBOSS // Gatekeeper",
		"enemy_name": "Gatekeeper",
		"enemy_visual": "( O_O )",
		"boss_id": boss_id,
		"goal_type": "syncopation_and_groove",
		"goal_min_syncopation": 0.22,
		"goal_min_groove": 0.45,
		"objective": "Objetivo: score >= 52, sync >= 0.22 y groove >= 0.45",
		"subtitle": "Chequeo final del acto",
		"required_score": 52,
		"damage_on_fail": 4,
	}

func _base_track_for_profile(base_profile_id: String) -> String:
	match base_profile_id:
		"drum_seed":
			return "kick"
		"trumpet_seed":
			return "melody"
		"bass_seed":
			return "bass"
		_:
			return "kick"

func _base_track_label_for_profile(base_profile_id: String) -> String:
	match base_profile_id:
		"drum_seed":
			return "Kick"
		"trumpet_seed":
			return "Trompeta"
		"bass_seed":
			return "Bajo"
		_:
			return "Kick"

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
			node["required_score"] = 36 + phase * 5 + phase_step * 2
			node["goal_type"] = "score_only"
			node["damage_on_fail"] = 2
			node["label"] = "%d-%d Combat // %s" % [phase, phase_step, String(node["boss_id"])]
			node["objective"] = "Objetivo: score >= %d" % int(node["required_score"])
			node["subtitle"] = "Ruta segura para escalar build"
		"elite":
			node["boss_id"] = _pick_boss(["energy_boss", "jazz_boss", "syncopation_boss"])
			node["required_score"] = 50 + phase * 6
			node["goal_type"] = "score_and_sync"
			node["goal_min_syncopation"] = 0.18
			node["damage_on_fail"] = 3
			node["label"] = "%d-%d Elite // %s" % [phase, phase_step, String(node["boss_id"])]
			node["objective"] = "Objetivo: score >= %d y sync >= 0.18" % int(node["required_score"])
			node["subtitle"] = "Mayor riesgo, mejor recompensa"
		"boss":
			node["boss_id"] = _pick_boss(["energy_boss", "jazz_boss"])
			node["required_score"] = 58 + phase * 4
			node["goal_type"] = "score_and_sync"
			node["goal_min_syncopation"] = 0.20
			node["damage_on_fail"] = 4
			node["label"] = "%d-%d BOSS // %s" % [phase, phase_step, String(node["boss_id"])]
			node["objective"] = "Objetivo: score >= %d y sync >= 0.20" % int(node["required_score"])
			node["subtitle"] = "Combate final"
		"event":
			node["label"] = "%d-%d Evento // Jam Room" % [phase, phase_step]
			node["subtitle"] = "Gana coins y posible carta"
		"shop":
			node["label"] = "%d-%d Tienda // Vinyl Dealer" % [phase, phase_step]
			node["subtitle"] = "Invierte coins en power-ups"
		"rest":
			node["label"] = "%d-%d Descanso // Green Room" % [phase, phase_step]
			node["subtitle"] = "Recupera HP y estabiliza run"

	return node

func _build_rewards_for(node_type: String) -> Array:
	match node_type:
		"first_enemy":
			return [
				{"type": "card_draft", "label": "Recompensa: carta", "cost": 0, "count": 3},
				{"type": "heal", "label": "Recuperar +2 HP", "amount": 2, "cost": 0},
				{"type": "coins", "label": "+3 Coins", "amount": 3, "cost": 0},
			]
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
		"miniboss":
			return [
				{"type": "card_draft", "label": "Draft miniboss", "cost": 0, "count": 3, "kind_filter": ["passive", "active"]},
				{"type": "coins", "label": "+6 Coins", "amount": 6, "cost": 0},
				{"type": "heal", "label": "Recuperar +4 HP", "amount": 4, "cost": 0},
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
		"first_enemy":
			return 2
		"combat":
			return 2
		"elite":
			return 4
		"miniboss":
			return 6
		"boss":
			return 5
		_:
			return 1

func _damage_for(node_type: String) -> int:
	match node_type:
		"first_enemy":
			return 2
		"combat":
			return 2
		"elite":
			return 3
		"miniboss":
			return 4
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
	return node_type == "first_enemy" or node_type == "combat" or node_type == "elite" or node_type == "miniboss" or node_type == "boss"

func _is_final_boss_node(node_type: String) -> bool:
	var is_boss_like: bool = node_type == "miniboss" or node_type == "boss"
	if not is_boss_like:
		return false
	return int(_state.get("phase", 1)) == phases_total and int(_state.get("phase_step", 1)) == steps_per_phase

func _record_node_visit(node_type: String) -> void:
	var visited_variant: Variant = _state.get("visited_nodes", [])
	if typeof(visited_variant) != TYPE_ARRAY:
		_state["visited_nodes"] = [node_type]
		return
	var visited_nodes: Array = visited_variant as Array
	visited_nodes.append(node_type)
	_state["visited_nodes"] = visited_nodes

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

func _duplicate_visited_nodes() -> Array:
	var out: Array = []
	var visited_variant: Variant = _state.get("visited_nodes", [])
	if typeof(visited_variant) != TYPE_ARRAY:
		return out
	var visited_nodes: Array = visited_variant as Array
	for node_type in visited_nodes:
		out.append(String(node_type))
	return out
