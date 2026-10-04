class_name SplatSugarCloud
extends Control
## 糖果云：圆润的花瓣云 + 内侧浅色高光（鼓鼓的糖果感）+ 几颗错开呼吸的魔法星光。头像 / 徽章后面的装饰，
## 与 Logo 底板（InkLogoArt）同一套图形语言。方形控件，随边长缩放；viewBox 200。

const VIEW := 200.0
const CENTRE := Vector2(100.0, 100.0)
const RADIUS := 62.0
const LOBES := 8
const DEPTH := 0.1
const POINTS := 96
const HIGHLIGHT_SCALE := 0.72
const HIGHLIGHT_SHIFT := Vector2(-7.0, -9.0)
const HIGHLIGHT_ALPHA := 0.5
const SPARKLES := [[26.0, 58.0, 17.0, 0.0], [176.0, 66.0, 13.0, 0.4], [30.0, 158.0, 9.0, 0.2]]   ## 3 颗，避开右下（那里是等级牌 / XP 条）
const SPARKLE_SECONDS := 1.9

var fill: Color = Color("ff8a14")
var gold: Color = Color("ffd54a")
var sparkles: bool = true          ## false = 只画云本体（开战页英雄框下沿那朵：用户不要魔法星光）
var _cloud: PackedVector2Array


static func make(colour: Color, gold_colour: Color, side: float) -> SplatSugarCloud:
	var cloud := SplatSugarCloud.new()
	cloud.fill = colour
	cloud.gold = gold_colour
	cloud.custom_minimum_size = Vector2.ONE * side
	cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cloud


func _init() -> void:
	for index: int in POINTS:
		var angle: float = TAU * index / POINTS
		_cloud.append(CENTRE + Vector2(cos(angle), sin(angle)) * RADIUS * (1.0 + DEPTH * cos(LOBES * angle)))


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var scale_factor: float = size.x / VIEW
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * scale_factor)
	draw_colored_polygon(_cloud, fill)
	var edge := PackedVector2Array(_cloud)
	edge.append(_cloud[0])
	draw_polyline(edge, fill, 1.0 / scale_factor, true)
	var inner := Transform2D().scaled(Vector2.ONE * scale_factor) * Transform2D().translated(CENTRE + HIGHLIGHT_SHIFT) * Transform2D().scaled(Vector2.ONE * HIGHLIGHT_SCALE) * Transform2D().translated(-CENTRE)
	draw_set_transform_matrix(inner)
	draw_colored_polygon(_cloud, Color(fill.lerp(Color.WHITE, 0.38), HIGHLIGHT_ALPHA))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * scale_factor)
	if not sparkles:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	for spec: Array in SPARKLES:
		var pulse: float = 0.5 - 0.5 * cos(TAU * fposmod(now / SPARKLE_SECONDS + float(spec[3]), 1.0))
		SplatSugarSparkle.draw(self, Vector2(spec[0], spec[1]), float(spec[2]), pulse, gold)

