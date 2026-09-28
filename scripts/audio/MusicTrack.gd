extends Resource
class_name MusicTrack

## A looping piece of music. loop_offset is where it jumps back to at its
## end; tools/loop_music.py finds it (and bakes the crossfade that makes the
## jump seamless) and writes it into this track's .tres.

@export var stream: AudioStream
@export var loop_offset := 0.0
