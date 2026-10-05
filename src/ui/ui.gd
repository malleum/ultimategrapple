extends RefCounted
## Shared UI theme + widget helpers (all UI is built in code).

const NEON := Color(0.3, 2.0, 2.2)
const PINK := Color(2.2, 0.4, 1.6)
const GOLD := Color(2.2, 1.8, 0.4)
const DIM := Color(0.7, 0.75, 0.85)
## Time medals keep their save keys (ace / gold / silver / bronze) but are
## shown with disc golf names: gold, silver and bronze mean 1st / 2nd / 3rd
## on an online leaderboard.
const MEDAL_COLORS := {"ace": Color(2.2, 0.6, 2.0), "gold": Color(0.4, 1.9, 2.2), "silver": Color(0.6, 2.0, 0.7), "bronze": Color(0.8, 1.0, 2.2), "": Color(0.6, 0.6, 0.6)}
const MEDAL_NAMES := {"ace": "ACE", "gold": "EAGLE", "silver": "BIRDIE", "bronze": "PAR"}
const PODIUM := ["GOLD", "SILVER", "BRONZE"]
const PODIUM_COLORS := [Color(2.2, 1.8, 0.3), Color(1.5, 1.6, 1.8), Color(1.6, 0.8, 0.4)]

static var _theme: Theme = null
static var _mono: Font = null


static func mono_font() -> Font:
	if _mono == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["JetBrains Mono", "Fira Code", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
		f.font_weight = 700
		_mono = f
	return _mono


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 22
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.03, 0.02, 0.08, 0.85)
	normal.border_color = Color(0.3, 1.2, 1.4)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	normal.skew = Vector2(-0.15, 0)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.1, 0.05, 0.2, 0.95)
	hover.border_color = PINK
	hover.shadow_color = Color(1.5, 0.3, 1.2, 0.5)
	hover.shadow_size = 8
	var pressed := hover.duplicate()
	pressed.bg_color = Color(0.3, 0.05, 0.25, 1)
	var disabled := normal.duplicate()
	disabled.border_color = Color(0.3, 0.3, 0.35)
	for cls in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("focus", cls, hover)
		t.set_stylebox("disabled", cls, disabled)
		t.set_color("font_color", cls, Color(0.85, 1, 1))
		t.set_color("font_hover_color", cls, Color(1.6, 1.6, 1.6))
		t.set_color("font_pressed_color", cls, Color(1.8, 1.8, 1.8))
		t.set_color("font_focus_color", cls, Color(1.4, 1.4, 1.4))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.02, 0.01, 0.06, 0.88)
	panel.border_color = Color(0.3, 1.0, 1.2, 0.8)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.content_margin_left = 24
	panel.content_margin_right = 24
	panel.content_margin_top = 18
	panel.content_margin_bottom = 18
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var le := normal.duplicate()
	le.skew = Vector2.ZERO
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", hover.duplicate())
	t.set_stylebox("normal", "SpinBox", le)
	t.set_color("font_color", "LineEdit", Color(1, 1, 1))
	t.set_color("font_color", "Label", Color(0.9, 0.97, 1))
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Label", 4)
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(0.15, 0.3, 0.4)
	slider.content_margin_top = 4
	slider.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", slider)
	var grab := StyleBoxFlat.new()
	grab.bg_color = NEON
	grab.content_margin_top = 4
	grab.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 1.0, 1.2, 0.6)
	sb.set_corner_radius_all(3)
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb)
	var sbbg := StyleBoxFlat.new()
	sbbg.bg_color = Color(0, 0, 0, 0.3)
	t.set_stylebox("scroll", "VScrollBar", sbbg)
	_theme = t
	return t


static func label(text: String, size := 22, color := Color(0.9, 0.97, 1), align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func button(text: String, cb: Callable, size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(cb)
	b.pressed.connect(func(): Sfx.play("ui_click", 0.8))
	b.mouse_entered.connect(func(): Sfx.play("ui_hover", 0.4))
	b.focus_mode = Control.FOCUS_ALL
	return b


static func title(text: String, size := 96) -> Label:
	var l := label(text, size, Color(0.4, 2.2, 2.4), HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Color(1.4, 0.2, 1.2))
	l.add_theme_constant_override("outline_size", 10)
	return l


static func vbox(sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func slider(minv: float, maxv: float, val: float, step: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(260, 28)
	s.value_changed.connect(cb)
	return s


static func medal_color(m: String) -> Color:
	return MEDAL_COLORS.get(m, MEDAL_COLORS[""])


## "EAGLE" for "gold" etc. ("" for no medal).
static func medal_name(m: String) -> String:
	return str(MEDAL_NAMES.get(m, ""))


## Online leaderboard place 1..3 -> "GOLD" / "SILVER" / "BRONZE" ("" otherwise).
static func podium(rank: int) -> String:
	return PODIUM[rank - 1] if rank >= 1 and rank <= 3 else ""


static func podium_color(rank: int) -> Color:
	return PODIUM_COLORS[rank - 1] if rank >= 1 and rank <= 3 else DIM
