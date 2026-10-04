class_name InkProjectilePool
extends MultiMeshInstance3D

const CAPACITY: int = 700
const SAT_SIZE: Array[float] = [0.46, 0.33, 0.24, 0.17]
const FxColors = preload("res://scripts/fx/ink_fx_colors.gd")
var quality: float = 1.0
var capture_render_packets: bool = false
var render_packets: Array[Dictionary] = []

func initialize() -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var sphere := SphereMesh.new()
	sphere.radius = 1
	sphere.height = 2
	sphere.radial_segments = 12
	sphere.rings = 6
	multimesh.mesh = sphere
	multimesh.instance_count = CAPACITY
	multimesh.visible_instance_count = 0
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/fx_projectile.gdshader")
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-512, -64, -512), Vector3(1024, 200, 1024))

func render_projectiles(bullets: Array, colors: Array) -> void:
	if capture_render_packets:render_packets.clear()
	var count: int = 0
	for round in bullets:
		if count >= CAPACITY - 5:
			break
		if round["kind"] in ["bomb", "storm_pod"]:
			continue
		if is_instance_valid(round.get("mesh")):
			round["mesh"].layers = 0
		if float(round.get("delay", 0)) > 0:
			continue
		var velocity: Vector3 = round["velocity"]
		var speed: float = velocity.length()
		var dir: Vector3 = velocity / speed if speed > 0.001 else Vector3(0, 0, 1)
		var reference: Vector3 = Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
		var tangent: Vector3 = reference.cross(dir).normalized()
		var basis := Basis(tangent, dir.cross(tangent), dir)
		var age: float = float(round["age"])
		var grow: float = minf(1.0, age * 20.0)
		var radius: float = float(round.get("vis", 0.1))
		var visible_radius: float = radius * grow * (1.0 + 0.3 * sin(grow * PI))
		var tail: float = float(round.get("tail0", 0.8)) + minf(float(round.get("tail_k", 1.3)), speed * 0.04) * grow
		var wobble: float = float(round.get("wob", 0.04))
		var bright: float = 1.0
		if round["kind"] == "blaster":
			var t: float = smoothstep(0.8, 1.0, age / maxf(age + float(round["life"]), 0.001))
			visible_radius *= 1.0 + 0.34 * t
			wobble *= 1.0 + 2.4 * t
			bright = 1.0 + 0.9 * t
			tail *= 1.0 - 0.55 * t
		var seed: float = float(round.get("seed", 0.5))
		var phase: float = seed * 40.0 + age * float(round.get("wob_f", 20))
		var color: Color = FxColors.from_srgb(colors[int(round["team"]) % colors.size()]) if not colors.is_empty() else Color.WHITE
		var head_color := Color(color.r * bright, color.g * bright, color.b * bright, 1)
		multimesh.set_instance_transform(count, Transform3D(basis.scaled(Vector3.ONE * maxf(0.001, visible_radius)), round["pos"]))
		multimesh.set_instance_color(count, head_color)
		if capture_render_packets:render_packets.append({"color":head_color,"head":true})
		multimesh.set_instance_custom_data(count, Color(tail, wobble, phase, float(round.get("nose", 0.3))))
		count += 1
		var satellites: int = mini(int(round.get("sats", 3)), 1 if quality <= 0.4 else 2 if quality <= 0.7 else 4)
		if speed < 4:
			continue
		var travelled: float = Vector3(round["pos"]).distance_to(round.get("start", round["pos"]))
		var spk: float = 0.55 + 0.45 * minf(1.0, speed / 25.0)
		var fade: float = 1.0 - 0.45 * minf(1.0, age / maxf(age + float(round["life"]), 0.001))
		for i in range(satellites):
			if count >= CAPACITY:
				break
			var behind: float = radius * (tail + 1.15 + float(i) * 1.8) * spk
			if travelled < behind + radius * 1.6:
				break
			var ph: float = seed * 31.0 + float(i) * 2.4 + age * 11.0
			var lateral: float = radius * (0.16 + float(i) * 0.16)
			var p: Vector3 = round["pos"] - dir * behind + tangent * sin(ph) * lateral + basis.y * cos(ph * 1.3) * lateral
			var size: float = radius * SAT_SIZE[i] * fade * (1.0 + 0.14 * sin(ph * 2.1))
			multimesh.set_instance_transform(count, Transform3D(basis.scaled(Vector3.ONE * size), p))
			multimesh.set_instance_color(count, color)
			if capture_render_packets:render_packets.append({"color":color,"head":false})
			multimesh.set_instance_custom_data(count, Color(1.3 + 0.25 * spk, 0.05, ph * 3.0, 0))
			count += 1
	multimesh.visible_instance_count = count

func clear() -> void:
	render_packets.clear()
	if multimesh:
		multimesh.visible_instance_count = 0
