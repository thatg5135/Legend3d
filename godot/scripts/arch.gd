## Building shells, built as real meshes rather than stacks of boxes:
## round walls with true openings for doors and windows, a stone footing,
## a timber wall plate, an overhanging thatch roof with thickness and eaves,
## rafters inside, carved lintels, door leaves and stairs.
class_name Arch
extends RefCounted

const SEGS := 40           # around a round building
const WINDOW_SILL := 1.05
const WINDOW_TOP := 1.75
const WINDOW_W := 0.9

var w: World


func _init(world: World) -> void:
	w = world


# ================================================================== mesh helpers

class MB:
	## Collects quads per material, then makes one mesh per material.
	var tools := {}   # material -> SurfaceTool

	func _st(m: Material) -> SurfaceTool:
		if not tools.has(m):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[m] = st
		return tools[m]

	## a-b-c-d counter-clockwise seen from the side that should be visible.
	func quad(m: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua := Vector2.ZERO, ub := Vector2(1, 0), uc := Vector2(1, 1), ud := Vector2(0, 1)) -> void:
		var st := _st(m)
		var nrm := (b - a).cross(d - a).normalized()
		if nrm.length() < 0.5:
			nrm = (c - b).cross(a - b).normalized()
		# Godot treats clockwise as the front, so emit a-c-b / a-d-c
		for v in [[a, ua], [c, uc], [b, ub], [a, ua], [d, ud], [c, uc]]:
			st.set_normal(nrm)
			st.set_uv(v[1])
			st.add_vertex(v[0])

	func tri(m: Material, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
		var st := _st(m)
		var nrm := (b - a).cross(c - a).normalized()
		for v in [[a, ua], [c, uc], [b, ub]]:
			st.set_normal(nrm)
			st.set_uv(v[1])
			st.add_vertex(v[0])

	func commit(parent: Node3D, cast := true) -> void:
		for m in tools:
			var mi := MeshInstance3D.new()
			mi.mesh = (tools[m] as SurfaceTool).commit()
			mi.material_override = m
			if not cast:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)


static func _ring_pt(c: Vector3, r: float, a: float, y: float) -> Vector3:
	return Vector3(c.x + cos(a) * r, c.y + y, c.z + sin(a) * r)


## Is angle `a` inside any of the [center, half_width] openings?
static func _in_gap(a: float, gaps: Array) -> bool:
	for g in gaps:
		if absf(angle_difference(a, g[0])) < g[1]:
			return true
	return false


## A curved band of wall between radii r0 (inner) and r1 (outer), heights
## y0..y1, skipping `gaps`. Outer face, inner face, top, and the jambs.
func _ring_band(mb: MB, c: Vector3, r0: float, r1: float, y0: float, y1: float, gaps: Array,
		outer_m: Material, inner_m: Material, top_m: Material) -> void:
	var step := TAU / SEGS
	for i in SEGS:
		var a0 := i * step
		var a1 := (i + 1) * step
		var mid := (a0 + a1) * 0.5
		if _in_gap(mid, gaps):
			continue
		var o00 := _ring_pt(c, r1, a0, y0)
		var o10 := _ring_pt(c, r1, a1, y0)
		var o11 := _ring_pt(c, r1, a1, y1)
		var o01 := _ring_pt(c, r1, a0, y1)
		var i00 := _ring_pt(c, r0, a0, y0)
		var i10 := _ring_pt(c, r0, a1, y0)
		var i11 := _ring_pt(c, r0, a1, y1)
		var i01 := _ring_pt(c, r0, a0, y1)
		if outer_m != null:
			mb.quad(outer_m, o10, o00, o01, o11)
		if inner_m != null:
			mb.quad(inner_m, i00, i10, i11, i01)
		if top_m != null:
			mb.quad(top_m, o01, i01, i11, o11)
		# close the wall where an opening starts or ends
		var prev_gap := _in_gap(mid - step, gaps)
		var next_gap := _in_gap(mid + step, gaps)
		var jamb := inner_m if inner_m != null else outer_m
		if prev_gap:
			mb.quad(jamb, i00, o00, o01, i01)
		if next_gap:
			mb.quad(jamb, o10, i10, i11, o11)


# ================================================================== roundhouse

## Builds a roundhouse shell. opts:
##   doors: [angle], windows: [angle] or [[angle, y_off]], outside: bool, inside: bool,
##   art: bool (painted posts, carved lintels), height: wall height for a
##   building of several storeys (defaults to the pack's wall_h), floors: [y]
##   heights of upper floors (a timber band runs round the outside there)
func roundhouse(n: Node3D, sh: Dictionary, p: Dictionary, opts: Dictionary) -> Dictionary:
	var c: Vector3 = sh["center"]
	var r := float(sh["r"])
	var h := float(opts.get("height", p["wall_h"]))
	var base_h := float(p["base_h"])
	var outside: bool = opts.get("outside", true)
	var inside: bool = opts.get("inside", true)
	var door_gap := asin(clampf((World.DOOR_W * 0.5 + 0.12) / r, 0.0, 1.0))
	var doors := []
	for a in opts.get("doors", []):
		doors.append([a, door_gap])
	var win_gap := asin(clampf((WINDOW_W * 0.5) / r, 0.0, 1.0))
	var wins := []
	for wv in opts.get("windows", []):
		if wv is Array:
			wins.append([float(wv[0]), win_gap, float(wv[1])])
		else:
			wins.append([float(wv), win_gap, 0.0])
	var all_gaps := doors + wins
	var mb := MB.new()
	var ext := w.mat(str(p["ext_wall"]))
	var foot := w.mat(str(p["ext_base"]))
	# finished houses were daubed inside; bare wattle only in huts and sheds
	var int_key := str(p["int_wall"])
	if int_key == "wattle" and str(sh.get("tier", "")) != "hut":
		int_key = "daub"
	var inn := w.mat(int_key)
	var timber := w.mat(str(p["post"]))
	var thatch := w.mat_uv(str(p["roof"]), 0.5)
	var under := w.mat_uv("thatch_under", 0.5)
	var t_wall := 0.24

	# the wall is built in horizontal bands, cut wherever a door or a window is
	var cuts := [0.0, h]
	if outside:
		cuts.append(base_h)
	for g in wins:
		cuts.append(float(g[2]) + WINDOW_SILL)
		cuts.append(float(g[2]) + WINDOW_TOP)
	cuts.sort()
	if outside:
		_ring_band(mb, c, r + t_wall - 0.02, r + t_wall + 0.14, 0.0, base_h, doors, foot, null, foot)
	for i in range(cuts.size() - 1):
		var y0: float = cuts[i]
		var y1: float = cuts[i + 1]
		if y1 - y0 < 0.001:
			continue
		var gaps := doors.duplicate()
		for g in wins:
			if float(g[2]) + WINDOW_SILL <= y0 + 0.001 and y1 <= float(g[2]) + WINDOW_TOP + 0.001:
				gaps.append(g)
		if outside and y0 >= base_h - 0.001:
			_ring_band(mb, c, r, r + t_wall, y0, y1, gaps, ext, null, null)
		if inside:
			_ring_band(mb, c, r - 0.06, r, y0, y1, gaps, null, inn, null)
	# window sills, lintels and jambs through the wall
	for g in wins:
		_opening_frame(mb, c, r - 0.06, r + t_wall, g[0], g[1], float(g[2]) + WINDOW_SILL, float(g[2]) + WINDOW_TOP, timber)
	for g in doors:
		_opening_frame(mb, c, r - 0.06, r + t_wall, g[0], g[1], 0.0, World.DOOR_H, timber)
		# the wall is cut in whole segments; patch it back to the doorway's edges
		var sp := _gap_span(all_gaps, g)
		var lo: float = g[0] + sp[0]
		var hi: float = g[0] + sp[1]
		_lintel_patch(mb, c, r, r + t_wall, (lo + hi) * 0.5, (hi - lo) * 0.5, World.DOOR_H, h,
			ext if outside else null, inn if inside else null)
		_arc_patch(mb, c, r, r + t_wall, lo, g[0] - g[1], 0.0, World.DOOR_H, ext if outside else null, inn if inside else null)
		_arc_patch(mb, c, r, r + t_wall, g[0] + g[1], hi, 0.0, World.DOOR_H, ext if outside else null, inn if inside else null)
	for g in wins:
		var sp := _gap_span(all_gaps, g)
		var wy := float(g[2])
		_arc_patch(mb, c, r, r + t_wall, g[0] + sp[0], g[0] - g[1], wy + WINDOW_SILL, wy + WINDOW_TOP, ext if outside else null, inn if inside else null)
		_arc_patch(mb, c, r, r + t_wall, g[0] + g[1], g[0] + sp[1], wy + WINDOW_SILL, wy + WINDOW_TOP, ext if outside else null, inn if inside else null)
	# a timber band round the outside where each upper floor sits
	if outside:
		for fy in opts.get("floors", []):
			_ring_band(mb, c, r + t_wall, r + t_wall + 0.07, float(fy) - 0.12, float(fy) + 0.1, doors, timber, null, timber)
	# wall plate: a timber ring the rafters sit on
	_ring_band(mb, c, r - 0.18, r + t_wall + 0.06, h, h + 0.16, [], timber, timber, timber)

	# roof: thatch with real thickness and overhanging eaves
	var pitch := float(p["roof_pitch"])
	var eave_r := r + t_wall + 0.95
	var eave_y := h - 0.25
	var apex_y := eave_y + eave_r * pitch
	var thick := 0.42
	var step := TAU / SEGS
	var slant := sqrt(eave_r * eave_r + (apex_y - eave_y) * (apex_y - eave_y))
	for i in SEGS:
		var a0 := i * step
		var a1 := (i + 1) * step
		var arc0 := a0 * eave_r
		var arc1 := a1 * eave_r
		var e0 := _ring_pt(c, eave_r, a0, eave_y)
		var e1 := _ring_pt(c, eave_r, a1, eave_y)
		var top := c + Vector3(0, apex_y, 0)
		# outer thatch surface (UV in meters: across, down the slope)
		mb.tri(thatch, e1, e0, top, Vector2(arc1, slant), Vector2(arc0, slant), Vector2((arc0 + arc1) * 0.5, 0.0))
		# the thick, trimmed edge of the eaves
		var d0 := e0 - Vector3(0, thick, 0)
		var d1 := e1 - Vector3(0, thick, 0)
		mb.quad(thatch, e0, e1, d1, d0, Vector2(arc0, 0), Vector2(arc1, 0), Vector2(arc1, thick), Vector2(arc0, thick))
		# underside, seen from inside and from under the eaves
		var top_u := c + Vector3(0, apex_y - thick * 1.6, 0)
		mb.tri(under, d0, d1, top_u, Vector2(arc0, slant), Vector2(arc1, slant), Vector2((arc0 + arc1) * 0.5, 0.0))
	if inside:
		_rafters(n, c, r, h, apex_y - thick * 1.6, timber)
	mb.commit(n)

	# invisible collision, one slab per wall segment (doors stay open)
	for i in SEGS:
		var a := (i + 0.5) * step
		if _in_gap(a, doors):
			continue
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(2.0 * (r + 0.1) * sin(step / 2) + 0.08, h, t_wall + 0.2)
		cs.shape = bs
		body.add_child(cs)
		body.position = _ring_pt(c, r + t_wall * 0.5, a, h * 0.5)
		body.rotation.y = -(a + PI / 2)
		n.add_child(body)

	# door frames outside: posts and a lintel, carved in bigger houses
	if outside:
		for g in doors:
			_door_frame(n, c, r + t_wall, g[0], p, bool(opts.get("art", false)))
	for g in wins:
		_shutters(n, c, r + t_wall, g[0], p, float(g[2]))
	return {"apex": c + Vector3(0, apex_y, 0), "eave_r": eave_r}


## The stretch of wall actually removed around gap g, as offsets from its
## center: whole segments whose middles fall inside the opening.
func _gap_span(gaps: Array, g: Array) -> Array:
	var step := TAU / SEGS
	var lo := 0.0
	var hi := 0.0
	for i in SEGS:
		var mid := (i + 0.5) * step
		var d := angle_difference(float(g[0]), mid)
		if absf(d) < float(g[1]):
			lo = minf(lo, d - step * 0.5)
			hi = maxf(hi, d + step * 0.5)
	return [lo, hi]


## A piece of curved wall between angles a0..a1 (no top or ends).
func _arc_patch(mb: MB, c: Vector3, r0: float, r1: float, a0: float, a1: float, y0: float, y1: float, outer_m: Material, inner_m: Material) -> void:
	if a1 - a0 < 0.0005:
		return
	if outer_m != null:
		mb.quad(outer_m, _ring_pt(c, r1, a1, y0), _ring_pt(c, r1, a0, y0), _ring_pt(c, r1, a0, y1), _ring_pt(c, r1, a1, y1))
	if inner_m != null:
		mb.quad(inner_m, _ring_pt(c, r0 - 0.06, a0, y0), _ring_pt(c, r0 - 0.06, a1, y0), _ring_pt(c, r0 - 0.06, a1, y1), _ring_pt(c, r0 - 0.06, a0, y1))


## Fill the wall over a doorway (between door top and wall top).
func _lintel_patch(mb: MB, c: Vector3, r0: float, r1: float, a: float, half: float, y0: float, y1: float, outer_m: Material, inner_m: Material) -> void:
	var steps := 4
	for k in steps:
		var aa0 := a - half + 2.0 * half * k / steps
		var aa1 := a - half + 2.0 * half * (k + 1) / steps
		if outer_m != null:
			mb.quad(outer_m, _ring_pt(c, r1, aa1, y0), _ring_pt(c, r1, aa0, y0), _ring_pt(c, r1, aa0, y1), _ring_pt(c, r1, aa1, y1))
		if inner_m != null:
			mb.quad(inner_m, _ring_pt(c, r0 - 0.06, aa0, y0), _ring_pt(c, r0 - 0.06, aa1, y0), _ring_pt(c, r0 - 0.06, aa1, y1), _ring_pt(c, r0 - 0.06, aa0, y1))
		var soffit: Material = outer_m if outer_m != null else inner_m
		mb.quad(soffit, _ring_pt(c, r0 - 0.06, aa0, y0), _ring_pt(c, r1, aa0, y0), _ring_pt(c, r1, aa1, y0), _ring_pt(c, r0 - 0.06, aa1, y0))


## Timber linings around an opening through the wall thickness.
func _opening_frame(mb: MB, c: Vector3, r0: float, r1: float, a: float, half: float, y0: float, y1: float, m: Material) -> void:
	var al := a - half
	var ar := a + half
	# sides
	mb.quad(m, _ring_pt(c, r0, al, y0), _ring_pt(c, r1, al, y0), _ring_pt(c, r1, al, y1), _ring_pt(c, r0, al, y1))
	mb.quad(m, _ring_pt(c, r1, ar, y0), _ring_pt(c, r0, ar, y0), _ring_pt(c, r0, ar, y1), _ring_pt(c, r1, ar, y1))
	# head
	mb.quad(m, _ring_pt(c, r0, ar, y1), _ring_pt(c, r0, al, y1), _ring_pt(c, r1, al, y1), _ring_pt(c, r1, ar, y1))
	if y0 > 0.05:  # sill
		mb.quad(m, _ring_pt(c, r0, al, y0), _ring_pt(c, r0, ar, y0), _ring_pt(c, r1 + 0.06, ar, y0), _ring_pt(c, r1 + 0.06, al, y0))


func _rafters(n: Node3D, c: Vector3, r: float, h: float, apex_y: float, m: Material) -> void:
	var count := clampi(int(r * 2.2), 8, 22)
	for i in count:
		var a := (i + 0.25) * TAU / count
		var foot := _ring_pt(c, r - 0.1, a, h + 0.12)
		var top := c + Vector3(0, apex_y - 0.12, 0)
		var mid := (foot + top) * 0.5
		var length := foot.distance_to(top)
		var mi := w.box(n, Vector3(0.12, 0.14, length), mid, m, false)
		mi.look_at_from_position(mid, top, Vector3.UP)
	# a few purlin rings tying them together
	for k: float in [0.35, 0.65]:
		var rr := (r - 0.1) * (1.0 - k)
		var yy := lerpf(h + 0.12, apex_y - 0.12, k)
		var segs := 16
		for i in segs:
			var a0 := i * TAU / segs
			var a1 := (i + 1) * TAU / segs
			var p0 := _ring_pt(c, rr, a0, yy)
			var p1 := _ring_pt(c, rr, a1, yy)
			var mi := w.box(n, Vector3(0.08, 0.08, p0.distance_to(p1) + 0.04), (p0 + p1) * 0.5, m, false)
			mi.look_at_from_position((p0 + p1) * 0.5, p1, Vector3.UP)


func _door_frame(n: Node3D, c: Vector3, r: float, a: float, p: Dictionary, carved: bool) -> void:
	var dir := Vector3(cos(a), 0, sin(a))
	var across := Vector3(-dir.z, 0, dir.x)
	var at := c + dir * (r + 0.05)
	var post := w.mat(str(p["post"]))
	for s: int in [-1, 1]:
		w.box(n, Vector3(0.22, World.DOOR_H + 0.25, 0.26), at + across * s * (World.DOOR_W * 0.5 + 0.08) + Vector3(0, (World.DOOR_H + 0.25) * 0.5, 0), post, true, -(a + PI / 2))
	var lin := w.mat("knot_band") if carved else post
	w.box(n, Vector3(World.DOOR_W + 0.6, 0.3, 0.28), at + Vector3(0, World.DOOR_H + 0.15, 0), lin, false, -(a + PI / 2))


func _shutters(n: Node3D, c: Vector3, r: float, a: float, p: Dictionary, y_off := 0.0) -> void:
	var dir := Vector3(cos(a), 0, sin(a))
	var across := Vector3(-dir.z, 0, dir.x)
	var at := c + dir * (r + 0.06)
	var wood := w.mat(str(p["door"]))
	var hgt := WINDOW_TOP - WINDOW_SILL
	for s: int in [-1, 1]:
		var leaf := w.box(n, Vector3(WINDOW_W * 0.5, hgt, 0.05), at + across * s * (WINDOW_W * 0.5 + WINDOW_W * 0.25) + dir * 0.02 + Vector3(0, y_off + WINDOW_SILL + hgt * 0.5, 0), wood, false, -(a + PI / 2))
		leaf.rotation.y += s * 0.15


# ================================================================== square buildings

## Hipped thatch roof over a rectangular footprint, with overhanging eaves.
func hip_roof(n: Node3D, sh: Dictionary, p: Dictionary) -> void:
	var c: Vector3 = sh["center"]
	var h := float(p["wall_h"])
	var pitch := float(p["roof_pitch"])
	var ex := float(sh["hx"]) + 0.9
	var ez := float(sh["hz"]) + 0.9
	var ey := h - 0.2
	var rise := minf(ex, ez) * pitch
	var ridge_half := absf(ex - ez)
	var along_x := ex >= ez
	var r0 := c + (Vector3(-ridge_half, ey + rise, 0) if along_x else Vector3(0, ey + rise, -ridge_half))
	var r1 := c + (Vector3(ridge_half, ey + rise, 0) if along_x else Vector3(0, ey + rise, ridge_half))
	var nw := c + Vector3(-ex, ey, -ez)
	var ne := c + Vector3(ex, ey, -ez)
	var se := c + Vector3(ex, ey, ez)
	var sw := c + Vector3(-ex, ey, ez)
	var th := w.mat(str(p["roof"]))
	var mb := MB.new()
	if along_x:
		mb.quad(th, nw, r0, r1, ne)
		mb.quad(th, se, r1, r0, sw)
		mb.tri(th, sw, r0, nw, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		mb.tri(th, ne, r1, se, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	else:
		mb.quad(th, ne, r0, r1, se)
		mb.quad(th, sw, r1, r0, nw)
		mb.tri(th, nw, r0, ne, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		mb.tri(th, se, r1, sw, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	# thick trimmed eaves all round
	var d := Vector3(0, -0.4, 0)
	for pair in [[nw, ne], [ne, se], [se, sw], [sw, nw]]:
		mb.quad(th, pair[1], pair[0], pair[0] + d, pair[1] + d)
	mb.quad(w.mat("thatch_under"), nw + d, ne + d, se + d, sw + d)
	mb.commit(n)


# ================================================================== doors

## A door leaf for an opening. Returns the hinge node; rotate it to open.
## `wide` makes a double door. Facing: local -Z points out of the room.
func door_leaf(parent: Node3D, at: Vector3, out_dir: Vector3, p: Dictionary, wide: bool, ironbound: bool) -> Node3D:
	var root := Node3D.new()
	root.position = at
	root.rotation.y = atan2(out_dir.x, out_dir.z) + PI
	parent.add_child(root)
	var wood := w.mat(str(p["door"]))
	var iron := w.mat("iron")
	var leaves := 2 if wide else 1
	var leaf_w := (World.DOOR_W - 0.08) / leaves
	var hinges := []
	for k in leaves:
		var side := -1.0 if k == 0 else 1.0
		var hinge := Node3D.new()
		hinge.position = Vector3(side * (World.DOOR_W * 0.5 - 0.04), 0, 0)
		root.add_child(hinge)
		var lw := leaf_w
		var cx := -side * lw * 0.5
		# planks on two ledges
		w.box_dyn(hinge, Vector3(lw, World.DOOR_H - 0.04, 0.08), Vector3(cx, (World.DOOR_H - 0.04) * 0.5, 0), wood)
		for y in [0.35, World.DOOR_H - 0.45]:
			w.box_dyn(hinge, Vector3(lw - 0.1, 0.12, 0.05), Vector3(cx, y, 0.06), wood)
		if ironbound:
			for y in [0.25, World.DOOR_H * 0.5, World.DOOR_H - 0.3]:
				w.box_dyn(hinge, Vector3(lw - 0.04, 0.07, 0.03), Vector3(cx, y, -0.055), iron)
			for k2 in 6:
				w.box_dyn(hinge, Vector3(0.05, 0.05, 0.03), Vector3(cx - lw * 0.4 + k2 * lw * 0.16, World.DOOR_H * 0.5 + 0.12, -0.07), iron)
		w.box_dyn(hinge, Vector3(0.07, 0.16, 0.05), Vector3(cx - side * (lw * 0.5 - 0.15), World.DOOR_H * 0.48, -0.07), iron)
		hinge.set_meta("side", side)
		hinges.append(hinge)
	root.set_meta("hinges", hinges)
	return root


static func set_door_open(root: Node3D, open: bool, animate: bool) -> void:
	if root == null or not is_instance_valid(root):
		return
	for hinge in root.get_meta("hinges", []):
		var hn := hinge as Node3D
		var side := float(hn.get_meta("side", 1.0))
		var target := side * deg_to_rad(95.0) if open else 0.0
		if animate and hn.is_inside_tree():
			var tw := hn.create_tween()
			tw.tween_property(hn, "rotation:y", target, 0.6).set_trans(Tween.TRANS_SINE)
		else:
			hn.rotation.y = target


# ================================================================== stairs

## A straight flight of timber stairs from `bottom` rising `rise` meters along
## `dir`. Returns the top landing position. Walkable: a hidden ramp under it.
func stairs(n: Node3D, bottom: Vector3, dir: Vector3, rise: float, p: Dictionary) -> Vector3:
	var run := rise / tan(deg_to_rad(37.0))
	var steps := int(round(rise / 0.21))
	var tread := run / steps
	var wood := w.mat(str(p["furniture"]))
	var dark := w.mat(str(p["door"]))
	var yaw := atan2(dir.x, dir.z)
	var root := Node3D.new()
	root.position = bottom
	root.rotation.y = yaw
	n.add_child(root)
	for i in steps:
		var z := (i + 0.5) * tread
		var y := (i + 1) * rise / steps
		w.box(root, Vector3(1.1, 0.06, tread + 0.04), Vector3(0, y - 0.03, z), wood, false)
		w.box(root, Vector3(1.1, rise / steps, 0.04), Vector3(0, y - rise / steps * 0.5, z - tread * 0.5), dark, false)
	# stringers and a handrail on the open side
	var slope_len := sqrt(run * run + rise * rise)
	var ang := atan2(rise, run)
	for s: int in [-1, 1]:
		var str_mi := w.box(root, Vector3(0.08, 0.28, slope_len), Vector3(s * 0.58, rise * 0.5 - 0.1, run * 0.5), dark, false)
		str_mi.rotation.x = -ang
	var rail := w.box(root, Vector3(0.06, 0.06, slope_len), Vector3(0.62, rise * 0.5 + 0.85, run * 0.5), wood, false)
	rail.rotation.x = -ang
	for k in 4:
		var t := (k + 0.5) / 4.0
		w.box(root, Vector3(0.05, 0.9, 0.05), Vector3(0.62, rise * t + 0.4, run * t), wood, false)
	# landing at the top
	w.box(root, Vector3(1.3, 0.1, 1.2), Vector3(0, rise - 0.05, run + 0.6), wood, true)
	# the walkable ramp (invisible)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.1, 0.1, slope_len + 0.1)
	cs.shape = bs
	body.add_child(cs)
	body.position = Vector3(0, rise * 0.5 - 0.05, run * 0.5)
	body.rotation.x = -ang
	root.add_child(body)
	return bottom + dir * (run + 0.6) + Vector3(0, rise, 0)


## The opening at the top of stairs coming up from below: a dark well with a rail.
func stairwell(n: Node3D, at: Vector3, dir: Vector3, p: Dictionary) -> void:
	var root := Node3D.new()
	root.position = at
	root.rotation.y = atan2(dir.x, dir.z)
	n.add_child(root)
	w.box(root, Vector3(1.3, 0.02, 2.4), Vector3(0, 0.025, 0), w.void_mat(), false)
	var wood := w.mat(str(p["furniture"]))
	for s: int in [-1, 1]:
		w.box(root, Vector3(0.06, 0.06, 2.4), Vector3(s * 0.7, 0.95, 0), wood, false)
		for k in 3:
			w.box(root, Vector3(0.05, 0.95, 0.05), Vector3(s * 0.7, 0.47, -1.1 + k * 1.1), wood, false)
	w.box(root, Vector3(1.45, 0.06, 0.06), Vector3(0, 0.95, -1.2), wood, false)
	# top steps visible going down
	for i in 3:
		w.box(root, Vector3(1.1, 0.05, 0.3), Vector3(0, -0.2 - i * 0.21, 0.9 - i * 0.28), wood, false)


# ================================================================== smoke

## Smoke curling out of the thatch above a fire.
func smoke(n: Node3D, at: Vector3, big: bool) -> CPUParticles3D:
	var ps := CPUParticles3D.new()
	ps.position = at
	ps.amount = 26 if big else 16
	ps.lifetime = 7.0
	ps.preprocess = 7.0
	ps.local_coords = false
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ps.emission_sphere_radius = 0.6 if big else 0.35
	ps.direction = Vector3(0, 1, 0)
	ps.spread = 12.0
	ps.gravity = Vector3(0.25, 0.32, 0.0)
	ps.initial_velocity_min = 0.25
	ps.initial_velocity_max = 0.5
	ps.scale_amount_min = 0.9
	ps.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(1, 2.8))
	ps.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.75, 0.73, 0.7, 0.0))
	grad.set_color(1, Color(0.6, 0.6, 0.6, 0.0))
	grad.add_point(0.12, Color(0.72, 0.7, 0.67, 0.42))
	grad.add_point(0.6, Color(0.66, 0.65, 0.63, 0.22))
	ps.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Tex.puff()
	m.disable_receive_shadows = true
	q.material = m
	ps.mesh = q
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ps.add_to_group("l3d_smoke")
	n.add_child(ps)
	return ps
