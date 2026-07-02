extends Node

# ─── Minimal Wireframe Style Kit ──────────────────────────────────────────────
# All UI drawing goes through these helpers.
# Change values here to reskin the entire game UI.

# ── Palette ───────────────────────────────────────────────────────────────────
const C_BG        := Color(0.00, 0.00, 0.00, 0.30)   # panel fill
const C_BORDER    := Color(1.00, 1.00, 1.00, 0.55)   # panel / button border
const C_BORDER_DIM := Color(1.00, 1.00, 1.00, 0.20)  # secondary border (grid cells)
const C_TEXT      := Color(1.00, 1.00, 1.00, 0.80)   # primary label
const C_TEXT_DIM  := Color(1.00, 1.00, 1.00, 0.45)   # secondary label
const C_FILL_LO   := Color(1.00, 1.00, 1.00, 0.06)   # subtle fill (cell bg)
const C_FILL_HI   := Color(1.00, 1.00, 1.00, 0.18)   # highlighted fill (btn active)
const C_OVERLAY   := Color(0.00, 0.00, 0.00, 0.55)   # full-screen dim (kept light so blur shows)
const C_BAR_BG    := Color(1.00, 1.00, 1.00, 0.10)   # progress bar track
const C_BAR_FILL  := Color(1.00, 1.00, 1.00, 0.70)   # progress bar fill (shield)
const C_BAR_HP    := Color(0.85, 0.18, 0.18, 0.90)   # HP bar fill (red kept for legibility)
const C_BAR_LINE  := Color(1.00, 1.00, 1.00, 0.25)   # progress bar border

# ── Metrics ───────────────────────────────────────────────────────────────────
const BORDER_W    := 1.0    # panel border line width
const CORNER_L    := 8.0    # L-bracket corner arm length
const FONT_SIZE_S := 11
const FONT_SIZE_M := 13
const FONT_SIZE_L := 15

# ─── Core draw helpers ─────────────────────────────────────────────────────────

# Draw a panel: dim fill + 1px border + four L-bracket corners
func draw_panel(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, C_BG)
	ci.draw_rect(rect, C_BORDER, false, BORDER_W)
	_draw_corners(ci, rect)

# Draw a panel without fill (border + corners only)
func draw_panel_outline(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, C_BORDER, false, BORDER_W)
	_draw_corners(ci, rect)

# Draw a grid cell
func draw_cell(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, C_FILL_LO)
	ci.draw_rect(rect, C_BORDER_DIM, false, BORDER_W)

# Draw a progress bar (track + fill + border)
func draw_bar(ci: CanvasItem, rect: Rect2, ratio: float, fill_col: Color) -> void:
	ci.draw_rect(rect, C_BAR_BG)
	if ratio > 0.0:
		ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), fill_col)
	ci.draw_rect(rect, C_BAR_LINE, false, BORDER_W)

# Draw a circle button
func draw_circle_btn(ci: CanvasItem, center: Vector2, radius: float, active: bool) -> void:
	var fill := C_FILL_HI if active else C_FILL_LO
	var ring := C_BORDER if active else C_BORDER_DIM
	ci.draw_circle(center, radius, fill)
	ci.draw_arc(center, radius, 0.0, TAU, 48, ring, BORDER_W)

# Draw a square button
func draw_square_btn(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, C_FILL_LO)
	ci.draw_rect(rect, C_BORDER_DIM, false, BORDER_W)

# Draw a text label using the fallback font
func draw_label(ci: CanvasItem, pos: Vector2, text: String,
		size: int = FONT_SIZE_M, col: Color = C_TEXT) -> void:
	ci.draw_string(ThemeDB.fallback_font, pos, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

# ─── Private ──────────────────────────────────────────────────────────────────
func _draw_corners(ci: CanvasItem, rect: Rect2) -> void:
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.position.x + rect.size.x
	var y1 := rect.position.y + rect.size.y
	var L  := CORNER_L
	var w  := BORDER_W + 0.5   # slightly thicker for emphasis
	var c  := C_TEXT            # full-bright corners
	# Top-left
	ci.draw_line(Vector2(x0, y0 + L), Vector2(x0, y0), c, w)
	ci.draw_line(Vector2(x0, y0), Vector2(x0 + L, y0), c, w)
	# Top-right
	ci.draw_line(Vector2(x1 - L, y0), Vector2(x1, y0), c, w)
	ci.draw_line(Vector2(x1, y0), Vector2(x1, y0 + L), c, w)
	# Bottom-left
	ci.draw_line(Vector2(x0, y1 - L), Vector2(x0, y1), c, w)
	ci.draw_line(Vector2(x0, y1), Vector2(x0 + L, y1), c, w)
	# Bottom-right
	ci.draw_line(Vector2(x1 - L, y1), Vector2(x1, y1), c, w)
	ci.draw_line(Vector2(x1, y1), Vector2(x1, y1 - L), c, w)
