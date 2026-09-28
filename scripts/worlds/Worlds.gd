extends Node

## Autoload. Every WorldDef in res://worlds/, indexed by world id
## (stratum * STRATUM_SIZE + slot). Everything else refers to worlds by id.
##
## Topology: worlds come in strata (depth bands) of up to STRATUM_SIZE.
## Common portals move one slot within a stratum; fissures cross to the
## neighbouring stratum, landing on the same slot (or the nearest one that
## exists). Strata may be incomplete: with one world each, there are no
## common portals and fissures do all the linking.

const DIR := "res://worlds/"
const STRATUM_SIZE := 4
const STRATA := 5

var _defs: Dictionary[int, WorldDef] = {}
var _ids: Array[int] = []
var _dist := {} # Vector2i(a, b) -> hops

func _ready() -> void:
	# list_directory also sees the remapped files of an exported build.
	for f in ResourceLoader.list_directory(DIR):
		if f.ends_with(".tres"):
			var d := load(DIR + f) as WorldDef
			_defs[id_of(d.stratum, d.slot)] = d
	_ids.assign(_defs.keys())
	_ids.sort()

static func id_of(stratum_index: int, slot_index: int) -> int:
	return stratum_index * STRATUM_SIZE + slot_index

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

func slot(w: int) -> int:
	return w % STRATUM_SIZE

func deepest_stratum() -> int:
	return stratum(_ids[-1])

func in_stratum(s: int) -> Array[int]:
	return _ids.filter(func(w: int) -> bool: return stratum(w) == s)

## Common portal: the next slot in the same stratum (dir +1/-1), -1 if none.
func portal_target(w: int, dir: int) -> int:
	var t := w + dir
	return t if stratum(t) == stratum(w) and slot(w) + dir >= 0 and has(t) else -1

## Fissure: the neighbouring stratum (dir +1 deeper, -1 shallower), same
## slot or the nearest existing one; -1 if that stratum is empty or absent.
func fissure_target(w: int, dir: int) -> int:
	var best := -1
	for t in in_stratum(stratum(w) + dir):
		if best < 0 or absi(slot(t) - slot(w)) < absi(slot(best) - slot(w)):
			best = t
	return best

## Every world one portal or fissure away.
func links(w: int) -> Array[int]:
	var out: Array[int] = []
	for t in [portal_target(w, -1), portal_target(w, 1), fissure_target(w, -1), fissure_target(w, 1)]:
		if t >= 0 and not t in out:
			out.append(t)
	return out

## One hop shallower (-1) or deeper (+1): the adjacent slot if the stratum
## has one, else across a fissure. -1 if none. (What the scanner shows.)
func adjacent(w: int, dir: int) -> int:
	var t := portal_target(w, dir)
	return t if t >= 0 else fissure_target(w, dir)

## Portal/fissure hops between two worlds (BFS; cached).
func distance(a: int, b: int) -> int:
	var key := Vector2i(a, b)
	if not _dist.has(key):
		var d := {a: 0}
		var queue: Array[int] = [a]
		while not queue.is_empty():
			var c: int = queue.pop_front()
			for n in links(c):
				if not d.has(n):
					d[n] = d[c] + 1
					queue.append(n)
		_dist[key] = d.get(b, 99)
	return _dist[key]

## The world one hop from `from` on a shortest way to `goal`.
func step_toward(from: int, goal: int) -> int:
	var best := from
	for n in links(from):
		if best == from or distance(n, goal) < distance(best, goal):
			best = n
	return best
