extends Node
class_name InstrumentLayer

# Lightweight synth layer used for prototyping without external samples/DAWs.
signal track_triggered(track_name: String, step_index: int)

@export var layer_id: String = "layer"
@export var display_name: String = "Layer"

var is_active: bool = true
var is_muted: bool = false

var tracks: Dictionary = {}

var _voices: Array[Dictionary] = []
var _playback: AudioStreamGeneratorPlayback
var _sample_rate: float = 44100.0
var _rng = RandomNumberGenerator.new()

@onready var _player: AudioStreamPlayer = get_node_or_null("AudioStreamPlayer")

func _ready() -> void:
	_rng.randomize()
	_setup_audio_player()

func _process(_delta: float) -> void:
	_fill_audio_buffer()

func setup_tracks(track_definitions: Dictionary) -> void:
	tracks.clear()
	for track_name in track_definitions.keys():
		var cfg: Dictionary = {
			"waveform": "sine",
			"freq": 220.0,
			"freq_end": -1.0,
			"decay": 0.12,
			"volume": 0.5,
			"pan": 0.0,
		}
		for key in track_definitions[track_name].keys():
			cfg[key] = track_definitions[track_name][key]
		tracks[track_name] = cfg

func trigger_track(track_name: String, step_index: int = -1, velocity: float = 1.0) -> void:
	if not is_active or is_muted:
		return
	if not tracks.has(track_name):
		return

	var cfg: Dictionary = tracks[track_name]
	var base_freq = float(cfg.get("freq", 220.0))
	if cfg.has("freq_sequence") and step_index >= 0:
		var sequence: Array = cfg["freq_sequence"]
		if not sequence.is_empty():
			base_freq = float(sequence[step_index % sequence.size()])
	var voice = {
		"waveform": String(cfg.get("waveform", "sine")),
		"freq": base_freq,
		"freq_end": float(cfg.get("freq_end", -1.0)),
		"phase": 0.0,
		"age": 0.0,
		"duration": max(0.02, float(cfg.get("decay", 0.12))),
		"volume": max(0.0, float(cfg.get("volume", 0.5)) * velocity),
		"pan": clamp(float(cfg.get("pan", 0.0)), -1.0, 1.0),
	}
	_voices.append(voice)
	emit_signal("track_triggered", track_name, step_index)
	_fill_audio_buffer()

func set_active(value: bool) -> void:
	is_active = value

func set_muted(value: bool) -> void:
	is_muted = value

func _setup_audio_player() -> void:
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.name = "AudioStreamPlayer"
		add_child(_player)

	var stream = AudioStreamGenerator.new()
	stream.mix_rate = int(_sample_rate)
	stream.buffer_length = 0.25
	_player.stream = stream
	_player.play()
	_playback = _player.get_stream_playback()

func _fill_audio_buffer() -> void:
	if _playback == null:
		return

	var frames = _playback.get_frames_available()
	for _i in range(frames):
		var mixed_l = 0.0
		var mixed_r = 0.0
		var next_voices: Array[Dictionary] = []

		for voice_data in _voices:
			var age = float(voice_data.get("age", 0.0))
			var duration = float(voice_data.get("duration", 0.1))
			if age >= duration:
				continue

			var t = age / duration
			var envelope = pow(1.0 - t, 2.0)
			var freq = float(voice_data.get("freq", 220.0))
			var freq_end = float(voice_data.get("freq_end", -1.0))
			if freq_end > 0.0:
				freq = lerp(freq, freq_end, t)

			var phase = float(voice_data.get("phase", 0.0))
			var sample = _sample_wave(String(voice_data.get("waveform", "sine")), phase)
			var amp = sample * float(voice_data.get("volume", 0.5)) * envelope
			var pan = float(voice_data.get("pan", 0.0))
			mixed_l += amp * (1.0 - max(0.0, pan))
			mixed_r += amp * (1.0 + min(0.0, pan))

			voice_data["phase"] = fposmod(phase + (freq / _sample_rate), 1.0)
			voice_data["age"] = age + (1.0 / _sample_rate)
			next_voices.append(voice_data)

		_voices = next_voices
		_playback.push_frame(Vector2(clamp(mixed_l * 0.5, -1.0, 1.0), clamp(mixed_r * 0.5, -1.0, 1.0)))

func _sample_wave(waveform: String, phase: float) -> float:
	match waveform:
		"square":
			return 1.0 if phase < 0.5 else -1.0
		"triangle":
			return 1.0 - 4.0 * abs(phase - 0.5)
		"noise":
			return _rng.randf_range(-1.0, 1.0)
		_:
			return sin(TAU * phase)
