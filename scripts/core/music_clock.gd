extends Node
class_name MusicClock

# Global transport clock. Emits deterministic step events for a 4/4 step-sequencer loop.
signal started
signal stopped
signal step_advanced(step: int, loop_index: int)
signal beat_advanced(beat: int, loop_index: int)
signal loop_started(loop_index: int)

@export_range(60, 200, 1) var bpm: int = 120:
	set(value):
		bpm = clamp(value, 60, 200)
		_recompute_step_duration()

@export var beats_per_bar: int = 4
@export var steps_per_loop: int = 16

var running: bool = false
var current_step: int = 0
var loop_index: int = 0

var _accumulator: float = 0.0
var _step_duration: float = 0.125

func _ready() -> void:
	_recompute_step_duration()

func _process(delta: float) -> void:
	if not running:
		return

	_accumulator += delta
	while _accumulator >= _step_duration:
		_accumulator -= _step_duration
		_emit_step()

func start_clock(reset_position: bool = false) -> void:
	if reset_position:
		reset()
	if running:
		return
	running = true
	emit_signal("started")

func stop_clock() -> void:
	if not running:
		return
	running = false
	emit_signal("stopped")

func reset() -> void:
	current_step = 0
	loop_index = 0
	_accumulator = 0.0

func set_bpm(new_bpm: int) -> void:
	bpm = new_bpm

func get_step_duration() -> float:
	return _step_duration

func _emit_step() -> void:
	emit_signal("step_advanced", current_step, loop_index)

	var steps_per_beat: int = max(1, int(float(steps_per_loop) / float(max(beats_per_bar, 1))))
	if current_step % steps_per_beat == 0:
		var beat_index: int = int(float(current_step) / float(steps_per_beat))
		emit_signal("beat_advanced", beat_index, loop_index)

	current_step += 1
	if current_step >= steps_per_loop:
		current_step = 0
		loop_index += 1
		emit_signal("loop_started", loop_index)

func _recompute_step_duration() -> void:
	# In 4/4 with 16 steps, each step is a sixteenth note.
	_step_duration = (60.0 / float(max(bpm, 1))) * (4.0 / float(max(steps_per_loop, 1)))
