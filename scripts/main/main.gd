extends Node
class_name Main

# Main composition root: wires audio layers, sequencing, upgrades, battles and UI.
const STEPS_PER_LOOP = 16
const DEFAULT_RUN_BPM: int = 116
const CARD_LIBRARY_SCRIPT = preload("res://scripts/core/card_library.gd")
@export var auto_start_on_play: bool = false

@onready var clock: MusicClock = $MusicClock
@onready var sequencer: Sequencer = $Sequencer
@onready var upgrade_system: UpgradeSystem = $UpgradeSystem
@onready var score_analyzer: ScoreAnalyzer = $ScoreAnalyzer
@onready var battle_system: BattleSystem = $BattleSystem
@onready var run_manager: RunManager = $RunManager
@onready var ui: UIController = $CanvasLayer/UIRoot

@onready var drums_layer: InstrumentLayer = $Layers/DrumsLayer
@onready var bass_layer: InstrumentLayer = $Layers/BassLayer
@onready var melody_layer: InstrumentLayer = $Layers/MelodyLayer
@onready var fx_layer: InstrumentLayer = $Layers/FxLayer

var _layers: Dictionary = {}
var _track_to_layer: Dictionary = {
	"kick": "drums",
	"snare": "drums",
	"hat": "drums",
	"bass": "bass",
	"melody": "melody",
	"fx": "fx",
}

var _selected_track: String = "kick"
var _current_metrics: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _card_library: CardLibrary = CARD_LIBRARY_SCRIPT.new()
var _passive_cards: Array = []
var _active_cards: Array = []
var _pending_card_draft: Array = []
var _temp_score_bonus: int = 0
var _base_active_hand_size: int = 3
var _preview_tween: Tween
var _master_volume_linear: float = 0.72
var _master_muted: bool = false
var _decision_ducking_enabled: bool = true
var _decision_duck_factor: float = 0.55

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = false
	get_window().title = "SYNN // Vertical Slice"
	get_window().min_size = Vector2i(1200, 760)
	_rng.randomize()
	_configure_layers()
	_configure_sequencer()
	_connect_signals()
	_configure_ui()
	_apply_master_volume()
	sequencer.rebuild_now(0)
	_refresh_metrics()
	ui.update_clock_display(clock.current_step, clock.loop_index, clock.bpm, clock.running)
	ui.update_variation_display("Prototipo cargado. Usa Start/Stop o edita patrones en vivo.")
	if auto_start_on_play:
		clock.start_clock()
		ui.update_clock_display(clock.current_step, clock.loop_index, clock.bpm, clock.running)
	_reset_cards()
	run_manager.start_new_run()
	_sync_run_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				if clock.running:
					_on_stop_requested()
				else:
					_on_start_requested()
			KEY_R:
				_on_random_build_requested()
			KEY_V:
				_on_manual_variation_requested()
			KEY_B:
				var bosses = battle_system.get_boss_ids()
				if not bosses.is_empty():
					_on_battle_requested(bosses[0])
			KEY_MINUS, KEY_KP_SUBTRACT:
				_on_master_volume_changed(_master_volume_linear - 0.1)
			KEY_EQUAL, KEY_KP_ADD:
				_on_master_volume_changed(_master_volume_linear + 0.1)
			KEY_M:
				_on_master_mute_toggled(not _master_muted)

func _configure_layers() -> void:
	_layers = {
		"drums": drums_layer,
		"bass": bass_layer,
		"melody": melody_layer,
		"fx": fx_layer,
	}

	drums_layer.setup_tracks({
		"kick": {
			"waveform": "sine",
			"freq": 120.0,
			"freq_end": 45.0,
			"decay": 0.18,
			"volume": 0.9,
		},
		"snare": {
			"waveform": "noise",
			"freq": 220.0,
			"decay": 0.10,
			"volume": 0.42,
		},
		"hat": {
			"waveform": "noise",
			"freq": 8000.0,
			"decay": 0.035,
			"volume": 0.20,
		},
	})

	bass_layer.setup_tracks({
		"bass": {
			"waveform": "triangle",
			"freq": 55.0,
			"decay": 0.18,
			"volume": 0.52,
			"freq_sequence": [55.0, 55.0, 65.4, 55.0, 73.4, 65.4, 55.0, 49.0, 55.0, 65.4, 73.4, 55.0, 49.0, 55.0, 65.4, 55.0],
		},
	})

	melody_layer.setup_tracks({
		"melody": {
			"waveform": "square",
			"freq": 220.0,
			"decay": 0.12,
			"volume": 0.24,
			"freq_sequence": [220.0, 247.0, 262.0, 294.0, 330.0, 294.0, 262.0, 247.0, 220.0, 247.0, 262.0, 330.0, 349.0, 330.0, 294.0, 262.0],
		},
	})

	fx_layer.setup_tracks({
		"fx": {
			"waveform": "triangle",
			"freq": 880.0,
			"freq_end": 440.0,
			"decay": 0.20,
			"volume": 0.18,
		},
	})

func _configure_sequencer() -> void:
	sequencer.configure(_layers, _track_to_layer, _default_patterns(), upgrade_system, STEPS_PER_LOOP)

func _connect_signals() -> void:
	clock.step_advanced.connect(_on_clock_step_advanced)
	sequencer.step_processed.connect(_on_sequencer_step_processed)
	sequencer.patterns_rebuilt.connect(_on_patterns_rebuilt)
	sequencer.base_pattern_changed.connect(_on_base_pattern_changed)
	upgrade_system.upgrades_changed.connect(_on_upgrades_changed)
	run_manager.run_started.connect(_on_run_started)
	run_manager.run_updated.connect(_on_run_updated)
	run_manager.reward_offered.connect(_on_run_reward_offered)
	run_manager.run_ended.connect(_on_run_ended)

	ui.start_requested.connect(_on_start_requested)
	ui.stop_requested.connect(_on_stop_requested)
	ui.reset_requested.connect(_on_reset_requested)
	ui.bpm_changed.connect(_on_bpm_changed)
	ui.auto_variation_changed.connect(_on_auto_variation_changed)
	ui.layer_active_changed.connect(_on_layer_active_changed)
	ui.layer_muted_changed.connect(_on_layer_muted_changed)
	ui.upgrade_changed.connect(_on_upgrade_changed)
	ui.track_selected.connect(_on_track_selected)
	ui.step_toggled.connect(_on_step_toggled)
	ui.battle_requested.connect(_on_battle_requested)
	ui.random_build_requested.connect(_on_random_build_requested)
	ui.best_build_search_requested.connect(_on_best_build_search_requested)
	ui.manual_variation_requested.connect(_on_manual_variation_requested)
	ui.run_new_requested.connect(_on_run_new_requested)
	ui.run_choice_selected.connect(_on_run_choice_selected)
	ui.run_enter_requested.connect(_on_run_enter_requested)
	ui.run_reward_selected.connect(_on_run_reward_selected)
	ui.card_play_requested.connect(_on_card_play_requested)
	ui.card_draft_pick_requested.connect(_on_card_draft_pick_requested)
	ui.base_card_hovered.connect(_on_base_card_hovered)
	ui.rhythm_preset_requested.connect(_on_rhythm_preset_requested)
	ui.master_volume_changed.connect(_on_master_volume_changed)
	ui.master_mute_toggled.connect(_on_master_mute_toggled)

func _configure_ui() -> void:
	ui.configure(
		_layer_display_names(),
		_get_layer_states(),
		upgrade_system.get_upgrade_definitions(),
		sequencer.get_track_names(),
		battle_system.get_boss_definitions(),
		STEPS_PER_LOOP,
		clock.bpm
	)
	ui.set_studio_unlocked(false)
	ui.set_master_volume(_master_volume_linear, _master_muted)
	ui.set_track_pattern(_selected_track, sequencer.get_pattern(_selected_track))

func _on_clock_step_advanced(step_index: int, loop_index: int) -> void:
	sequencer.process_step(step_index, loop_index)
	ui.update_clock_display(step_index, loop_index, clock.bpm, clock.running)

func _on_sequencer_step_processed(_step_index: int, _loop_index: int) -> void:
	_refresh_metrics()

func _on_patterns_rebuilt(_patterns: Dictionary, variation_description: String) -> void:
	ui.update_variation_display(variation_description)
	_refresh_metrics()

func _on_base_pattern_changed(track_name: String, pattern: Array) -> void:
	ui.set_track_pattern(track_name, pattern)

func _on_upgrades_changed() -> void:
	var enabled = upgrade_system.get_enabled_map()
	for upgrade_id in enabled.keys():
		ui.set_upgrade_state(upgrade_id, bool(enabled[upgrade_id]))
	sequencer.rebuild_now(clock.loop_index)
	_refresh_metrics()

func _on_start_requested() -> void:
	var run_state: Dictionary = run_manager.get_state()
	if not bool(run_state.get("active", false)):
		ui.update_variation_display("Pulsa New Run para comenzar una fase.")
		return
	if String(run_state.get("base_profile_id", "")).is_empty():
		ui.update_variation_display("Elige una carta base en RUN antes de iniciar el loop.")
		return
	clock.start_clock()
	ui.update_variation_display("Main: Start")
	ui.update_clock_display(clock.current_step, clock.loop_index, clock.bpm, clock.running)

func _on_stop_requested() -> void:
	clock.stop_clock()
	ui.update_variation_display("Main: Stop")
	ui.update_clock_display(clock.current_step, clock.loop_index, clock.bpm, clock.running)

func _on_reset_requested() -> void:
	clock.stop_clock()
	clock.reset()
	sequencer.rebuild_now(0)
	ui.update_variation_display("Main: Reset")
	ui.update_clock_display(clock.current_step, clock.loop_index, clock.bpm, clock.running)
	_refresh_metrics()

func _on_bpm_changed(new_bpm: int) -> void:
	clock.set_bpm(new_bpm)
	ui.update_clock_display(clock.current_step, clock.loop_index, clock.bpm, clock.running)

func _on_auto_variation_changed(enabled: bool) -> void:
	sequencer.auto_variation_enabled = enabled
	sequencer.rebuild_now(clock.loop_index)
	_refresh_metrics()

func _on_layer_active_changed(layer_id: String, enabled: bool) -> void:
	if not _layers.has(layer_id):
		return
	(_layers[layer_id] as InstrumentLayer).set_active(enabled)
	ui.set_layer_state(layer_id, enabled, (_layers[layer_id] as InstrumentLayer).is_muted)
	_refresh_metrics()

func _on_layer_muted_changed(layer_id: String, muted: bool) -> void:
	if not _layers.has(layer_id):
		return
	(_layers[layer_id] as InstrumentLayer).set_muted(muted)
	ui.set_layer_state(layer_id, (_layers[layer_id] as InstrumentLayer).is_active, muted)

func _on_upgrade_changed(upgrade_id: String, enabled: bool) -> void:
	ui.update_variation_display("Main: Upgrade %s -> %s" % [upgrade_id, "ON" if enabled else "OFF"])
	upgrade_system.set_upgrade_enabled(upgrade_id, enabled)

func _on_track_selected(track_name: String) -> void:
	_selected_track = track_name
	ui.set_track_pattern(track_name, sequencer.get_pattern(track_name))

func _on_step_toggled(track_name: String, step_index: int, enabled: bool) -> void:
	sequencer.set_step(track_name, step_index, enabled)
	sequencer.rebuild_now(clock.loop_index)
	ui.update_variation_display("Main: %s step %d -> %s" % [track_name, step_index + 1, "ON" if enabled else "OFF"])
	_refresh_metrics()

func _on_battle_requested(boss_id: String) -> void:
	_refresh_metrics()
	var result = battle_system.evaluate_battle(
		boss_id,
		_current_metrics,
		sequencer.get_active_effective_patterns(),
		upgrade_system.get_enabled_map()
	)
	ui.update_battle_display(result)

func _on_random_build_requested() -> void:
	ui.update_variation_display("Main: Random Build")
	_apply_random_build()

func _on_best_build_search_requested() -> void:
	ui.update_variation_display("Main: Auto Test")
	var best = _search_best_build(36)
	ui.update_battle_display({
		"boss_name": "Auto Test",
		"victory": int(best.get("wins", 0)) >= 3,
		"battle_score": int(best.get("avg_battle", 0)),
		"reason": "Mejor build: %d/5 victorias | score %d" % [int(best.get("wins", 0)), int(best.get("score", 0))],
	})

func _on_manual_variation_requested() -> void:
	var description = sequencer.apply_variation_to_base()
	sequencer.rebuild_now(clock.loop_index)
	ui.update_variation_display("Main: " + description)
	ui.set_track_pattern(_selected_track, sequencer.get_pattern(_selected_track))
	_refresh_metrics()

func _on_run_new_requested() -> void:
	run_manager.start_new_run()
	ui.update_variation_display("Run iniciada: 1-1 base, 1-2 decision, 1-3 decision, 1-4 miniboss.")

func _on_run_choice_selected(index: int) -> void:
	run_manager.select_choice(index)

func _on_run_enter_requested() -> void:
	var action: Dictionary = run_manager.enter_selected_node()
	_handle_run_action(action)

func _on_run_reward_selected(index: int) -> void:
	var result: Dictionary = run_manager.select_reward(index)
	var status: String = String(result.get("status", ""))
	match status:
		"ok":
			_apply_external_reward(result.get("external_reward", {}))
			sequencer.rebuild_now(clock.loop_index)
			_refresh_metrics()
			ui.set_track_pattern(_selected_track, sequencer.get_pattern(_selected_track))
		"insufficient_funds":
			ui.update_variation_display("Run: coins insuficientes")
		_:
			ui.update_variation_display("Run: recompensa no disponible")

func _on_run_started(_state: Dictionary) -> void:
	_card_library.set_seed(int(_state.get("seed", 0)))
	clock.stop_clock()
	clock.reset()
	ui.update_clock_display(clock.current_step, clock.loop_index, clock.bpm, clock.running)
	_reset_cards()
	_reset_musical_build_for_run()
	_sync_run_ui()

func _on_run_updated(_state: Dictionary) -> void:
	_sync_run_ui()

func _on_run_reward_offered(_rewards: Array) -> void:
	_sync_run_ui()

func _on_run_ended(victory: bool, reason: String) -> void:
	clock.stop_clock()
	ui.update_clock_display(clock.current_step, clock.loop_index, clock.bpm, clock.running)
	ui.update_battle_display({
		"boss_name": "Run",
		"victory": victory,
		"battle_score": int(_current_metrics.get("score", 0)),
		"reason": reason,
	})
	_sync_run_ui()

func _on_card_play_requested(index: int) -> void:
	if index < 0 or index >= _active_cards.size():
		return
	var card_data: Dictionary = (_active_cards[index] as Dictionary).duplicate(true)
	_active_cards.remove_at(index)
	_apply_active_card_effect(card_data)
	sequencer.rebuild_now(clock.loop_index)
	_refresh_metrics()
	ui.set_track_pattern(_selected_track, sequencer.get_pattern(_selected_track))
	_sync_card_ui()

func _on_card_draft_pick_requested(index: int) -> void:
	if index < 0 or index >= _pending_card_draft.size():
		return
	var card_data: Dictionary = (_pending_card_draft[index] as Dictionary).duplicate(true)
	_pending_card_draft.clear()
	_apply_card_gain(card_data)
	_sync_card_ui()
	ui.show_card_draft([])

func _handle_run_action(action: Dictionary) -> void:
	var status: String = String(action.get("status", ""))
	match status:
		"battle":
			_resolve_run_battle(action.get("node", {}))
		"base_choice":
			if _preview_tween != null and _preview_tween.is_running():
				_preview_tween.kill()
			_apply_base_profile(String(action.get("base_profile_id", "")))
			clock.start_clock(true)
			ui.update_clock_display(clock.current_step, clock.loop_index, clock.bpm, clock.running)
			ui.update_battle_display({
				"boss_name": "Base",
				"victory": true,
				"battle_score": int(_current_metrics.get("score", 0)),
				"reason": String(action.get("summary", "Base elegida")),
			})
		"instant":
			ui.update_battle_display({
				"boss_name": "Nodo",
				"victory": true,
				"battle_score": int(_current_metrics.get("score", 0)),
				"reason": String(action.get("summary", "Nodo resuelto")),
			})
		"awaiting_reward":
			ui.update_variation_display("Run: primero elige una recompensa")
		"inactive":
			ui.update_variation_display("Run inactiva. Pulsa New Run")
		_:
			ui.update_variation_display("Run: no hay nodo seleccionado")

func _resolve_run_battle(node: Dictionary) -> void:
	_refresh_metrics()
	var node_type: String = String(node.get("type", "combat"))
	var score_now: int = int(_current_metrics.get("score", 0))
	var is_boss_like: bool = node_type == "boss" or node_type == "miniboss"
	var card_score_bonus: int = _compute_card_score_bonus(is_boss_like)
	var score_with_cards: int = score_now + card_score_bonus
	var battle_result: Dictionary = _evaluate_run_enemy(node, score_with_cards)
	var victory: bool = bool(battle_result.get("victory", false))
	var reason: String = String(battle_result.get("reason", ""))
	if card_score_bonus > 0:
		reason += " | Bonus cartas +%d" % card_score_bonus
	var battle_label: String = String(node.get("label", String(battle_result.get("boss_name", "Enemy"))))

	ui.update_battle_display({
		"boss_name": battle_label,
		"victory": victory,
		"battle_score": int(battle_result.get("battle_score", 0)),
		"reason": reason,
	})

	run_manager.resolve_battle_result(
		node,
		victory,
		int(battle_result.get("battle_score", 0)),
		score_with_cards,
		reason
	)
	_temp_score_bonus = 0

func _evaluate_run_enemy(node: Dictionary, effective_score: int) -> Dictionary:
	var node_type: String = String(node.get("type", "combat"))
	var required_score: int = int(node.get("required_score", 0))
	var score_ok: bool = effective_score >= required_score
	var boss_name: String = String(node.get("enemy_name", node.get("label", "Enemy")))

	match node_type:
		"first_enemy":
			var track_name: String = String(node.get("goal_track", node.get("required_track", "kick")))
			var track_label: String = String(node.get("required_track_label", track_name.capitalize()))
			var min_hits: int = int(node.get("goal_min_hits", node.get("min_hits", 6)))
			var hits: int = _count_track_hits(track_name)
			var hits_ok: bool = hits >= min_hits
			var victory_first: bool = score_ok and hits_ok
			var reason_first: String = "Checklist: Hits %d/%d en %s | Score %d/%d." % [
				hits, min_hits, track_label, effective_score, required_score
			]
			return {
				"boss_name": boss_name,
				"victory": victory_first,
				"battle_score": effective_score + hits * 5,
				"reason": reason_first,
			}
		"combat":
			var reason_combat: String = "Checklist: Score %d/%d." % [effective_score, required_score]
			return {
				"boss_name": boss_name,
				"victory": score_ok,
				"battle_score": effective_score,
				"reason": reason_combat,
			}
		"elite":
			var min_sync: float = float(node.get("goal_min_syncopation", 0.18))
			var sync_now: float = float(_current_metrics.get("syncopation", 0.0))
			var sync_ok: bool = sync_now >= min_sync
			var victory_elite: bool = score_ok and sync_ok
			var reason_elite: String = "Checklist: Score %d/%d | Sync %.2f/%.2f." % [
				effective_score, required_score, sync_now, min_sync
			]
			return {
				"boss_name": boss_name,
				"victory": victory_elite,
				"battle_score": effective_score + int(round(sync_now * 100.0)),
				"reason": reason_elite,
			}
		"miniboss":
			var min_sync_mb: float = float(node.get("goal_min_syncopation", 0.22))
			var min_groove_mb: float = float(node.get("goal_min_groove", 0.45))
			var sync_mb: float = float(_current_metrics.get("syncopation", 0.0))
			var groove_mb: float = float(_current_metrics.get("groove", 0.0))
			var sync_mb_ok: bool = sync_mb >= min_sync_mb
			var groove_mb_ok: bool = groove_mb >= min_groove_mb
			var victory_mb: bool = score_ok and sync_mb_ok and groove_mb_ok
			var reason_mb: String = "Checklist: Score %d/%d | Sync %.2f/%.2f | Groove %.2f/%.2f." % [
				effective_score, required_score, sync_mb, min_sync_mb, groove_mb, min_groove_mb
			]
			return {
				"boss_name": boss_name,
				"victory": victory_mb,
				"battle_score": effective_score + int(round(sync_mb * 100.0)) + int(round(groove_mb * 100.0)),
				"reason": reason_mb,
			}
		_:
			var boss_id: String = String(node.get("boss_id", "groove_test"))
			var fallback_result: Dictionary = battle_system.evaluate_battle(
				boss_id,
				_current_metrics,
				sequencer.get_active_effective_patterns(),
				upgrade_system.get_enabled_map()
			)
			var fallback_win: bool = bool(fallback_result.get("victory", false)) and score_ok
			var fallback_reason: String = "Checklist: Score %d/%d | Boss rule %s." % [
				effective_score, required_score, "OK" if bool(fallback_result.get("victory", false)) else "FAIL"
			]
			return {
				"boss_name": String(fallback_result.get("boss_name", boss_name)),
				"victory": fallback_win,
				"battle_score": int(fallback_result.get("battle_score", effective_score)),
				"reason": fallback_reason,
			}

func _count_track_hits(track_name: String) -> int:
	var patterns: Dictionary = sequencer.get_active_effective_patterns()
	if not patterns.has(track_name):
		return 0
	var track_pattern: Variant = patterns[track_name]
	if typeof(track_pattern) != TYPE_ARRAY:
		return 0
	var pattern_array: Array = track_pattern as Array
	var hits: int = 0
	for step_value in pattern_array:
		if int(step_value) == 1:
			hits += 1
	return hits

func _apply_external_reward(reward: Dictionary) -> void:
	if reward.is_empty():
		return

	var reward_type: String = String(reward.get("type", ""))
	match reward_type:
		"card_draft":
			_offer_card_draft(reward)
		"upgrade_random":
			_grant_random_upgrade()
		"variation":
			var description = sequencer.apply_variation_to_base()
			ui.update_variation_display("Reward: " + description)
		"randomize_track":
			_randomize_one_track()
		_:
			ui.update_variation_display("Reward: %s" % String(reward.get("label", "Aplicada")))

func _offer_card_draft(reward: Dictionary) -> void:
	var count: int = int(reward.get("count", 3))
	var kind_filter: Array[String] = ["passive", "active"]
	if reward.has("kind_filter"):
		kind_filter.clear()
		for kind in reward["kind_filter"]:
			kind_filter.append(String(kind))

	_pending_card_draft = _card_library.random_draft(count, kind_filter)
	ui.show_card_draft(_pending_card_draft)
	ui.update_variation_display("Draft de cartas: elige 1")

func _apply_card_gain(card_data: Dictionary) -> void:
	var card_kind: String = String(card_data.get("card_kind", "passive"))
	if card_kind == "active":
		_active_cards.append(card_data.duplicate(true))
		while _active_cards.size() > _get_max_active_hand_size():
			_active_cards.remove_at(0)
	else:
		_passive_cards.append(card_data.duplicate(true))
		_apply_passive_card_effect(card_data)

	ui.update_variation_display("Carta obtenida: %s" % String(card_data.get("name", "Carta")))

func _apply_passive_card_effect(card_data: Dictionary) -> void:
	var payload: Dictionary = card_data.get("payload", {})
	var effect: String = String(payload.get("effect", ""))
	match effect:
		"enable_upgrade":
			var upgrade_id: String = String(payload.get("upgrade_id", ""))
			if not upgrade_id.is_empty():
				upgrade_system.set_upgrade_enabled(upgrade_id, true)
		"grant_coins":
			run_manager.add_coins(int(payload.get("amount", 0)))
		"heal":
			run_manager.heal(int(payload.get("amount", 0)))
		_:
			pass

func _apply_active_card_effect(card_data: Dictionary) -> void:
	var payload: Dictionary = card_data.get("payload", {})
	var effect: String = String(payload.get("effect", ""))
	match effect:
		"variation":
			var description = sequencer.apply_variation_to_base()
			ui.update_variation_display("Activa: " + description)
		"reforge_track":
			var track_name: String = String(payload.get("track", "kick"))
			sequencer.set_pattern(track_name, _random_pattern_for_track(track_name))
			ui.update_variation_display("Activa: reforge %s" % track_name)
		"reroll_all":
			sequencer.randomize_base_patterns()
			ui.update_variation_display("Activa: random build base")
		"temp_score_bonus":
			_temp_score_bonus += int(payload.get("amount", 0))
			ui.update_variation_display("Activa: +%d score temporal" % int(payload.get("amount", 0)))
		"grant_coins":
			run_manager.add_coins(int(payload.get("amount", 0)))
			ui.update_variation_display("Activa: +%d coins" % int(payload.get("amount", 0)))
		_:
			ui.update_variation_display("Activa usada: %s" % String(card_data.get("name", "Carta")))

func _get_max_active_hand_size() -> int:
	var bonus: int = 0
	for card_data in _passive_cards:
		var payload: Dictionary = (card_data as Dictionary).get("payload", {})
		if String(payload.get("effect", "")) == "active_hand_bonus":
			bonus += int(payload.get("amount", 0))
	return _base_active_hand_size + bonus

func _compute_card_score_bonus(is_boss_node: bool) -> int:
	var bonus: int = _temp_score_bonus
	for card_data in _passive_cards:
		var payload: Dictionary = (card_data as Dictionary).get("payload", {})
		var effect: String = String(payload.get("effect", ""))
		if effect == "score_bonus":
			bonus += int(payload.get("amount", 0))
		elif effect == "boss_score_bonus" and is_boss_node:
			bonus += int(payload.get("amount", 0))
	return bonus

func _reset_cards() -> void:
	_passive_cards.clear()
	_active_cards.clear()
	_pending_card_draft.clear()
	_temp_score_bonus = 0
	_sync_card_ui()

func _sync_card_ui() -> void:
	ui.update_card_state(_passive_cards, _active_cards)
	if _pending_card_draft.is_empty():
		ui.show_card_draft([])

func _grant_random_upgrade() -> void:
	var enabled_map: Dictionary = upgrade_system.get_enabled_map()
	var disabled: Array = []
	for upgrade_id in upgrade_system.get_upgrade_ids():
		if not bool(enabled_map.get(upgrade_id, false)):
			disabled.append(upgrade_id)
	if disabled.is_empty():
		ui.update_variation_display("Reward: no hay upgrades por desbloquear")
		return
	var chosen_id: String = String(disabled[_rng.randi_range(0, disabled.size() - 1)])
	upgrade_system.set_upgrade_enabled(chosen_id, true)
	ui.update_variation_display("Reward: upgrade %s" % chosen_id)

func _randomize_one_track() -> void:
	var track_names: Array[String] = sequencer.get_track_names()
	if track_names.is_empty():
		return
	var track: String = track_names[_rng.randi_range(0, track_names.size() - 1)]
	sequencer.set_pattern(track, _random_pattern_for_track(track))
	ui.update_variation_display("Reward: reforge de %s" % track)

func _sync_run_ui() -> void:
	var run_state: Dictionary = run_manager.get_state()
	ui.set_studio_unlocked(not String(run_state.get("base_profile_id", "")).is_empty())
	ui.update_run_status(run_state)
	ui.update_run_choices(
		run_state.get("current_choices", []),
		int(run_state.get("selected_choice_index", -1)),
		run_state.get("pending_node", {})
	)
	ui.show_reward_choices(
		run_state.get("pending_rewards", []),
		int(run_state.get("coins", 0))
	)
	ui.update_run_combat_hint(_build_run_combat_hint(run_state))
	_update_focus_audio(run_state)
	_sync_card_ui()

func _build_run_combat_hint(run_state: Dictionary) -> String:
	var pending_variant: Variant = run_state.get("pending_node", {})
	if typeof(pending_variant) != TYPE_DICTIONARY:
		return "Selecciona una carta para ver los requisitos de pelea."
	var pending_node: Dictionary = pending_variant as Dictionary
	if pending_node.is_empty():
		return "Selecciona una carta para ver los requisitos de pelea."

	var node_type: String = String(pending_node.get("type", ""))
	if node_type == "base_seed":
		return "Paso 1: elige una base. Luego se desbloquean peleas por checklist."
	if not _is_run_battle_node(node_type):
		return "Nodo de utilidad: no hay pelea en esta carta."

	var score_now: int = int(_current_metrics.get("score", 0))
	var is_boss_like: bool = node_type == "boss" or node_type == "miniboss"
	var card_bonus: int = _compute_card_score_bonus(is_boss_like)
	var effective_score: int = score_now + card_bonus
	var preview: Dictionary = _evaluate_run_enemy(pending_node, effective_score)
	var win_text: String = "GANAS" if bool(preview.get("victory", false)) else "PIERDES"
	return "Si peleas ahora: %s | %s" % [win_text, String(preview.get("reason", ""))]

func _is_run_battle_node(node_type: String) -> bool:
	return node_type == "first_enemy" or node_type == "combat" or node_type == "elite" or node_type == "miniboss" or node_type == "boss"

func _update_focus_audio(run_state: Dictionary) -> void:
	var should_duck: bool = false
	if _decision_ducking_enabled:
		var has_base: bool = not String(run_state.get("base_profile_id", "")).is_empty()
		var awaiting_reward: bool = bool(run_state.get("awaiting_reward", false))
		should_duck = has_base and awaiting_reward
	_apply_master_volume(_decision_duck_factor if should_duck else 1.0)

func _on_base_card_hovered(profile_id: String) -> void:
	if profile_id.is_empty():
		return
	_play_base_preview(profile_id)

func _on_rhythm_preset_requested(preset_id: String) -> void:
	_apply_rhythm_preset(preset_id)

func _apply_rhythm_preset(preset_id: String) -> void:
	var run_state: Dictionary = run_manager.get_state()
	var base_profile_id: String = String(run_state.get("base_profile_id", ""))
	if base_profile_id.is_empty():
		ui.update_variation_display("Primero elige una base para aplicar ritmo.")
		return
	var target_track: String = _track_for_base_profile(base_profile_id)
	if target_track.is_empty():
		target_track = _selected_track

	var rhythm_pattern: Array = []
	match preset_id:
		"straight":
			rhythm_pattern = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
		"half_time":
			rhythm_pattern = [1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0]
		"syncopated":
			rhythm_pattern = [1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 0]
		_:
			return

	sequencer.set_pattern(target_track, rhythm_pattern)

	sequencer.rebuild_now(clock.loop_index)
	ui.set_track_pattern(_selected_track, sequencer.get_pattern(_selected_track))
	_refresh_metrics()
	ui.update_variation_display("Rhythm preset aplicado en %s: %s" % [target_track, preset_id])

func _track_for_base_profile(profile_id: String) -> String:
	match profile_id:
		"drum_seed":
			return "kick"
		"trumpet_seed":
			return "melody"
		"bass_seed":
			return "bass"
		_:
			return ""

func _play_base_preview(profile_id: String) -> void:
	var profiles: Dictionary = _base_profiles()
	if not profiles.has(profile_id):
		return
	var profile_variant: Variant = profiles[profile_id]
	if typeof(profile_variant) == TYPE_DICTIONARY:
		var profile: Dictionary = profile_variant as Dictionary
		var bass_seq: Variant = profile.get("bass_sequence", [])
		if typeof(bass_seq) == TYPE_ARRAY:
			_set_bass_freq_sequence(bass_seq as Array)
		var melody_seq: Variant = profile.get("melody_sequence", [])
		if typeof(melody_seq) == TYPE_ARRAY:
			_set_melody_freq_sequence(melody_seq as Array)

	if _preview_tween != null and _preview_tween.is_running():
		_preview_tween.kill()

	var events: Array = _base_preview_events(profile_id)
	if events.is_empty():
		return

	_preview_tween = create_tween()
	var timeline: float = 0.0
	for event_value in events:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event_data: Dictionary = event_value
		var t: float = float(event_data.get("t", 0.0))
		var wait: float = max(0.0, t - timeline)
		timeline = t
		_preview_tween.tween_interval(wait)
		_preview_tween.tween_callback(
			Callable(self, "_trigger_preview_track").bind(
				String(event_data.get("track", "kick")),
				int(event_data.get("step", 0)),
				float(event_data.get("velocity", 0.6))
			)
		)

func _base_preview_events(profile_id: String) -> Array:
	match profile_id:
		"drum_seed":
			return [
				{"t": 0.00, "track": "kick", "step": 0, "velocity": 0.86},
				{"t": 0.18, "track": "kick", "step": 4, "velocity": 0.86},
				{"t": 0.36, "track": "kick", "step": 8, "velocity": 0.86},
				{"t": 0.54, "track": "kick", "step": 12, "velocity": 0.86},
			]
		"trumpet_seed":
			return [
				{"t": 0.00, "track": "melody", "step": 0, "velocity": 0.52},
				{"t": 0.16, "track": "melody", "step": 5, "velocity": 0.52},
				{"t": 0.32, "track": "melody", "step": 8, "velocity": 0.52},
				{"t": 0.48, "track": "melody", "step": 13, "velocity": 0.52},
			]
		"bass_seed":
			return [
				{"t": 0.00, "track": "bass", "step": 0, "velocity": 0.62},
				{"t": 0.18, "track": "bass", "step": 4, "velocity": 0.62},
				{"t": 0.36, "track": "bass", "step": 8, "velocity": 0.62},
				{"t": 0.54, "track": "bass", "step": 12, "velocity": 0.62},
			]
		_:
			return []

func _trigger_preview_track(track_name: String, step_index: int, velocity: float) -> void:
	var layer_id: String = String(_track_to_layer.get(track_name, ""))
	if layer_id.is_empty() or not _layers.has(layer_id):
		return
	var layer: InstrumentLayer = _layers[layer_id]
	layer.trigger_track(track_name, step_index, velocity)

func _on_master_volume_changed(volume_linear: float) -> void:
	_master_volume_linear = clamp(volume_linear, 0.0, 1.0)
	if _master_muted and _master_volume_linear > 0.0:
		_master_muted = false
	ui.set_master_volume(_master_volume_linear, _master_muted)
	_apply_master_volume()

func _on_master_mute_toggled(muted: bool) -> void:
	_master_muted = muted
	ui.set_master_volume(_master_volume_linear, _master_muted)
	_apply_master_volume()

func _apply_master_volume(extra_gain: float = 1.0) -> void:
	var bus_index: int = AudioServer.get_bus_index("Master")
	if bus_index < 0:
		return
	if _master_muted:
		AudioServer.set_bus_mute(bus_index, true)
		return
	AudioServer.set_bus_mute(bus_index, false)
	var linear_value: float = clamp(_master_volume_linear * extra_gain, 0.0001, 1.0)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear_value))

func _reset_musical_build_for_run() -> void:
	# Each run starts from a clean musical state before selecting 1-1 base.
	upgrade_system.disable_all()
	sequencer.load_base_patterns(_default_patterns(), true)
	_set_bass_freq_sequence(_default_bass_sequence())
	_set_melody_freq_sequence(_default_melody_sequence())
	clock.set_bpm(DEFAULT_RUN_BPM)

	for layer_id in _layers.keys():
		var layer: InstrumentLayer = _layers[layer_id]
		layer.set_active(true)
		layer.set_muted(false)
		ui.set_layer_state(layer_id, true, false)

	var enabled_map: Dictionary = upgrade_system.get_enabled_map()
	for upgrade_id in enabled_map.keys():
		ui.set_upgrade_state(upgrade_id, bool(enabled_map[upgrade_id]))

	sequencer.rebuild_now(clock.loop_index)
	ui.update_clock_display(clock.current_step, clock.loop_index, clock.bpm, clock.running)
	ui.set_track_pattern(_selected_track, sequencer.get_pattern(_selected_track))
	_refresh_metrics()

func _apply_base_profile(profile_id: String) -> void:
	var profiles: Dictionary = _base_profiles()
	if not profiles.has(profile_id):
		ui.update_variation_display("Base no encontrada: %s" % profile_id)
		return

	var profile_value: Variant = profiles[profile_id]
	if typeof(profile_value) != TYPE_DICTIONARY:
		ui.update_variation_display("Base invalida: %s" % profile_id)
		return
	var profile: Dictionary = profile_value as Dictionary

	var patterns_value: Variant = profile.get("patterns", {})
	if typeof(patterns_value) == TYPE_DICTIONARY:
		var base_patterns: Dictionary = patterns_value as Dictionary
		sequencer.load_base_patterns(base_patterns, true)

	var primary_track: String = String(profile.get("primary_track", _selected_track))
	if not primary_track.is_empty():
		_selected_track = primary_track
		ui.select_track(_selected_track)

	var bpm_value: Variant = profile.get("bpm", DEFAULT_RUN_BPM)
	clock.set_bpm(int(bpm_value))

	var bass_seq_value: Variant = profile.get("bass_sequence", [])
	if typeof(bass_seq_value) == TYPE_ARRAY:
		var bass_seq: Array = bass_seq_value as Array
		_set_bass_freq_sequence(bass_seq)

	var melody_seq_value: Variant = profile.get("melody_sequence", [])
	if typeof(melody_seq_value) == TYPE_ARRAY:
		var melody_seq: Array = melody_seq_value as Array
		_set_melody_freq_sequence(melody_seq)

	var active_layers_value: Variant = profile.get("active_layers", [])
	if typeof(active_layers_value) == TYPE_ARRAY:
		var active_layers_raw: Array = active_layers_value as Array
		var active_layer_ids: Array[String] = []
		for layer_variant in active_layers_raw:
			active_layer_ids.append(String(layer_variant))
		for layer_id in _layers.keys():
			var layer: InstrumentLayer = _layers[layer_id]
			var enabled: bool = active_layer_ids.has(layer_id)
			layer.set_active(enabled)
			layer.set_muted(false)
			ui.set_layer_state(layer_id, enabled, false)

	var starter_map: Dictionary = {}
	for upgrade_id in upgrade_system.get_upgrade_ids():
		starter_map[upgrade_id] = false

	var upgrades_value: Variant = profile.get("starter_upgrades", [])
	if typeof(upgrades_value) == TYPE_ARRAY:
		for upgrade_variant in upgrades_value:
			var upgrade_id: String = String(upgrade_variant)
			if starter_map.has(upgrade_id):
				starter_map[upgrade_id] = true

	upgrade_system.load_enabled_map(starter_map, true)
	sequencer.rebuild_now(clock.loop_index)
	ui.update_clock_display(clock.current_step, clock.loop_index, clock.bpm, clock.running)
	ui.set_track_pattern(_selected_track, sequencer.get_pattern(_selected_track))
	_refresh_metrics()

	var label: String = String(profile.get("label", profile_id))
	var summary: String = String(profile.get("summary", ""))
	ui.update_variation_display("Base activa: %s | %s" % [label, summary])

func _base_profiles() -> Dictionary:
	return {
		"drum_seed": {
			"label": "Drum Pulse",
			"summary": "Solo kick basico para arrancar.",
			"primary_track": "kick",
			"active_layers": ["drums"],
			"bpm": 108,
			"patterns": {
				"kick": [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
				"snare": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
				"hat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
				"bass": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
				"melody": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
				"fx": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
			},
			"bass_sequence": _default_bass_sequence(),
			"melody_sequence": _default_melody_sequence(),
			"starter_upgrades": [],
		},
		"trumpet_seed": {
			"label": "Brass Call",
			"summary": "Solo linea de trompeta sintetica.",
			"primary_track": "melody",
			"active_layers": ["melody"],
			"bpm": 102,
			"patterns": {
				"kick": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
				"snare": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
				"hat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
				"bass": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
				"melody": [1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0],
				"fx": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
			},
			"bass_sequence": _default_bass_sequence(),
			"melody_sequence": [330.0, 330.0, 370.0, 392.0, 440.0, 392.0, 370.0, 330.0, 294.0, 330.0, 370.0, 392.0, 440.0, 392.0, 370.0, 330.0],
			"starter_upgrades": [],
		},
		"bass_seed": {
			"label": "Bass March",
			"summary": "Solo bajo en pulso simple.",
			"primary_track": "bass",
			"active_layers": ["bass"],
			"bpm": 100,
			"patterns": {
				"kick": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
				"snare": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
				"hat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
				"bass": [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
				"melody": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
				"fx": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
			},
			"bass_sequence": [49.0, 49.0, 49.0, 55.0, 43.6, 43.6, 49.0, 55.0, 49.0, 49.0, 55.0, 58.2, 49.0, 49.0, 43.6, 49.0],
			"melody_sequence": _default_melody_sequence(),
			"starter_upgrades": [],
		},
	}

func _set_bass_freq_sequence(sequence: Array) -> void:
	if not bass_layer.tracks.has("bass"):
		return
	var bass_cfg: Dictionary = (bass_layer.tracks["bass"] as Dictionary).duplicate(true)
	bass_cfg["freq_sequence"] = sequence.duplicate()
	bass_layer.tracks["bass"] = bass_cfg

func _set_melody_freq_sequence(sequence: Array) -> void:
	if not melody_layer.tracks.has("melody"):
		return
	var melody_cfg: Dictionary = (melody_layer.tracks["melody"] as Dictionary).duplicate(true)
	melody_cfg["freq_sequence"] = sequence.duplicate()
	melody_layer.tracks["melody"] = melody_cfg

func _default_bass_sequence() -> Array:
	return [55.0, 55.0, 65.4, 55.0, 73.4, 65.4, 55.0, 49.0, 55.0, 65.4, 73.4, 55.0, 49.0, 55.0, 65.4, 55.0]

func _default_melody_sequence() -> Array:
	return [220.0, 247.0, 262.0, 294.0, 330.0, 294.0, 262.0, 247.0, 220.0, 247.0, 262.0, 330.0, 349.0, 330.0, 294.0, 262.0]

func _refresh_metrics() -> void:
	_current_metrics = score_analyzer.analyze(
		sequencer.get_active_effective_patterns(),
		STEPS_PER_LOOP,
		upgrade_system.get_enabled_map()
	)
	ui.update_score_display(_current_metrics)
	var run_state: Dictionary = run_manager.get_state()
	if bool(run_state.get("active", false)):
		ui.update_run_combat_hint(_build_run_combat_hint(run_state))

func _apply_random_build() -> void:
	var state = _random_build_state()
	_apply_build_state(state, true, true)
	sequencer.rebuild_now(clock.loop_index)
	ui.set_track_pattern(_selected_track, sequencer.get_pattern(_selected_track))
	_refresh_metrics()
	ui.update_battle_display({
		"boss_name": "Build Aleatoria",
		"victory": true,
		"battle_score": int(_current_metrics.get("score", 0)),
		"reason": "Se genero una combinacion aleatoria de patrones y upgrades.",
	})

func _search_best_build(iterations: int) -> Dictionary:
	var original_state = _capture_build_state()
	var best_state = original_state.duplicate(true)
	var best_value = -1000000.0
	var best_summary = {
		"wins": 0,
		"avg_battle": 0,
		"score": 0,
	}

	for i in range(iterations):
		var candidate = _random_build_state()
		_apply_build_state(candidate, false, false)
		sequencer.rebuild_now(i)

		var metrics = score_analyzer.analyze(
			sequencer.get_active_effective_patterns(),
			STEPS_PER_LOOP,
			upgrade_system.get_enabled_map()
		)
		var summary = _evaluate_current_build(metrics)
		var value = float(summary.get("wins", 0)) * 1000.0 + float(summary.get("avg_battle", 0)) + float(summary.get("score", 0)) * 2.0

		if value > best_value:
			best_value = value
			best_state = _capture_build_state()
			best_summary = summary

	_apply_build_state(best_state, true, true)
	sequencer.rebuild_now(clock.loop_index)
	ui.set_track_pattern(_selected_track, sequencer.get_pattern(_selected_track))
	_refresh_metrics()

	return best_summary

func _evaluate_current_build(metrics: Dictionary) -> Dictionary:
	var wins = 0
	var battle_total = 0
	for boss_id in battle_system.get_boss_ids():
		var result = battle_system.evaluate_battle(
			boss_id,
			metrics,
			sequencer.get_active_effective_patterns(),
			upgrade_system.get_enabled_map()
		)
		if bool(result.get("victory", false)):
			wins += 1
		battle_total += int(result.get("battle_score", 0))

	var avg_battle = int(round(float(battle_total) / max(1.0, float(battle_system.get_boss_ids().size()))))
	return {
		"wins": wins,
		"avg_battle": avg_battle,
		"score": int(metrics.get("score", 0)),
	}

func _capture_build_state() -> Dictionary:
	return {
		"patterns": sequencer.get_base_patterns(),
		"upgrades": upgrade_system.get_enabled_map(),
		"layers": _get_layer_states(),
	}

func _apply_build_state(state: Dictionary, emit_signals: bool, update_ui: bool) -> void:
	sequencer.load_base_patterns(state.get("patterns", {}), emit_signals)
	upgrade_system.load_enabled_map(state.get("upgrades", {}), emit_signals)

	var layer_states: Dictionary = state.get("layers", {})
	for layer_id in _layers.keys():
		var layer: InstrumentLayer = _layers[layer_id]
		var info: Dictionary = layer_states.get(layer_id, {"active": true, "muted": false})
		layer.set_active(bool(info.get("active", true)))
		layer.set_muted(bool(info.get("muted", false)))
		if update_ui:
			ui.set_layer_state(layer_id, layer.is_active, layer.is_muted)

	if update_ui:
		var upgrade_map: Dictionary = upgrade_system.get_enabled_map()
		for upgrade_id in upgrade_map.keys():
			ui.set_upgrade_state(upgrade_id, bool(upgrade_map[upgrade_id]))

func _random_build_state() -> Dictionary:
	var patterns: Dictionary = {}
	for track_name in sequencer.get_track_names():
		patterns[track_name] = _random_pattern_for_track(track_name)

	var upgrade_map: Dictionary = {}
	for upgrade_id in upgrade_system.get_upgrade_ids():
		upgrade_map[upgrade_id] = _rng.randf() < 0.42

	var layer_states: Dictionary = {}
	for layer_id in _layers.keys():
		var active = true if layer_id == "drums" else (_rng.randf() > 0.12)
		layer_states[layer_id] = {
			"active": active,
			"muted": active and _rng.randf() < 0.12,
		}

	return {
		"patterns": patterns,
		"upgrades": upgrade_map,
		"layers": layer_states,
	}

func _random_pattern_for_track(track_name: String) -> Array:
	var target_density = {
		"kick": 0.26,
		"snare": 0.17,
		"hat": 0.75,
		"bass": 0.30,
		"melody": 0.24,
		"fx": 0.12,
	}
	var pattern: Array = []
	pattern.resize(STEPS_PER_LOOP)
	var chance = float(target_density.get(track_name, 0.25))
	for i in range(STEPS_PER_LOOP):
		pattern[i] = 1 if _rng.randf() < chance else 0
	if not pattern.has(1):
		pattern[_rng.randi_range(0, STEPS_PER_LOOP - 1)] = 1
	return pattern

func _layer_display_names() -> Dictionary:
	var names: Dictionary = {}
	for layer_id in _layers.keys():
		names[layer_id] = (_layers[layer_id] as InstrumentLayer).display_name
	return names

func _get_layer_states() -> Dictionary:
	var states: Dictionary = {}
	for layer_id in _layers.keys():
		var layer: InstrumentLayer = _layers[layer_id]
		states[layer_id] = {
			"active": layer.is_active,
			"muted": layer.is_muted,
		}
	return states

func _default_patterns() -> Dictionary:
	return {
		"kick": [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
		"snare": [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0],
		"hat": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
		"bass": [1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0],
		"melody": [1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0],
		"fx": [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1],
	}
