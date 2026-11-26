extends AudioStreamPlayer3D

## Keeps the bonfire crackle looping even when the imported WAV has loop
## playback disabled in its import settings.


func _ready() -> void:
	var wav := stream as AudioStreamWAV
	if wav != null and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		var looped: AudioStreamWAV = wav.duplicate()
		looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
		looped.loop_begin = 0
		looped.loop_end = int(round(looped.get_length() * float(looped.mix_rate)))
		stream = looped
	if not playing:
		play()
