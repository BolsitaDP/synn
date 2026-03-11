extends RefCounted
class_name CardLibrary

const CARD_DATA_SCRIPT = preload("res://scripts/core/card_data.gd")

var _cards: Array = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()
	_build_library()

func set_seed(seed: int) -> void:
	if seed == 0:
		_rng.randomize()
	else:
		_rng.seed = seed

func get_card_by_id(card_id: String) -> Dictionary:
	for card in _cards:
		if card.card_id == card_id:
			return card.to_dict()
	return {}

func random_draft(amount: int, kind_filter: Array = ["passive", "active"]) -> Array:
	var pool: Array = []
	for card in _cards:
		if kind_filter.is_empty() or kind_filter.has(card.card_kind):
			pool.append(card)

	if pool.is_empty() or amount <= 0:
		return []

	var result: Array = []
	var used_ids: Dictionary = {}
	var safety: int = 0
	while result.size() < amount and safety < 100:
		safety += 1
		var pick = pool[_rng.randi_range(0, pool.size() - 1)]
		if used_ids.has(pick.card_id):
			continue
		used_ids[pick.card_id] = true
		result.append(pick.to_dict())

	return result

func _build_library() -> void:
	_cards.clear()

	# Passive cards: global build modifiers.
	_cards.append(_card("p_swing_core", "Swing Core", "Activa swing permanente.", "passive", "common", {"effect": "enable_upgrade", "upgrade_id": "swing_mode"}))
	_cards.append(_card("p_kick_twins", "Kick Twins", "Activa double kick permanente.", "passive", "common", {"effect": "enable_upgrade", "upgrade_id": "double_kick"}))
	_cards.append(_card("p_hat_rush", "Hat Rush", "Activa dense hats permanente.", "passive", "common", {"effect": "enable_upgrade", "upgrade_id": "dense_hats"}))
	_cards.append(_card("p_bass_lock", "Bass Lock", "Activa bass drive permanente.", "passive", "common", {"effect": "enable_upgrade", "upgrade_id": "bass_drive"}))
	_cards.append(_card("p_echo_lane", "Echo Lane", "Activa eco de melodia permanente.", "passive", "common", {"effect": "enable_upgrade", "upgrade_id": "echo_melody"}))
	_cards.append(_card("p_fill_instinct", "Fill Instinct", "Activa random fill permanente.", "passive", "common", {"effect": "enable_upgrade", "upgrade_id": "random_fill"}))
	_cards.append(_card("p_groove_tax", "Groove Tax", "+6 score base en combates.", "passive", "uncommon", {"effect": "score_bonus", "amount": 6}))
	_cards.append(_card("p_sync_tax", "Sync Tax", "+8 score base en combates.", "passive", "uncommon", {"effect": "score_bonus", "amount": 8}))
	_cards.append(_card("p_boss_favor", "Boss Favor", "+12 score vs boss final.", "passive", "rare", {"effect": "boss_score_bonus", "amount": 12}))
	_cards.append(_card("p_coin_aura", "Coin Aura", "+2 coins al recibir esta carta.", "passive", "common", {"effect": "grant_coins", "amount": 2}))
	_cards.append(_card("p_stitch", "Stitch", "Recupera +2 HP al recibirla.", "passive", "common", {"effect": "heal", "amount": 2}))
	_cards.append(_card("p_combo_slot", "Combo Slot", "Aumenta mano activa maxima en +1.", "passive", "rare", {"effect": "active_hand_bonus", "amount": 1}))

	# Active cards: one-shot tactical actions.
	_cards.append(_card("a_micro_fill", "Micro Fill", "Aplica una variacion controlada.", "active", "common", {"effect": "variation"}))
	_cards.append(_card("a_kick_punch", "Kick Punch", "Refuerza el track kick.", "active", "common", {"effect": "reforge_track", "track": "kick"}))
	_cards.append(_card("a_snare_flip", "Snare Flip", "Refuerza el track snare.", "active", "common", {"effect": "reforge_track", "track": "snare"}))
	_cards.append(_card("a_melody_glitch", "Melody Glitch", "Refuerza el track melody.", "active", "common", {"effect": "reforge_track", "track": "melody"}))
	_cards.append(_card("a_fx_spark", "FX Spark", "Refuerza el track fx.", "active", "common", {"effect": "reforge_track", "track": "fx"}))
	_cards.append(_card("a_reroll_all", "Hard Reroll", "Randomiza todo el build base.", "active", "uncommon", {"effect": "reroll_all"}))
	_cards.append(_card("a_heat_up", "Heat Up", "+10 score para el proximo combate.", "active", "uncommon", {"effect": "temp_score_bonus", "amount": 10}))
	_cards.append(_card("a_cash_out", "Cash Out", "Gana +3 coins.", "active", "common", {"effect": "grant_coins", "amount": 3}))

func _card(card_id: String, name: String, description: String, card_kind: String, rarity: String, payload: Dictionary) -> Resource:
	var card = CARD_DATA_SCRIPT.new()
	card.card_id = card_id
	card.name = name
	card.description = description
	card.card_kind = card_kind
	card.rarity = rarity
	card.payload = payload.duplicate(true)
	return card
