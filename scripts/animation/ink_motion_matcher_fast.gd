extends "res://scripts/animation/ink_motion_matcher.gd"
## Portable provider with the two hot temporary range Arrays removed.
## Feature order, arithmetic, pruning, and strict continuation ties stay intact.

func _search_candidates() -> void:
	continuation_cost = _cost(matched_pose, INF)
	_best_pose = matched_pose
	_best_cost = continuation_cost
	var first_pose: int = _bucket.x
	for offset: int in _bucket.y - first_pose:
		var pose: int = first_pose + offset
		var cost := _cost(pose, _best_cost)
		if cost < _best_cost:
			_best_cost = cost
			_best_pose = pose

func _cost(pose: int, limit: float) -> float:
	var start := pose * 63
	var cost := 0.0
	for offset: int in _query.size() - 42:
		var d: int = 42 + offset
		var delta := _features[start + d] - _query[d]
		cost += delta * delta * _weights[d]
	if cost > limit: return cost
	for d in 42:
		var delta := _features[start + d] - _query[d]
		cost += delta * delta * _weights[d]
		if cost > limit: return cost
	return cost
