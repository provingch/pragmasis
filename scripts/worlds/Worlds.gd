extends Node

## Autoload. Every WorldDef in res://worlds/, indexed by world id: an int
## derived from its place in the topology (see id_of). Everything else
## refers to worlds by that id.

const DIR := "res://worlds/"
## Worlds per stratum; ids leave room for missing slots.
const STRATUM_SIZE := 4

var _defs: Dictionary[int, WorldDef] = {}
var _ids: Array[int] = []

func _ready() -> void:
	# list_directory also sees the remapped files of an exported build.
	for f in ResourceLoader.list_directory(DIR):
		if f.ends_with(".tres"):
			var d := load(DIR + f) as WorldDef
			_defs[id_of(d.stratum, d.slot)] = d
	_ids.assign(_defs.keys())
	_ids.sort()

static func id_of(stratum: int, slot: int) -> int:
	return stratum * STRATUM_SIZE + slot

func def(w: int) -> WorldDef:
	return _defs[w]

func has(w: int) -> bool:
	return _defs.has(w)

## All world ids, shallowest first.
func ids() -> Array[int]:
	return _ids

## Where every run starts: the shallowest world.
func start() -> int:
	return _ids[0]

func stratum(w: int) -> int:
	return w / STRATUM_SIZE

## Next world deeper (dir 1) or shallower (-1) in depth order, -1 if none.
func neighbor(w: int, dir: int) -> int:
	var i := _ids.find(w) + dir
	return _ids[i] if i >= 0 and i < _ids.size() else -1

## Portal hops between two worlds.
func distance(a: int, b: int) -> int:
	return absi(_ids.find(a) - _ids.find(b))

## The world one hop from `from` on the way to `goal`.
func step_toward(from: int, goal: int) -> int:
	return neighbor(from, signi(_ids.find(goal) - _ids.find(from)))
