class_name SplatSugarSparkle
extends RefCounted
## 四角魔法星光（凹边星，星形线 x = cos³t, y = sin³t）：糖果云 / Logo 底板 / 头像装饰共用。
## 一颗星 = 金色外晕 + 白色星体 + 金色细描边，随 pulse（0..1）呼吸：小 → 大、暗 → 亮。

const POINTS := 28
const GLOW_SCALE := 1.35
const MIN_SIZE := 0.55           ## pulse = 0 时的大小占比
const OUTLINE_WIDTH := 1.4

static var _unit: PackedVector2Array = _build()


static func _build() -> PackedVector2Array:
	var points := PackedVector2Array()
	for index: int in POINTS:
		var t: float = TAU * index / POINTS
		points.append(Vector2(pow(cos(t), 3.0), pow(sin(t), 3.0)))
	return points


## 在 canvas 的当前坐标系里画一颗星：at 中心、radius 满大小的半径、pulse 0..1、gold 金色。
static func draw(canvas: CanvasItem, at: Vector2, radius: float, pulse: float, gold: Color) -> void:
	var r: float = radius * (MIN_SIZE + (1.0 - MIN_SIZE) * pulse)
	var body := PackedVector2Array()
	var glow := PackedVector2Array()
	for point: Vector2 in _unit:
		body.append(at + point * r)
		glow.append(at + point * r * GLOW_SCALE)
	canvas.draw_colored_polygon(glow, Color(gold, 0.35 * pulse))
	canvas.draw_colored_polygon(body, Color(1.0, 1.0, 1.0, 0.55 + 0.45 * pulse))
	var ring := PackedVector2Array(body)
	ring.append(body[0])
	canvas.draw_polyline(ring, Color(gold, 0.9), OUTLINE_WIDTH, true)

