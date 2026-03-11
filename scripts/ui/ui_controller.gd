extends Control
class_name UIController

signal start_requested
signal stop_requested
signal reset_requested
signal bpm_changed(new_bpm: int)
signal auto_variation_changed(enabled: bool)
signal random_build_requested
signal best_build_search_requested
signal manual_variation_requested
signal layer_active_changed(layer_id: String, enabled: bool)
signal layer_muted_changed(layer_id: String, muted: bool)
signal upgrade_changed(upgrade_id: String, enabled: bool)
signal track_selected(track_name: String)
signal step_toggled(track_name: String, step_index: int, enabled: bool)
signal battle_requested(boss_id: String)
signal run_new_requested
signal run_choice_selected(index: int)
signal run_enter_requested
signal run_reward_selected(index: int)
signal card_play_requested(index: int)
signal card_draft_pick_requested(index: int)

const SCREEN_HOME: String = "home"
const SCREEN_RUN: String = "run"
const SCREEN_STUDIO: String = "studio"
const SCREEN_BATTLE: String = "battle"

var _clock_label: Label
var _score_label: Label
var _battle_label: Label
var _variation_label: Label
var _interaction_label: Label

var _run_status_label: Label
var _run_node_label: Label
var _card_passive_label: Label

var _track_selector: OptionButton
var _boss_selector: OptionButton
var _run_choice_selector: OptionButton

var _step_container: HBoxContainer
var _layer_rows: VBoxContainer
var _upgrade_rows: VBoxContainer

var _bpm_spinbox: SpinBox
var _auto_variation_check: CheckBox
var _run_enter_button: Button
var _reward_row: HFlowContainer
var _card_active_row: HFlowContainer
var _card_draft_row: HFlowContainer

var _step_buttons: Array[Button] = []
var _track_order: Array[String] = []
var _boss_order: Array[String] = []

var _layer_active_boxes: Dictionary = {}
var _layer_mute_boxes: Dictionary = {}
var _upgrade_boxes: Dictionary = {}

var _selected_track: String = ""
var _suppress_step_events: bool = false
var _suppress_run_choice_events: bool = false

var _nav_buttons: Dictionary = {}
var _screens: Dictionary = {}
var _current_screen: String = SCREEN_HOME

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_switch_screen(SCREEN_HOME)

func configure(
		layer_display_names: Dictionary,
		layer_states: Dictionary,
		upgrade_defs: Dictionary,
		track_names: Array[String],
		boss_defs: Dictionary,
		steps_per_loop: int,
		bpm: int
	) -> void:
	_build_layer_controls(layer_display_names, layer_states)
	_build_upgrade_controls(upgrade_defs)
	_build_track_selector(track_names)
	_build_step_buttons(steps_per_loop)
	_build_boss_selector(boss_defs)
	_bpm_spinbox.value = bpm
	if not _track_order.is_empty():
		_selected_track = _track_order[0]
		emit_signal("track_selected", _selected_track)

func update_clock_display(step_index: int, loop_index: int, bpm: int, running: bool) -> void:
	_clock_label.text = "Clock %s | BPM %d | Loop %d | Step %d" % ["RUN" if running else "STOP", bpm, loop_index, step_index + 1]
	highlight_step(step_index)

func update_score_display(metrics: Dictionary) -> void:
	_score_label.text = "Score %d | Density %.2f | Sync %.2f | Groove %.2f | Variety %.2f | Energy %.2f" % [
		int(metrics.get("score", 0)),
		float(metrics.get("density", 0.0)),
		float(metrics.get("syncopation", 0.0)),
		float(metrics.get("groove", 0.0)),
		float(metrics.get("variety", 0.0)),
		float(metrics.get("energy", 0.0)),
	]

func update_battle_display(result: Dictionary) -> void:
	if result.is_empty():
		return
	_battle_label.text = "Battle %s | %s | score %d | %s" % [
		String(result.get("boss_name", "-")),
		"VICTORIA" if bool(result.get("victory", false)) else "DERROTA",
		int(result.get("battle_score", 0)),
		String(result.get("reason", "")),
	]

func update_variation_display(text: String) -> void:
	_variation_label.text = "Estado: %s" % text

func update_run_status(run_state: Dictionary) -> void:
	var active: bool = bool(run_state.get("active", false))
	if not active:
		_run_status_label.text = "Run inactiva (pulsa New Run)"
		_run_node_label.text = "Nodo seleccionado: -"
		_run_enter_button.disabled = true
		return

	var hp: int = int(run_state.get("hp", 0))
	var max_hp: int = int(run_state.get("max_hp", 0))
	var coins: int = int(run_state.get("coins", 0))
	var phase: int = int(run_state.get("phase", 1))
	var phase_step: int = int(run_state.get("phase_step", 1))
	var floor: int = int(run_state.get("floor", 0))
	var floors_total: int = int(run_state.get("floors_total", 0))
	var awaiting_reward: bool = bool(run_state.get("awaiting_reward", false))

	_run_status_label.text = "Run HP %d/%d | Coins %d | Fase %d-%d | Piso %d/%d | %s" % [
		hp, max_hp, coins, phase, phase_step, floor, floors_total, "Elige recompensa" if awaiting_reward else "Elige nodo"
	]
	_run_enter_button.disabled = awaiting_reward

func update_run_choices(choices: Array, selected_index: int, pending_node: Dictionary) -> void:
	_suppress_run_choice_events = true
	_run_choice_selector.clear()
	for i in range(choices.size()):
		var item: Dictionary = choices[i]
		var subtitle: String = String(item.get("subtitle", ""))
		var label: String = String(item.get("label", "Nodo"))
		if subtitle.is_empty():
			_run_choice_selector.add_item("%d) %s" % [i + 1, label])
		else:
			_run_choice_selector.add_item("%d) %s - %s" % [i + 1, label, subtitle])
	if selected_index >= 0 and selected_index < _run_choice_selector.get_item_count():
		_run_choice_selector.select(selected_index)
	_suppress_run_choice_events = false

	if pending_node.is_empty():
		_run_node_label.text = "Nodo seleccionado: -"
	else:
		var pending_label: String = String(pending_node.get("label", "-"))
		var pending_subtitle: String = String(pending_node.get("subtitle", ""))
		_run_node_label.text = "Nodo seleccionado: %s%s" % [
			pending_label,
			" | %s" % pending_subtitle if not pending_subtitle.is_empty() else ""
		]

func show_reward_choices(rewards: Array, coins: int) -> void:
	for child in _reward_row.get_children():
		child.queue_free()
	if rewards.is_empty():
		_reward_row.visible = false
		return

	_reward_row.visible = true
	for i in range(rewards.size()):
		var reward: Dictionary = rewards[i]
		var cost: int = int(reward.get("cost", 0))
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(220, 40)
		button.text = "%s%s" % [
			String(reward.get("label", "Reward")),
			" (cost %d)" % cost if cost > 0 else ""
		]
		button.disabled = cost > coins
		button.pressed.connect(_on_run_reward_button_pressed.bind(i))
		_reward_row.add_child(button)

func update_card_state(passive_cards: Array, active_cards: Array) -> void:
	var passive_text: String = "-"
	if not passive_cards.is_empty():
		var names: Array[String] = []
		for card in passive_cards:
			var card_data: Dictionary = card
			names.append(String(card_data.get("name", "Carta")))
		passive_text = ""
		for i in range(names.size()):
			if i > 0:
				passive_text += " | "
			passive_text += names[i]
	_card_passive_label.text = "Pasivas: %s" % passive_text

	for child in _card_active_row.get_children():
		child.queue_free()
	for i in range(active_cards.size()):
		var card_data: Dictionary = active_cards[i]
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(180, 40)
		button.text = "Play [%d] %s" % [i + 1, String(card_data.get("name", "Activa"))]
		button.pressed.connect(_on_card_play_button_pressed.bind(i))
		_card_active_row.add_child(button)

func show_card_draft(cards: Array) -> void:
	for child in _card_draft_row.get_children():
		child.queue_free()
	_card_draft_row.visible = not cards.is_empty()
	for i in range(cards.size()):
		var card_data: Dictionary = cards[i]
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(220, 84)
		button.text = "%s\n%s" % [String(card_data.get("name", "Carta")), String(card_data.get("description", ""))]
		button.pressed.connect(_on_card_draft_button_pressed.bind(i))
		_card_draft_row.add_child(button)

func set_track_pattern(track_name: String, pattern: Array) -> void:
	if track_name != _selected_track:
		return
	_suppress_step_events = true
	for i in range(min(pattern.size(), _step_buttons.size())):
		_step_buttons[i].button_pressed = int(pattern[i]) == 1
	_suppress_step_events = false

func set_layer_state(layer_id: String, is_active: bool, is_muted: bool) -> void:
	if _layer_active_boxes.has(layer_id):
		(_layer_active_boxes[layer_id] as CheckBox).set_pressed_no_signal(is_active)
	if _layer_mute_boxes.has(layer_id):
		(_layer_mute_boxes[layer_id] as CheckBox).set_pressed_no_signal(is_muted)

func set_upgrade_state(upgrade_id: String, enabled: bool) -> void:
	if _upgrade_boxes.has(upgrade_id):
		(_upgrade_boxes[upgrade_id] as CheckBox).set_pressed_no_signal(enabled)

func highlight_step(step_index: int) -> void:
	for i in range(_step_buttons.size()):
		var button: Button = _step_buttons[i]
		button.modulate = Color(1.0, 1.0, 1.0)
		if i == step_index:
			button.modulate = Color(0.82, 1.0, 0.72)

func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.07, 0.10, 0.14)
	add_child(backdrop)

	var left_glow: ColorRect = ColorRect.new()
	left_glow.color = Color(0.15, 0.24, 0.30, 0.40)
	left_glow.size = Vector2(380, 900)
	left_glow.position = Vector2(-80, -40)
	backdrop.add_child(left_glow)

	var right_glow: ColorRect = ColorRect.new()
	right_glow.color = Color(0.29, 0.16, 0.08, 0.34)
	right_glow.size = Vector2(380, 900)
	right_glow.position = Vector2(900, -20)
	backdrop.add_child(right_glow)

	var root_margin: MarginContainer = MarginContainer.new()
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 20)
	root_margin.add_theme_constant_override("margin_right", 20)
	root_margin.add_theme_constant_override("margin_top", 16)
	root_margin.add_theme_constant_override("margin_bottom", 16)
	add_child(root_margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root_margin.add_child(root)

	root.add_child(_build_header())
	root.add_child(_build_screen_host())
	root.add_child(_build_hud())

func _build_header() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.10, 0.14, 0.20, 0.92), Color(0.44, 0.58, 0.74)))

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var title: Label = Label.new()
	title.text = "SYNN // ROGUELITE MUSIC PROTOTYPE"
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = Color(0.92, 0.97, 1.0)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "Loop de run: X-1 base, X-2 nodo, X-3 boss. Build musical por capas."
	subtitle.modulate = Color(0.70, 0.82, 0.90)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(subtitle)

	var nav: HFlowContainer = HFlowContainer.new()
	nav.add_theme_constant_override("h_separation", 6)
	nav.add_theme_constant_override("v_separation", 6)
	col.add_child(nav)

	nav.add_child(_create_nav_button("HOME", SCREEN_HOME))
	nav.add_child(_create_nav_button("RUN", SCREEN_RUN))
	nav.add_child(_create_nav_button("STUDIO", SCREEN_STUDIO))
	nav.add_child(_create_nav_button("BATTLE", SCREEN_BATTLE))

	return panel

func _build_screen_host() -> Control:
	var host: PanelContainer = PanelContainer.new()
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.clip_contents = true
	host.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.11, 0.16, 0.90), Color(0.30, 0.38, 0.50)))

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 14)
	host.add_child(pad)

	var stack: Control = Control.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(stack)

	var raw_screens: Dictionary = {
		SCREEN_HOME: _build_home_screen(),
		SCREEN_RUN: _build_run_screen(),
		SCREEN_STUDIO: _build_studio_screen(),
		SCREEN_BATTLE: _build_battle_screen(),
	}

	_screens.clear()
	for screen_id in raw_screens.keys():
		var wrapper: ScrollContainer = ScrollContainer.new()
		wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		wrapper.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		wrapper.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		wrapper.follow_focus = true
		wrapper.visible = false

		var screen: Control = raw_screens[screen_id]
		screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
		screen.custom_minimum_size = Vector2(0.0, 620.0)
		wrapper.add_child(screen)
		stack.add_child(wrapper)
		_screens[screen_id] = wrapper

	return host

func _build_hud() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.09, 0.13, 0.19, 0.94), Color(0.33, 0.44, 0.58)))

	var row: VBoxContainer = VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)

	_clock_label = Label.new()
	_clock_label.text = "Clock: -"
	_clock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_clock_label)

	_score_label = Label.new()
	_score_label.text = "Score: -"
	_score_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_score_label)

	_battle_label = Label.new()
	_battle_label.text = "Battle: -"
	_battle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_battle_label)

	_variation_label = Label.new()
	_variation_label.text = "Estado: -"
	_variation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_variation_label)

	_interaction_label = Label.new()
	_interaction_label.text = "Interaccion: -"
	_interaction_label.modulate = Color(0.86, 0.92, 0.74)
	row.add_child(_interaction_label)

	return panel

func _build_home_screen() -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)

	var hero: Label = Label.new()
	hero.text = "Vertical Slice"
	hero.add_theme_font_size_override("font_size", 28)
	hero.modulate = Color(0.98, 0.92, 0.77)
	col.add_child(hero)

	var pitch: Label = Label.new()
	pitch.text = "En 1-1 eliges una base sonora inicial; luego mejoras tu build para superar elites y bosses en X-3."
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pitch.modulate = Color(0.86, 0.92, 1.0)
	col.add_child(pitch)

	var pillars: HFlowContainer = HFlowContainer.new()
	pillars.add_theme_constant_override("h_separation", 8)
	pillars.add_theme_constant_override("v_separation", 8)
	col.add_child(pillars)
	pillars.add_child(_feature_card("RUN MAP", "Elige nodo por piso"))
	pillars.add_child(_feature_card("CARD DRAFT", "Build unico por run"))
	pillars.add_child(_feature_card("BOSS CHECK", "Requisitos musicales"))

	var actions: HFlowContainer = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	col.add_child(actions)

	var start_btn: Button = Button.new()
	start_btn.text = "START LOOP"
	start_btn.pressed.connect(_on_start_button_pressed)
	actions.add_child(start_btn)

	var new_run_btn: Button = Button.new()
	new_run_btn.text = "NEW RUN"
	new_run_btn.pressed.connect(_on_run_new_button_pressed)
	actions.add_child(new_run_btn)

	var goto_run: Button = Button.new()
	goto_run.text = "GO RUN SCREEN"
	goto_run.pressed.connect(_on_nav_pressed.bind(SCREEN_RUN))
	actions.add_child(goto_run)

	return col

func _build_run_screen() -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)

	var title: Label = Label.new()
	title.text = "Run Director"
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color(0.94, 0.86, 0.72)
	col.add_child(title)

	var run_buttons: HFlowContainer = HFlowContainer.new()
	run_buttons.add_theme_constant_override("h_separation", 6)
	run_buttons.add_theme_constant_override("v_separation", 6)
	col.add_child(run_buttons)

	var run_new_btn: Button = Button.new()
	run_new_btn.text = "New Run"
	run_new_btn.pressed.connect(_on_run_new_button_pressed)
	run_buttons.add_child(run_new_btn)

	_run_enter_button = Button.new()
	_run_enter_button.text = "Enter Node"
	_run_enter_button.pressed.connect(_on_run_enter_button_pressed)
	run_buttons.add_child(_run_enter_button)

	_run_status_label = Label.new()
	_run_status_label.text = "Run: inactiva"
	_run_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_run_status_label)

	var pick_row: HBoxContainer = HBoxContainer.new()
	pick_row.add_theme_constant_override("separation", 6)
	col.add_child(pick_row)

	var pick_label: Label = Label.new()
	pick_label.text = "Opciones de nodo"
	pick_row.add_child(pick_label)

	_run_choice_selector = OptionButton.new()
	_run_choice_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_choice_selector.item_selected.connect(_on_run_choice_item_selected)
	pick_row.add_child(_run_choice_selector)

	_run_node_label = Label.new()
	_run_node_label.text = "Nodo seleccionado: -"
	_run_node_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_run_node_label)

	_reward_row = HFlowContainer.new()
	_reward_row.add_theme_constant_override("h_separation", 6)
	_reward_row.add_theme_constant_override("v_separation", 6)
	_reward_row.visible = false
	col.add_child(_reward_row)

	col.add_child(_separator_label("Cards"))

	_card_passive_label = Label.new()
	_card_passive_label.text = "Pasivas: -"
	col.add_child(_card_passive_label)

	var active_title: Label = Label.new()
	active_title.text = "Activas (click para jugar)"
	col.add_child(active_title)

	_card_active_row = HFlowContainer.new()
	_card_active_row.add_theme_constant_override("h_separation", 6)
	_card_active_row.add_theme_constant_override("v_separation", 6)
	col.add_child(_card_active_row)

	var draft_title: Label = Label.new()
	draft_title.text = "Draft 1 de 3"
	col.add_child(draft_title)

	_card_draft_row = HFlowContainer.new()
	_card_draft_row.add_theme_constant_override("h_separation", 6)
	_card_draft_row.add_theme_constant_override("v_separation", 6)
	_card_draft_row.visible = false
	col.add_child(_card_draft_row)

	return col

func _build_studio_screen() -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)

	var title: Label = Label.new()
	title.text = "Music Studio"
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color(0.84, 0.94, 0.90)
	col.add_child(title)

	var transport: HFlowContainer = HFlowContainer.new()
	transport.add_theme_constant_override("h_separation", 6)
	transport.add_theme_constant_override("v_separation", 6)
	col.add_child(transport)

	var start_btn: Button = Button.new()
	start_btn.text = "Start"
	start_btn.pressed.connect(_on_start_button_pressed)
	transport.add_child(start_btn)

	var stop_btn: Button = Button.new()
	stop_btn.text = "Stop"
	stop_btn.pressed.connect(_on_stop_button_pressed)
	transport.add_child(stop_btn)

	var reset_btn: Button = Button.new()
	reset_btn.text = "Reset"
	reset_btn.pressed.connect(_on_reset_button_pressed)
	transport.add_child(reset_btn)

	var random_btn: Button = Button.new()
	random_btn.text = "Random Build"
	random_btn.pressed.connect(_on_random_build_button_pressed)
	transport.add_child(random_btn)

	var auto_btn: Button = Button.new()
	auto_btn.text = "Auto Test"
	auto_btn.pressed.connect(_on_auto_test_button_pressed)
	transport.add_child(auto_btn)

	var variation_btn: Button = Button.new()
	variation_btn.text = "Apply Variation"
	variation_btn.pressed.connect(_on_manual_variation_button_pressed)
	transport.add_child(variation_btn)

	var bpm_row: HBoxContainer = HBoxContainer.new()
	bpm_row.add_theme_constant_override("separation", 6)
	col.add_child(bpm_row)

	var bpm_label: Label = Label.new()
	bpm_label.text = "BPM"
	bpm_row.add_child(bpm_label)

	_bpm_spinbox = SpinBox.new()
	_bpm_spinbox.min_value = 60
	_bpm_spinbox.max_value = 180
	_bpm_spinbox.step = 1
	_bpm_spinbox.value_changed.connect(_on_bpm_changed)
	bpm_row.add_child(_bpm_spinbox)

	_auto_variation_check = CheckBox.new()
	_auto_variation_check.text = "Auto Variation"
	_auto_variation_check.button_pressed = true
	_auto_variation_check.toggled.connect(_on_auto_variation_toggled)
	bpm_row.add_child(_auto_variation_check)

	col.add_child(_separator_label("Layers"))
	_layer_rows = VBoxContainer.new()
	_layer_rows.add_theme_constant_override("separation", 4)
	col.add_child(_layer_rows)

	col.add_child(_separator_label("Upgrades"))
	_upgrade_rows = VBoxContainer.new()
	_upgrade_rows.add_theme_constant_override("separation", 4)
	col.add_child(_upgrade_rows)

	col.add_child(_separator_label("Pattern Editor"))
	var track_row: HBoxContainer = HBoxContainer.new()
	track_row.add_theme_constant_override("separation", 6)
	col.add_child(track_row)

	var track_label: Label = Label.new()
	track_label.text = "Track"
	track_row.add_child(track_label)

	_track_selector = OptionButton.new()
	_track_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track_selector.item_selected.connect(_on_track_item_selected)
	track_row.add_child(_track_selector)

	var step_scroll: ScrollContainer = ScrollContainer.new()
	step_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	step_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	step_scroll.custom_minimum_size = Vector2(0.0, 48.0)
	step_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(step_scroll)

	_step_container = HBoxContainer.new()
	_step_container.add_theme_constant_override("separation", 2)
	step_scroll.add_child(_step_container)

	return col

func _build_battle_screen() -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)

	var title: Label = Label.new()
	title.text = "Battle Room"
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color(0.98, 0.84, 0.72)
	col.add_child(title)

	var desc: Label = Label.new()
	desc.text = "Prueba tu build actual contra un boss concreto."
	desc.modulate = Color(0.83, 0.88, 0.94)
	col.add_child(desc)

	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	col.add_child(row)

	var boss_label: Label = Label.new()
	boss_label.text = "Boss"
	row.add_child(boss_label)

	_boss_selector = OptionButton.new()
	_boss_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_boss_selector)

	var run_btn: Button = Button.new()
	run_btn.text = "Run Battle"
	run_btn.pressed.connect(_on_battle_button_pressed)
	row.add_child(run_btn)

	var auto_btn: Button = Button.new()
	auto_btn.text = "Auto Test Builds"
	auto_btn.pressed.connect(_on_auto_test_button_pressed)
	row.add_child(auto_btn)

	return col

func _create_nav_button(label: String, screen_id: String) -> Button:
	var button: Button = Button.new()
	button.text = label
	button.pressed.connect(_on_nav_pressed.bind(screen_id))
	_nav_buttons[screen_id] = button
	return button

func _switch_screen(screen_id: String) -> void:
	if not _screens.has(screen_id):
		return
	_current_screen = screen_id
	for key in _screens.keys():
		(_screens[key] as Control).visible = key == screen_id

	for key in _nav_buttons.keys():
		var button: Button = _nav_buttons[key]
		button.modulate = Color(1.0, 1.0, 1.0) if key == screen_id else Color(0.78, 0.84, 0.92)

func _panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 10
	style.content_margin_top = 10
	style.content_margin_right = 10
	style.content_margin_bottom = 10
	return style

func _feature_card(title: String, body: String) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(170, 120)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.11, 0.16, 0.23, 0.95), Color(0.35, 0.45, 0.58)))

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	var head: Label = Label.new()
	head.text = title
	head.modulate = Color(0.97, 0.92, 0.78)
	head.add_theme_font_size_override("font_size", 18)
	col.add_child(head)

	var text: Label = Label.new()
	text.text = body
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.modulate = Color(0.82, 0.90, 0.96)
	col.add_child(text)

	return panel

func _separator_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.modulate = Color(0.95, 0.90, 0.78)
	label.add_theme_font_size_override("font_size", 18)
	return label

func _build_layer_controls(layer_display_names: Dictionary, layer_states: Dictionary) -> void:
	for child in _layer_rows.get_children():
		child.queue_free()
	_layer_active_boxes.clear()
	_layer_mute_boxes.clear()

	var ordered_ids: Array[String] = []
	for layer_id in layer_display_names.keys():
		ordered_ids.append(layer_id)
	ordered_ids.sort()

	for layer_id in ordered_ids:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_layer_rows.add_child(row)

		var name_label: Label = Label.new()
		name_label.text = String(layer_display_names[layer_id])
		name_label.custom_minimum_size = Vector2(110, 0)
		row.add_child(name_label)

		var active_box: CheckBox = CheckBox.new()
		active_box.text = "Active"
		active_box.button_pressed = bool(layer_states.get(layer_id, {}).get("active", true))
		active_box.toggled.connect(_on_layer_active_toggled.bind(layer_id))
		row.add_child(active_box)
		_layer_active_boxes[layer_id] = active_box

		var mute_box: CheckBox = CheckBox.new()
		mute_box.text = "Mute"
		mute_box.button_pressed = bool(layer_states.get(layer_id, {}).get("muted", false))
		mute_box.toggled.connect(_on_layer_muted_toggled.bind(layer_id))
		row.add_child(mute_box)
		_layer_mute_boxes[layer_id] = mute_box

func _build_upgrade_controls(upgrade_defs: Dictionary) -> void:
	for child in _upgrade_rows.get_children():
		child.queue_free()
	_upgrade_boxes.clear()

	var ordered_ids: Array[String] = []
	for upgrade_id in upgrade_defs.keys():
		ordered_ids.append(upgrade_id)
	ordered_ids.sort()

	for upgrade_id in ordered_ids:
		var data: Dictionary = upgrade_defs[upgrade_id]
		var box: CheckBox = CheckBox.new()
		box.text = "%s: %s" % [String(data.get("name", upgrade_id)), String(data.get("description", ""))]
		box.button_pressed = bool(data.get("enabled", false))
		box.toggled.connect(_on_upgrade_toggled.bind(upgrade_id))
		_upgrade_rows.add_child(box)
		_upgrade_boxes[upgrade_id] = box

func _build_track_selector(track_names: Array[String]) -> void:
	_track_selector.clear()
	_track_order = track_names.duplicate()
	for track_name in _track_order:
		_track_selector.add_item(track_name)

func _build_step_buttons(steps_per_loop: int) -> void:
	for child in _step_container.get_children():
		child.queue_free()
	_step_buttons.clear()

	for i in range(steps_per_loop):
		var button: Button = Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(28, 28)
		button.text = str(i + 1)
		button.toggled.connect(_on_step_button_toggled.bind(i))
		_step_container.add_child(button)
		_step_buttons.append(button)

func _build_boss_selector(boss_defs: Dictionary) -> void:
	_boss_selector.clear()
	_boss_order.clear()

	var ordered_ids: Array[String] = []
	for boss_id in boss_defs.keys():
		ordered_ids.append(boss_id)
	ordered_ids.sort()

	for boss_id in ordered_ids:
		_boss_order.append(boss_id)
		var boss_name: String = String(boss_defs[boss_id].get("name", boss_id))
		_boss_selector.add_item(boss_name)

func _set_interaction(text: String) -> void:
	_interaction_label.text = "Interaccion: %s" % text

func _on_nav_pressed(screen_id: String) -> void:
	_set_interaction("go %s" % screen_id)
	_switch_screen(screen_id)

func _on_bpm_changed(value: float) -> void:
	_set_interaction("BPM -> %d" % int(value))
	emit_signal("bpm_changed", int(value))

func _on_auto_variation_toggled(pressed: bool) -> void:
	_set_interaction("Auto Variation -> %s" % ("ON" if pressed else "OFF"))
	emit_signal("auto_variation_changed", pressed)

func _on_layer_active_toggled(pressed: bool, layer_id: String) -> void:
	_set_interaction("Layer %s Active -> %s" % [layer_id, "ON" if pressed else "OFF"])
	emit_signal("layer_active_changed", layer_id, pressed)

func _on_layer_muted_toggled(pressed: bool, layer_id: String) -> void:
	_set_interaction("Layer %s Mute -> %s" % [layer_id, "ON" if pressed else "OFF"])
	emit_signal("layer_muted_changed", layer_id, pressed)

func _on_upgrade_toggled(pressed: bool, upgrade_id: String) -> void:
	_set_interaction("Upgrade %s -> %s" % [upgrade_id, "ON" if pressed else "OFF"])
	emit_signal("upgrade_changed", upgrade_id, pressed)

func _on_track_item_selected(index: int) -> void:
	if index < 0 or index >= _track_order.size():
		return
	_selected_track = _track_order[index]
	_set_interaction("Track -> %s" % _selected_track)
	emit_signal("track_selected", _selected_track)

func _on_step_button_toggled(pressed: bool, step_index: int) -> void:
	if _suppress_step_events or _selected_track.is_empty():
		return
	_set_interaction("%s step %d -> %s" % [_selected_track, step_index + 1, "ON" if pressed else "OFF"])
	emit_signal("step_toggled", _selected_track, step_index, pressed)

func _on_battle_button_pressed() -> void:
	var index: int = _boss_selector.get_selected()
	if index < 0 or index >= _boss_order.size():
		return
	_set_interaction("Run Battle -> %s" % _boss_order[index])
	emit_signal("battle_requested", _boss_order[index])

func _on_run_new_button_pressed() -> void:
	_set_interaction("New Run")
	emit_signal("run_new_requested")
	_switch_screen(SCREEN_RUN)

func _on_run_choice_item_selected(index: int) -> void:
	if _suppress_run_choice_events:
		return
	_set_interaction("Run choice %d" % (index + 1))
	emit_signal("run_choice_selected", index)

func _on_run_enter_button_pressed() -> void:
	_set_interaction("Enter Node")
	emit_signal("run_enter_requested")

func _on_run_reward_button_pressed(index: int) -> void:
	_set_interaction("Reward %d" % (index + 1))
	emit_signal("run_reward_selected", index)

func _on_card_play_button_pressed(index: int) -> void:
	_set_interaction("Play card %d" % (index + 1))
	emit_signal("card_play_requested", index)

func _on_card_draft_button_pressed(index: int) -> void:
	_set_interaction("Draft pick %d" % (index + 1))
	emit_signal("card_draft_pick_requested", index)

func _on_start_button_pressed() -> void:
	_set_interaction("Start")
	emit_signal("start_requested")

func _on_stop_button_pressed() -> void:
	_set_interaction("Stop")
	emit_signal("stop_requested")

func _on_reset_button_pressed() -> void:
	_set_interaction("Reset")
	emit_signal("reset_requested")

func _on_random_build_button_pressed() -> void:
	_set_interaction("Random Build")
	emit_signal("random_build_requested")

func _on_auto_test_button_pressed() -> void:
	_set_interaction("Auto Test")
	emit_signal("best_build_search_requested")

func _on_manual_variation_button_pressed() -> void:
	_set_interaction("Apply Variation")
	emit_signal("manual_variation_requested")
