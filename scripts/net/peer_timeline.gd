class_name InkPeerTimeline
extends RefCounted
## Bounded playback follows a sender's clock without feeding network jitter into locomotion.

var offset: float = 0
var delay: float = 0.1
var playback: float = 0
var latest: float = -1
var initialized: bool = false
var samples: Dictionary = {}
var events: Array = []
var _arrivals: Array[float] = []
var _spacings: Array[float] = []

func accept(timestamp: float, now: float, actors: Array) -> void:
	var arrival: float = now - timestamp
	_arrivals.append(arrival)
	if _arrivals.size() > 60: _arrivals.pop_front()
	var floor_offset: float = _arrivals.min()
	if not initialized:
		offset = arrival
		playback = timestamp - delay
		initialized = true
	else:
		offset = lerpf(offset, floor_offset, 0.08)
		if timestamp > latest and latest > 0:
			_spacings.append(clampf(timestamp - latest, 0.02, 0.2))
			if _spacings.size() > 60: _spacings.pop_front()
		var jitter: Array[float] = _arrivals.duplicate()
		jitter.sort()
		var spacing: float = 0.05
		if not _spacings.is_empty():
			var sorted: Array[float] = _spacings.duplicate()
			sorted.sort()
			spacing = sorted[mini(sorted.size() - 1, floori(sorted.size() * 0.95))]
		var late: float = jitter[mini(jitter.size() - 1, floori(jitter.size() * 0.9))] - floor_offset
		delay = lerpf(delay, clampf(spacing + late + 0.025, 0.075, 0.22), 0.05)
	latest = maxf(latest, timestamp)
	for sample: Array in actors:
		var id: int = int(sample[0])
		var buffer: Array = samples.get(id, []) as Array
		if not buffer.is_empty() and timestamp <= float(buffer.back().t): continue
		buffer.append({"t": timestamp, "a": sample})
		while buffer.size() > 32: buffer.pop_front()
		samples[id] = buffer

func advance(delta: float, now: float) -> void:
	if not initialized: return
	var target: float = now - offset - delay
	var rate: float = clampf(1.0 + (target - playback) * 1.5, 0.92, 1.08)
	if playback > latest - 0.015: rate = 0.8
	playback += delta * rate
	if absf(target - playback) > 1.0: playback = target

func sample(id: int) -> Dictionary:
	var buffer: Array = samples.get(id, []) as Array
	if buffer.is_empty(): return {}
	while buffer.size() > 2 and float(buffer[1].t) < playback - 0.3: buffer.pop_front()
	for index: int in range(buffer.size() - 1):
		var a: Dictionary = buffer[index]
		var b: Dictionary = buffer[index + 1]
		if float(b.t) < playback: continue
		var duration: float = maxf(0.001, float(b.t) - float(a.t))
		if int(a.a[16]) != int(b.a[16]) or InkSnapshotCodec.position_of(a.a).distance_squared_to(InkSnapshotCodec.position_of(b.a)) > 225:
			return InkSnapshotCodec.interpolate(b.a, b.a, 0, 0)
		return InkSnapshotCodec.interpolate(a.a, b.a, (playback - float(a.t)) / duration, duration)
	var last: Dictionary = buffer.back()
	var state: Dictionary = InkSnapshotCodec.interpolate(last.a, last.a, 0, 0)
	var extrapolate: float = clampf(playback - float(last.t), 0, 0.18)
	state.position += (state.velocity as Vector3) * extrapolate
	if (int(state.flags) & 16) == 0: state.position.y -= 11.0 * extrapolate * extrapolate
	return state

func enqueue_events(values: Array) -> void:
	for event: Variant in values:
		if event is Array and event.size() >= 3 and event.size() <= 32 and (event[0] is float or event[0] is int):
			if is_finite(float(event[0])): events.append(event)
	if events.size() > 512: events = events.slice(events.size() - 512)
	events.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))

func due_events() -> Array:
	var result: Array = []
	while not events.is_empty() and float(events.front()[0]) <= playback:
		result.append(events.pop_front())
	return result
