"""
Build Brainrot Arena props in Blender and export them for Roblox Studio.

1 Blender unit = 1 Roblox stud. Each prop sits on the ground, centered at the origin.

Run every prop:

    blender --background --python make_props.py

Run a few:

    blender --background --python make_props.py -- --only Sword,Mace,Axe

FBX and GLB files land in blender/exports/ next to this script.
Import the FBX with Studio: File -> Import 3D. Turn on Upload to Roblox, then save the place.
"""

from __future__ import annotations

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(SCRIPT_DIR, "exports")

WOOD = (0.45, 0.28, 0.14)
WOOD_DARK = (0.28, 0.16, 0.08)
PLANK = (0.62, 0.42, 0.22)
GOLD = (0.85, 0.65, 0.22)
MARBLE = (0.86, 0.83, 0.76)
STONE = (0.42, 0.40, 0.37)
STONE_DARK = (0.25, 0.23, 0.21)
SAND = (0.72, 0.55, 0.32)
RED = (0.62, 0.10, 0.12)
CREAM = (0.93, 0.90, 0.84)
METAL = (0.55, 0.56, 0.58)
METAL_DARK = (0.12, 0.12, 0.13)
BLUE = (0.15, 0.35, 0.72)
WATER = (0.15, 0.45, 0.62)
ROPE = (0.72, 0.60, 0.38)
GRASS = (0.28, 0.52, 0.24)


def material(name: str, color: tuple, metallic: float = 0.0, roughness: float = 0.5, emission: float = 0.0):
	# Unique name so FBX slots survive Roblox Import 3D (duplicate names collapse to white).
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	# Viewport / legacy FBX diffuse — Studio often reads this when Principled fails.
	mat.diffuse_color = (color[0], color[1], color[2], 1.0)
	mat.metallic = metallic
	mat.roughness = roughness
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
	bsdf.inputs["Metallic"].default_value = metallic
	bsdf.inputs["Roughness"].default_value = roughness
	if emission > 0 and "Emission Strength" in bsdf.inputs:
		color_input = "Emission Color" if "Emission Color" in bsdf.inputs else "Emission"
		if color_input in bsdf.inputs:
			bsdf.inputs[color_input].default_value = (color[0], color[1], color[2], 1.0)
		bsdf.inputs["Emission Strength"].default_value = emission
	return mat


def new_object(name: str, mesh: bpy.types.Mesh, mat) -> bpy.types.Object:
	if mat is not None and mesh.materials.get(mat.name) is None:
		mesh.materials.append(mat)
	obj = bpy.data.objects.new(name, mesh)
	bpy.context.scene.collection.objects.link(obj)
	return obj


def finish_mesh(bm: bmesh.types.BMesh, name: str, smooth: bool = False) -> bpy.types.Mesh:
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	if smooth:
		for poly in mesh.polygons:
			poly.use_smooth = True
	return mesh


def box(name: str, size: tuple, location: tuple, mat, rotation: tuple = (0, 0, 0), bevel: float = 0.0) -> bpy.types.Object:
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	sx, sy, sz = size
	for vert in bm.verts:
		vert.co.x *= sx
		vert.co.y *= sy
		vert.co.z *= sz
	if bevel > 0:
		safe = min(bevel, sx * 0.2, sy * 0.2, sz * 0.2)
		if safe > 0.004:
			bm.edges.ensure_lookup_table()
			bmesh.ops.bevel(bm, geom=list(bm.edges), offset=safe, segments=1, profile=0.5, affect="EDGES")
	mesh = finish_mesh(bm, name, smooth=False)
	obj = new_object(name, mesh, mat)
	obj.location = location
	obj.rotation_euler = rotation
	return obj


def cylinder(name: str, radius: float, depth: float, location: tuple, mat, rotation: tuple = (0, 0, 0), segments: int = 20) -> bpy.types.Object:
	bm = bmesh.new()
	bmesh.ops.create_cone(
		bm,
		cap_ends=True,
		segments=segments,
		radius1=radius,
		radius2=radius,
		depth=depth,
	)
	mesh = finish_mesh(bm, name, smooth=True)
	obj = new_object(name, mesh, mat)
	obj.location = location
	obj.rotation_euler = rotation
	return obj


def cone(name: str, radius: float, depth: float, location: tuple, mat, rotation: tuple = (0, 0, 0), segments: int = 8) -> bpy.types.Object:
	bm = bmesh.new()
	bmesh.ops.create_cone(
		bm,
		cap_ends=True,
		segments=segments,
		radius1=radius,
		radius2=0.0,
		depth=depth,
	)
	mesh = finish_mesh(bm, name, smooth=True)
	obj = new_object(name, mesh, mat)
	obj.location = location
	obj.rotation_euler = rotation
	return obj


def sphere(name: str, radius: float, location: tuple, mat, scale: tuple = (1, 1, 1), segments: int = 16) -> bpy.types.Object:
	bm = bmesh.new()
	bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=max(8, segments // 2), radius=radius)
	mesh = finish_mesh(bm, name, smooth=True)
	obj = new_object(name, mesh, mat)
	obj.location = location
	obj.scale = scale
	return obj


def rock(name: str, radius: float, location: tuple, mat, seed: int, scale: tuple = (1, 1, 0.75)) -> bpy.types.Object:
	bm = bmesh.new()
	bmesh.ops.create_icosphere(bm, subdivisions=2, radius=radius)
	rng = random.Random(seed)
	for vert in bm.verts:
		vert.co *= 1.0 + rng.uniform(-0.16, 0.2)
		vert.co.x *= scale[0]
		vert.co.y *= scale[1]
		vert.co.z *= scale[2]
	mesh = finish_mesh(bm, name, smooth=True)
	obj = new_object(name, mesh, mat)
	obj.location = location
	return obj


def tapered_blade(name: str, length: float, width: float, thickness: float, mat, tip: float = 0.22) -> bpy.types.Object:
	bm = bmesh.new()
	steps = 8
	rings = []
	for i in range(steps + 1):
		t = i / steps
		w = width * (1.0 - t * 0.82)
		z = t * length
		ring = [
			bm.verts.new((-w / 2, -thickness / 2, z)),
			bm.verts.new((w / 2, -thickness / 2, z)),
			bm.verts.new((w / 2, thickness / 2, z)),
			bm.verts.new((-w / 2, thickness / 2, z)),
		]
		rings.append(ring)
	point = bm.verts.new((0.0, 0.0, length + tip))
	bm.faces.new(rings[0])
	for i in range(steps):
		a = rings[i]
		b = rings[i + 1]
		for k in range(4):
			bm.faces.new((a[k], b[k], b[(k + 1) % 4], a[(k + 1) % 4]))
	top = rings[-1]
	for k in range(4):
		bm.faces.new((top[k], point, top[(k + 1) % 4]))
	mesh = finish_mesh(bm, name, smooth=False)
	return new_object(name, mesh, mat)


def axe_head_mesh(name: str, mat) -> bpy.types.Object:
	"""A bearded axe head, edge pointing +X, sitting around local Z."""
	bm = bmesh.new()
	# Profile in XZ, extruded on Y.
	profile = [
		(0.05, 0.15),
		(0.85, 0.55),
		(1.15, 0.35),
		(1.2, 0.05),
		(0.95, -0.15),
		(0.55, -0.55),
		(0.15, -0.35),
		(0.0, -0.05),
	]
	half = 0.07
	front = [bm.verts.new((x, -half, z)) for x, z in profile]
	back = [bm.verts.new((x, half, z)) for x, z in profile]
	bm.faces.new(front)
	bm.faces.new(list(reversed(back)))
	for i in range(len(profile)):
		j = (i + 1) % len(profile)
		bm.faces.new((front[i], front[j], back[j], back[i]))
	mesh = finish_mesh(bm, name, smooth=False)
	return new_object(name, mesh, mat)


def wave_rug(name: str, length: float, width: float, mat) -> bpy.types.Object:
	bm = bmesh.new()
	div_x, div_y = 18, 8
	grid = []
	for iy in range(div_y + 1):
		row = []
		for ix in range(div_x + 1):
			x = -length / 2 + length * ix / div_x
			y = -width / 2 + width * iy / div_y
			z = math.sin(ix / div_x * math.pi * 2.0) * 0.08 + math.sin(iy / div_y * math.pi) * 0.03
			row.append(bm.verts.new((x, y, z)))
		grid.append(row)
	for iy in range(div_y):
		for ix in range(div_x):
			bm.faces.new((grid[iy][ix], grid[iy][ix + 1], grid[iy + 1][ix + 1], grid[iy + 1][ix]))
	# Give the cloth a little thickness by solidifying downward.
	geom = list(bm.faces) + list(bm.edges) + list(bm.verts)
	bmesh.ops.solidify(bm, geom=geom, thickness=0.06)
	mesh = finish_mesh(bm, name, smooth=True)
	return new_object(name, mesh, mat)


def kick_deck(name: str, length: float, width: float, mat) -> bpy.types.Object:
	bm = bmesh.new()
	div_x = 16
	div_y = 4
	thickness = 0.09
	grid_top = []
	grid_bot = []
	for iy in range(div_y + 1):
		top_row = []
		bot_row = []
		for ix in range(div_x + 1):
			x = -length / 2 + length * ix / div_x
			y = -width / 2 + width * iy / div_y
			along = abs(x) / (length / 2)
			kick = max(0.0, (along - 0.62) / 0.38) ** 1.4 * 0.28
			pinch = 1.0 - max(0.0, (along - 0.78)) * 0.35
			yy = y * pinch
			top_row.append(bm.verts.new((x, yy, thickness + kick)))
			bot_row.append(bm.verts.new((x, yy, kick)))
		grid_top.append(top_row)
		grid_bot.append(bot_row)
	for iy in range(div_y):
		for ix in range(div_x):
			bm.faces.new((grid_top[iy][ix], grid_top[iy + 1][ix], grid_top[iy + 1][ix + 1], grid_top[iy][ix + 1]))
			bm.faces.new((grid_bot[iy][ix], grid_bot[iy][ix + 1], grid_bot[iy + 1][ix + 1], grid_bot[iy + 1][ix]))
	for ix in range(div_x):
		bm.faces.new((grid_top[0][ix], grid_top[0][ix + 1], grid_bot[0][ix + 1], grid_bot[0][ix]))
		bm.faces.new((grid_top[div_y][ix + 1], grid_top[div_y][ix], grid_bot[div_y][ix], grid_bot[div_y][ix + 1]))
	for iy in range(div_y):
		bm.faces.new((grid_top[iy][0], grid_bot[iy][0], grid_bot[iy + 1][0], grid_top[iy + 1][0]))
		bm.faces.new((grid_top[iy + 1][div_x], grid_bot[iy + 1][div_x], grid_bot[iy][div_x], grid_top[iy][div_x]))
	mesh = finish_mesh(bm, name, smooth=True)
	return new_object(name, mesh, mat)


def reset_scene():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	scene = bpy.context.scene
	scene.unit_settings.system = "NONE"
	scene.unit_settings.scale_length = 1.0


def bake(obj: bpy.types.Object):
	mesh = obj.data
	if mesh is None:
		return
	mesh.transform(obj.matrix_world)
	obj.matrix_world = Matrix.Identity(4)


def ground_and_export(prop_name: str, objects: list):
	xs, ys, zs = [], [], []
	for obj in objects:
		for corner in obj.bound_box:
			world = obj.matrix_world @ Vector(corner)
			xs.append(world.x)
			ys.append(world.y)
			zs.append(world.z)
	shift = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs)))
	for obj in objects:
		obj.location -= shift
	bpy.context.view_layer.update()
	for obj in objects:
		bake(obj)

	root = bpy.data.objects.new(prop_name, None)
	root.empty_display_type = "PLAIN_AXES"
	root.empty_display_size = 1.0
	bpy.context.scene.collection.objects.link(root)
	for obj in objects:
		world = obj.matrix_world.copy()
		obj.parent = root
		obj.matrix_world = world

	bpy.ops.object.select_all(action="DESELECT")
	root.select_set(True)
	for obj in objects:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = root

	os.makedirs(OUT_DIR, exist_ok=True)
	fbx_path = os.path.join(OUT_DIR, prop_name + ".fbx")
	glb_path = os.path.join(OUT_DIR, prop_name + ".glb")
	bpy.ops.export_scene.fbx(
		filepath=fbx_path,
		use_selection=True,
		apply_scale_options="FBX_SCALE_NONE",
		axis_forward="Z",
		axis_up="Y",
		object_types={"EMPTY", "MESH"},
		mesh_smooth_type="FACE",
		bake_anim=False,
		use_mesh_modifiers=True,
	)
	gltf_kwargs = dict(
		filepath=glb_path,
		export_format="GLB",
		use_selection=True,
		export_apply=True,
		export_yup=True,
	)
	# Blender 4 packaging sometimes lacks Draco; skip compression when available.
	try:
		bpy.ops.export_scene.gltf(**gltf_kwargs, export_draco_mesh_compression_enable=False)
	except TypeError:
		bpy.ops.export_scene.gltf(**gltf_kwargs)
	print(f"[make_props] {prop_name} -> {fbx_path}")


def rx(degrees: float) -> tuple:
	return (math.radians(degrees), 0.0, 0.0)


def ry(degrees: float) -> tuple:
	return (0.0, math.radians(degrees), 0.0)


def rz(degrees: float) -> tuple:
	return (0.0, 0.0, math.radians(degrees))


# // Props -----------------------------------------------------------------------

def build_skateboard():
	deck_mat = material("Deck", (0.75, 0.28, 0.12), roughness=0.45)
	grip_mat = material("Grip", (0.08, 0.08, 0.09), roughness=0.85)
	metal_mat = material("TruckMetal", METAL, metallic=0.9, roughness=0.25)
	wheel_mat = material("Wheel", METAL_DARK, roughness=0.6)
	hub_mat = material("Hub", (0.85, 0.25, 0.1), roughness=0.4)
	parts = [kick_deck("Deck", 3.1, 0.82, deck_mat)]
	parts.append(box("Grip", (2.2, 0.62, 0.015), (0, 0, 0.2), grip_mat))
	parts.append(box("Stripe", (1.6, 0.08, 0.02), (0, 0, 0.205), material("Stripe", GOLD, metallic=0.4, roughness=0.3)))
	for x in (-0.85, 0.85):
		parts.append(box("Truck", (0.42, 0.62, 0.12), (x, 0, 0.02), metal_mat, bevel=0.01))
		parts.append(cylinder("Axle", 0.045, 0.78, (x, 0, -0.06), metal_mat, rotation=rx(90), segments=12))
		for y in (-0.32, 0.32):
			parts.append(cylinder("Wheel", 0.18, 0.16, (x, y, -0.06), wheel_mat, rotation=rx(90), segments=16))
			parts.append(cylinder("Hub", 0.07, 0.18, (x, y, -0.06), hub_mat, rotation=rx(90), segments=12))
	return parts


def build_magic_carpet():
	rug_mat = material("Rug", (0.55, 0.08, 0.16), roughness=0.75)
	border_mat = material("RugBorder", GOLD, metallic=0.6, roughness=0.35)
	field_mat = material("RugField", (0.28, 0.05, 0.38), roughness=0.7)
	parts = [wave_rug("Rug", 4.8, 2.7, rug_mat)]
	parts.append(box("Border", (4.95, 2.85, 0.03), (0, 0, -0.02), border_mat))
	parts.append(box("Field", (3.3, 1.5, 0.02), (0, 0, 0.08), field_mat))
	parts.append(cylinder("Medallion", 0.42, 0.03, (0, 0, 0.1), material("Medallion", GOLD, metallic=0.7, roughness=0.25, emission=0.4), segments=16))
	for x in (-1.05, 1.05):
		parts.append(box("Band", (0.18, 1.35, 0.02), (x, 0, 0.09), border_mat))
	tassel_mat = material("Tassel", GOLD, metallic=0.3, roughness=0.45)
	for i in range(-4, 5):
		x = i * 0.48
		parts.append(cone("TasselFront", 0.045, 0.45, (x, 1.45, -0.12), tassel_mat, rotation=rx(180)))
		parts.append(cone("TasselBack", 0.045, 0.45, (x, -1.45, -0.12), tassel_mat, rotation=rx(180)))
	return parts


def build_plane():
	body_mat = material("Fuselage", CREAM, roughness=0.35)
	red_mat = material("PlaneRed", (0.7, 0.1, 0.1), roughness=0.4)
	metal_mat = material("PlaneMetal", METAL_DARK, metallic=0.85, roughness=0.3)
	glass_mat = material("Glass", (0.6, 0.8, 0.95), roughness=0.1)
	seat_mat = material("Seat", (0.15, 0.16, 0.2), roughness=0.7)
	parts = []
	parts.append(sphere("Fuselage", 1.0, (0, 0.2, 1.15), body_mat, scale=(1.05, 2.6, 0.85), segments=20))
	parts.append(sphere("Nose", 0.7, (0, -2.5, 1.05), red_mat, scale=(0.9, 1.3, 0.75), segments=16))
	parts.append(cylinder("Cowl", 0.55, 0.35, (0, -3.15, 1.0), metal_mat, rotation=rx(90), segments=16))
	parts.append(box("Wing", (13.5, 2.1, 0.12), (0, -0.2, 0.85), red_mat, bevel=0.02))
	parts.append(box("WingTipL", (0.12, 1.8, 0.55), (-6.7, -0.2, 1.15), material("Tip", GOLD, metallic=0.5, roughness=0.3)))
	parts.append(box("WingTipR", (0.12, 1.8, 0.55), (6.7, -0.2, 1.15), material("TipR", GOLD, metallic=0.5, roughness=0.3)))
	parts.append(box("TailFin", (0.1, 1.2, 1.8), (0, 2.7, 1.9), red_mat))
	parts.append(box("TailWing", (3.6, 0.9, 0.1), (0, 2.55, 1.15), red_mat))
	parts.append(box("Seat", (1.1, 0.9, 0.35), (0, 0.15, 1.35), seat_mat))
	parts.append(box("Windshield", (1.5, 0.08, 0.7), (0, -1.15, 1.7), glass_mat, rotation=rx(-25)))
	parts.append(cylinder("PropHub", 0.18, 0.2, (0, -3.4, 1.0), metal_mat, rotation=rx(90)))
	parts.append(box("PropA", (0.12, 0.08, 2.6), (0, -3.55, 1.0), body_mat))
	parts.append(box("PropB", (2.6, 0.08, 0.12), (0, -3.55, 1.0), metal_mat))
	for x in (-0.7, 0.7):
		parts.append(cylinder("Gear", 0.04, 0.7, (x, -0.4, 0.35), metal_mat, segments=8))
		parts.append(cylinder("GearWheel", 0.16, 0.1, (x, -0.4, 0.0), material("Tire", METAL_DARK, roughness=0.7), rotation=ry(90), segments=12))
	return parts


def build_sword():
	steel = material("Steel", (0.78, 0.8, 0.84), metallic=0.95, roughness=0.18)
	gold_mat = material("SwordGold", GOLD, metallic=0.85, roughness=0.28)
	wrap = material("Wrap", (0.4, 0.08, 0.08), roughness=0.6)
	wood_mat = material("GripWood", WOOD_DARK, roughness=0.55)
	gem = material("Gem", (0.3, 0.65, 1.0), roughness=0.15, emission=0.8)
	blade = tapered_blade("Blade", 2.15, 0.26, 0.05, steel, tip=0.2)
	blade.location = (0, 0, 0.35)
	parts = [blade]
	parts.append(cylinder("Fuller", 0.012, 1.7, (0, 0.02, 1.25), material("Fuller", (0.45, 0.48, 0.52), metallic=0.8, roughness=0.3), segments=6))
	parts.append(box("Guard", (1.05, 0.16, 0.1), (0, 0, 0.32), gold_mat, bevel=0.015))
	parts.append(sphere("QuillonL", 0.07, (-0.5, 0, 0.38), gold_mat, segments=10))
	parts.append(sphere("QuillonR", 0.07, (0.5, 0, 0.38), gold_mat, segments=10))
	parts.append(cylinder("Grip", 0.07, 0.7, (0, 0, -0.08), wood_mat, segments=12))
	for i in range(4):
		parts.append(cylinder("WrapRing", 0.085, 0.06, (0, 0, -0.28 + i * 0.14), wrap, segments=12))
	parts.append(sphere("Pommel", 0.11, (0, 0, -0.5), gold_mat, segments=12))
	parts.append(sphere("Gem", 0.045, (0, 0.08, -0.5), gem, segments=8))
	return parts


def build_mace():
	wood_mat = material("Haft", WOOD, roughness=0.55)
	steel = material("MaceSteel", (0.5, 0.52, 0.56), metallic=0.92, roughness=0.22)
	gold_mat = material("MaceGold", GOLD, metallic=0.8, roughness=0.3)
	wrap = material("MaceWrap", METAL_DARK, roughness=0.5)
	parts = [cylinder("Haft", 0.07, 2.0, (0, 0, 1.0), wood_mat, segments=12)]
	for i in range(5):
		parts.append(cylinder("Grip", 0.09, 0.06, (0, 0, 0.35 + i * 0.12), wrap, segments=10))
	parts.append(sphere("Butt", 0.1, (0, 0, 0.05), gold_mat, segments=10))
	parts.append(cylinder("Collar", 0.11, 0.1, (0, 0, 1.95), gold_mat, segments=12))
	parts.append(sphere("Head", 0.42, (0, 0, 2.4), steel, segments=18))
	for i in range(8):
		angle = i * math.pi / 4
		x = math.cos(angle) * 0.38
		y = math.sin(angle) * 0.38
		parts.append(box("Flange", (0.08, 0.28, 0.55), (x, y, 2.4), steel, rotation=rz(math.degrees(angle))))
	parts.append(cone("Spike", 0.06, 0.35, (0, 0, 2.85), steel, segments=8))
	return parts


def build_axe():
	wood_mat = material("AxeHaft", WOOD, roughness=0.5)
	steel = material("AxeSteel", (0.62, 0.64, 0.68), metallic=0.93, roughness=0.2)
	wrap = material("AxeWrap", (0.35, 0.08, 0.08), roughness=0.55)
	parts = [cylinder("Haft", 0.065, 2.4, (0, 0, 1.2), wood_mat, segments=12)]
	for i in range(4):
		parts.append(cylinder("Wrap", 0.08, 0.05, (0, 0, 0.45 + i * 0.12), wrap, segments=10))
	head = axe_head_mesh("Bit", steel)
	head.location = (0.05, 0, 2.15)
	parts.append(head)
	parts.append(cylinder("Collar", 0.1, 0.16, (0, 0, 2.15), material("AxeCollar", METAL_DARK, metallic=0.8, roughness=0.35), segments=12))
	parts.append(box("Poll", (0.22, 0.16, 0.28), (-0.12, 0, 2.15), steel, bevel=0.01))
	return parts


def build_fishing_dock():
	plank_a = material("PlankA", PLANK, roughness=0.6)
	plank_b = material("PlankB", WOOD, roughness=0.62)
	dark = material("Piling", WOOD_DARK, roughness=0.55)
	rope_mat = material("Rope", ROPE, roughness=0.7)
	metal_mat = material("DockMetal", METAL, metallic=0.85, roughness=0.3)
	lantern_mat = material("Lantern", (1.0, 0.72, 0.3), roughness=0.3, emission=2.0)
	sign_mat = material("SignBoard", (0.12, 0.07, 0.04), roughness=0.5)
	gold_mat = material("SignGold", GOLD, metallic=0.75, roughness=0.3)
	parts = []
	for i in range(10):
		z = -6.5 + i * 1.35
		mat = plank_a if i % 2 == 0 else plank_b
		parts.append(box("Plank", (5.2, 1.15, 0.22), (0, z, 0.7), mat, bevel=0.01))
	parts.append(box("StringerL", (0.35, 13.2, 0.35), (-2.15, -0.4, 0.4), dark))
	parts.append(box("StringerR", (0.35, 13.2, 0.35), (2.15, -0.4, 0.4), dark))
	for x in (-2.15, 2.15):
		for y in (-6.2, -2.2, 1.8, 5.6):
			parts.append(cylinder("Piling", 0.22, 4.5, (x, y, -1.2), dark, segments=8))
		parts.append(cylinder("Rail", 0.06, 12.4, (x, -0.2, 1.7), rope_mat, rotation=rx(90), segments=8))
		parts.append(cylinder("RailLow", 0.045, 12.4, (x, -0.2, 1.25), rope_mat, rotation=rx(90), segments=8))
		for y in (-6.0, -2.0, 2.0, 5.4):
			parts.append(cylinder("RailPost", 0.08, 1.3, (x, y, 1.35), dark, segments=8))
	parts.append(cylinder("LampPost", 0.08, 3.2, (-2.2, -6.2, 2.3), metal_mat, segments=8))
	parts.append(box("Lamp", (0.45, 0.45, 0.6), (-2.2, -6.2, 4.0), lantern_mat))
	parts.append(box("Crate", (1.3, 1.15, 0.9), (-1.3, 2.4, 1.25), plank_b, bevel=0.02))
	parts.append(cylinder("Bucket", 0.32, 0.7, (1.4, 1.6, 1.15), metal_mat, segments=12))
	parts.append(cylinder("Coil", 0.22, 0.16, (1.5, -2.2, 0.9), rope_mat, segments=12))
	parts.append(cylinder("Rod", 0.035, 3.2, (2.15, 0.8, 2.2), dark, rotation=(0.4, 0, 0.3), segments=6))
	parts.append(box("DockSign", (4.4, 0.18, 1.5), (0, -6.6, 3.3), sign_mat))
	parts.append(box("DockSignFrame", (4.9, 0.1, 1.95), (0, -6.7, 3.3), gold_mat))
	water = material("Water", WATER, roughness=0.15)
	parts.append(box("Water", (16, 10, 0.2), (0, 6.5, -0.4), water))
	return parts


def build_gold_mine():
	rock_mat = material("Rock", STONE, roughness=0.85)
	rock_dark = material("RockDark", STONE_DARK, roughness=0.9)
	wood_mat = material("MineWood", WOOD, roughness=0.55)
	gold_mat = material("Ore", GOLD, metallic=0.75, roughness=0.3, emission=0.35)
	metal_mat = material("RailMetal", METAL, metallic=0.9, roughness=0.25)
	sign_mat = material("MineSign", (0.1, 0.06, 0.03), roughness=0.5)
	parts = []
	parts.append(rock("Hill", 4.2, (0, -1.2, 2.2), rock_mat, seed=3, scale=(1.5, 1.1, 0.85)))
	parts.append(rock("HillL", 2.2, (-4.2, -1.5, 1.3), rock_dark, seed=7, scale=(1.2, 1.0, 0.7)))
	parts.append(rock("HillR", 1.8, (4.4, -0.8, 1.1), rock_mat, seed=11, scale=(1.1, 1.2, 0.65)))
	parts.append(box("Mouth", (3.4, 0.8, 2.8), (0, 2.4, 1.5), material("Mouth", (0.03, 0.02, 0.015), roughness=1.0)))
	parts.append(box("Lintel", (4.6, 0.5, 0.45), (0, 2.7, 3.05), wood_mat, bevel=0.02))
	parts.append(cylinder("PostL", 0.22, 3.0, (-1.9, 2.7, 1.5), wood_mat, segments=8))
	parts.append(cylinder("PostR", 0.22, 3.0, (1.9, 2.7, 1.5), wood_mat, segments=8))
	for i in range(5):
		angle = -0.6 + i * 0.35
		parts.append(box("Vein", (0.55, 0.2, 0.35), (math.sin(angle) * 3.2, math.cos(angle) * 1.4 - 0.5, 2.2 + (i % 2) * 0.6), gold_mat))
	for i in range(7):
		parts.append(box("Tie", (2.2, 0.35, 0.16), (0, 2.6 + i * 1.15, 0.12), wood_mat))
	for x in (-0.55, 0.55):
		parts.append(box("Rail", (0.1, 8.2, 0.1), (x, 6.0, 0.28), metal_mat))
	parts.append(box("CartBed", (1.7, 2.3, 0.18), (0, 7.2, 0.55), wood_mat))
	parts.append(box("CartSideL", (0.12, 2.3, 0.7), (-0.8, 7.2, 0.95), wood_mat))
	parts.append(box("CartSideR", (0.12, 2.3, 0.7), (0.8, 7.2, 0.95), wood_mat))
	parts.append(box("CartFront", (1.7, 0.12, 0.7), (0, 6.1, 0.95), wood_mat))
	parts.append(box("CartBack", (1.7, 0.12, 0.7), (0, 8.3, 0.95), wood_mat))
	parts.append(rock("GoldPile", 0.55, (0, 7.2, 1.15), gold_mat, seed=2, scale=(1.3, 0.9, 0.55)))
	for x in (-0.7, 0.7):
		for y in (6.5, 7.9):
			parts.append(cylinder("Wheel", 0.22, 0.12, (x, y, 0.28), metal_mat, rotation=ry(90), segments=12))
	parts.append(box("Lantern", (0.4, 0.4, 0.55), (-2.4, 2.8, 3.3), material("MineLamp", (1, 0.7, 0.25), emission=2.0)))
	parts.append(box("Sign", (5.2, 0.2, 1.6), (0, 2.9, 4.3), sign_mat))
	parts.append(box("SignFrame", (5.7, 0.12, 2.05), (0, 3.0, 4.3), material("MineFrame", GOLD, metallic=0.7, roughness=0.3)))
	return parts


def build_vendor_stall():
	wood_mat = material("StallWood", WOOD, roughness=0.55)
	dark = material("StallDark", WOOD_DARK, roughness=0.5)
	red_mat = material("AwningRed", RED, roughness=0.65)
	cream_mat = material("AwningCream", CREAM, roughness=0.65)
	gold_mat = material("StallGold", GOLD, metallic=0.7, roughness=0.3)
	parts = []
	parts.append(box("Floor", (16, 9, 0.35), (0, 0, 0.18), dark))
	parts.append(box("Rug", (14, 7, 0.06), (0, -0.2, 0.4), red_mat))
	for i, x in enumerate([n * 1.6 - 6.4 for n in range(9)]):
		color_mat = red_mat if i % 2 == 0 else cream_mat
		parts.append(box("Stripe", (1.45, 8.4, 0.12), (x, -0.3, 6.4), color_mat))
	parts.append(box("Valence", (15.2, 0.25, 0.55), (0, -4.4, 5.9), red_mat))
	for x in (-7.6, 7.6):
		for y in (-4.2, 3.8):
			parts.append(cylinder("Post", 0.18, 6.2, (x, y, 3.2), wood_mat, segments=8))
			parts.append(box("Cap", (0.5, 0.5, 0.22), (x, y, 6.4), gold_mat))
	parts.append(box("Counter", (14, 1.5, 0.9), (0, 3.2, 1.0), wood_mat, bevel=0.02))
	parts.append(box("Cloth", (14.2, 1.7, 0.08), (0, 3.2, 1.48), red_mat))
	for i in range(6):
		x = -7.5 + i * 3.0
		parts.append(cylinder("Plinth", 0.7, 0.9, (x, -1.2, 0.9), dark, segments=10))
		parts.append(cylinder("PlinthTop", 0.78, 0.1, (x, -1.2, 1.4), gold_mat, segments=10))
	parts.append(box("Lantern", (0.4, 0.4, 0.55), (0, -3.6, 5.4), material("StallLamp", (1, 0.72, 0.28), emission=1.8)))
	parts.append(box("Sign", (9, 0.25, 1.8), (0, 0.2, 7.6), material("StallSign", (0.1, 0.06, 0.03), roughness=0.45)))
	parts.append(box("SignFrame", (9.7, 0.14, 2.4), (0, 0.35, 7.6), gold_mat))
	return parts


def build_trainer_stall():
	wood_mat = material("TrainerWood", WOOD, roughness=0.55)
	blue_mat = material("TrainerBlue", BLUE, roughness=0.55)
	gold_mat = material("TrainerGold", GOLD, metallic=0.7, roughness=0.3)
	metal_mat = material("Weight", METAL, metallic=0.9, roughness=0.25)
	parts = []
	parts.append(box("Floor", (12, 9, 0.3), (0, 0, 0.15), material("TrainerFloor", WOOD_DARK, roughness=0.55)))
	parts.append(box("Counter", (7, 1.4, 0.8), (0, 2.8, 0.8), wood_mat, bevel=0.02))
	parts.append(box("CounterCloth", (7.2, 1.55, 0.06), (0, 2.8, 1.22), blue_mat))
	parts.append(box("Awning", (12, 7.5, 0.16), (0, -0.2, 5.6), blue_mat))
	parts.append(box("AwningTrim", (12.4, 7.8, 0.08), (0, -0.2, 5.75), gold_mat))
	for x in (-5.6, 5.6):
		parts.append(cylinder("Post", 0.16, 5.4, (x, -3.4, 2.8), wood_mat, segments=8))
	parts.append(cylinder("Bar", 0.08, 2.4, (-3.2, -0.4, 1.5), metal_mat, rotation=ry(90), segments=10))
	parts.append(cylinder("PlateL", 0.45, 0.18, (-4.3, -0.4, 1.5), metal_mat, rotation=ry(90), segments=16))
	parts.append(cylinder("PlateR", 0.45, 0.18, (-2.1, -0.4, 1.5), metal_mat, rotation=ry(90), segments=16))
	parts.append(sphere("Bell", 0.28, (2.2, 2.7, 1.45), metal_mat, scale=(1, 1, 0.7), segments=12))
	parts.append(box("Sign", (8, 0.2, 1.6), (0, 0, 6.6), material("TrainerSign", (0.08, 0.05, 0.03), roughness=0.45)))
	parts.append(box("SignFrame", (8.6, 0.12, 2.15), (0, 0.15, 6.6), gold_mat))
	return parts


def build_signpost():
	wood_mat = material("SignPostWood", WOOD_DARK, roughness=0.5)
	board = material("SignBoardDark", (0.1, 0.06, 0.03), roughness=0.45)
	gold_mat = material("SignFrameGold", GOLD, metallic=0.75, roughness=0.28)
	parts = []
	for x in (-3.4, 3.4):
		parts.append(cylinder("Post", 0.16, 5.2, (x, 0, 2.6), wood_mat, segments=8))
		parts.append(box("Cap", (0.45, 0.45, 0.18), (x, 0, 5.3), gold_mat))
	parts.append(box("Board", (7.2, 0.18, 2.6), (0, 0, 4.3), board))
	parts.append(box("Frame", (7.8, 0.1, 3.15), (0, -0.08, 4.3), gold_mat))
	return parts


def build_fishing_sign():
	wood_mat = material("FishPost", WOOD, roughness=0.5)
	gold_mat = material("FishGold", GOLD, metallic=0.7, roughness=0.3)
	board_mat = material("FishBoard", (0.08, 0.28, 0.45), roughness=0.45)
	fish_mat = material("Fish", (0.35, 0.65, 0.8), roughness=0.4)
	parts = []
	parts.append(cylinder("PostL", 0.28, 14, (-6.5, 0, 7), wood_mat, segments=8))
	parts.append(cylinder("PostR", 0.28, 14, (6.5, 0, 7), wood_mat, segments=8))
	parts.append(box("CapL", (0.7, 0.7, 0.3), (-6.5, 0, 14.2), gold_mat))
	parts.append(box("CapR", (0.7, 0.7, 0.3), (6.5, 0, 14.2), gold_mat))
	parts.append(box("Beam", (14.5, 0.5, 0.6), (0, 0, 13.6), material("Beam", WOOD_DARK, roughness=0.5)))
	parts.append(box("Board", (11, 0.25, 4.2), (0, 0, 10.2), board_mat))
	parts.append(box("Frame", (11.8, 0.12, 4.9), (0, -0.12, 10.2), gold_mat))
	parts.append(sphere("FishBody", 0.7, (0, -0.2, 8.4), fish_mat, scale=(1.8, 0.35, 0.7), segments=12))
	parts.append(cone("FishTail", 0.35, 0.7, (1.5, -0.2, 8.4), fish_mat, rotation=ry(90), segments=4))
	return parts


def build_arena():
	stone_mat = material("ArenaStone", (0.7, 0.66, 0.6), roughness=0.7)
	stone_dark = material("ArenaStoneDark", (0.45, 0.42, 0.38), roughness=0.75)
	sand_mat = material("ArenaSand", SAND, roughness=0.9)
	red_mat = material("BannerRed", RED, roughness=0.6)
	blue_mat = material("BannerBlue", BLUE, roughness=0.55)
	gold_mat = material("ArenaGold", GOLD, metallic=0.7, roughness=0.3)
	wood_mat = material("TorchWood", WOOD_DARK, roughness=0.5)
	flame = material("Flame", (1.0, 0.45, 0.1), roughness=0.4, emission=3.0)
	parts = []
	radius = 30.0
	parts.append(cylinder("Sand", radius * 0.92, 0.4, (0, 0, 0.2), sand_mat, segments=48))
	parts.append(cylinder("InnerRing", 8.0, 0.15, (0, 0, 0.45), material("Emblem", (0.55, 0.12, 0.12), roughness=0.5), segments=32))
	parts.append(cylinder("Inlay", 3.0, 0.1, (0, 0, 0.55), gold_mat, segments=24))
	segments = 20
	for i in range(segments):
		angle = i / segments * math.pi * 2
		x = math.cos(angle) * radius
		y = math.sin(angle) * radius
		rot = rz(math.degrees(angle) + 90)
		arched = i % 2 == 0
		height = 8.0 if arched else 16.0
		z = height / 2
		mat = stone_dark if arched else stone_mat
		parts.append(box("Wall", (6.4, 2.2, height), (x, y, z), mat, rotation=rot))
		if arched:
			parts.append(box("Arch", (6.4, 2.4, 2.0), (x, y, 9.2), stone_mat, rotation=rot))
		parts.append(box("Cornice", (6.8, 3.0, 0.8), (x, y, 16.4), stone_dark, rotation=rot))
	for i in range(8):
		angle = i / 8 * math.pi * 2
		x = math.cos(angle) * (radius - 3.5)
		y = math.sin(angle) * (radius - 3.5)
		parts.append(cylinder("TorchPost", 0.2, 6.0, (x, y, 3.0), wood_mat, segments=8))
		parts.append(sphere("Flame", 0.35, (x, y, 6.3), flame, segments=8))
	for i in range(4):
		angle = i / 4 * math.pi * 2 + math.pi / 4
		x = math.cos(angle) * (radius - 1.2)
		y = math.sin(angle) * (radius - 1.2)
		rot = rz(math.degrees(angle) + 90)
		cloth = red_mat if i % 2 == 0 else blue_mat
		parts.append(box("Banner", (2.6, 0.12, 4.5), (x, y, 12.0), cloth, rotation=rot))
		parts.append(box("BannerTrim", (2.7, 0.14, 0.2), (x, y, 9.7), gold_mat, rotation=rot))
	return parts


def build_player_plot():
	stone_mat = material("PlotStone", (0.48, 0.45, 0.4), roughness=0.75)
	grass_mat = material("PlotGrass", GRASS, roughness=0.85)
	wood_mat = material("PlotWood", WOOD, roughness=0.55)
	plank_mat = material("PlotPlank", PLANK, roughness=0.55)
	gold_mat = material("PlotGold", GOLD, metallic=0.7, roughness=0.3)
	marble_mat = material("Pedestal", MARBLE, roughness=0.35)
	sign_mat = material("PlotSign", (0.12, 0.07, 0.04), roughness=0.45)
	size = 52.0
	half = size / 2
	parts = []
	parts.append(box("Foundation", (size + 6, size + 6, 1.2), (0, 0, 0.6), material("Foundation", STONE_DARK, roughness=0.8)))
	parts.append(box("Curb", (size + 3, size + 3, 0.35), (0, 0, 1.15), stone_mat))
	parts.append(box("Lawn", (size, size, 0.4), (0, 0, 1.25), grass_mat))
	deck_y = 8.0
	deck_depth = size * 0.5
	deck_z = -size * 0.18
	parts.append(box("Deck", (size - 2, deck_depth, 0.6), (0, deck_z, deck_y), plank_mat))
	parts.append(box("DeckTrim", (size - 1, deck_depth + 0.6, 0.2), (0, deck_z, deck_y - 0.4), wood_mat))
	for sx in (-1, 1):
		for sz in (-1, 1):
			px = sx * (half - 0.7)
			pz = sz * (half - 0.7)
			parts.append(cylinder("Post", 0.4, deck_y + 1.5, (px, pz, (deck_y + 1.5) / 2), wood_mat, segments=8))
			parts.append(box("PostCap", (1.1, 1.1, 0.28), (px, pz, deck_y + 1.7), gold_mat))
	parts.append(box("RailFront", (size - 4, 0.25, 0.9), (0, deck_z - deck_depth / 2, deck_y + 0.9), wood_mat))
	parts.append(box("RailBack", (size - 4, 0.25, 0.9), (0, deck_z + deck_depth / 2, deck_y + 0.9), wood_mat))
	stair_x = half - 4
	for step in range(8):
		z = deck_z + deck_depth / 2 + 1.2 + step * 2.2
		parts.append(box("Step", (5.5, 2.0, 0.45), (stair_x, z, 0.9 + step * 0.95), plank_mat))
	parts.append(box("OwnerSign", (9, 0.25, 2.4), (0, deck_z - deck_depth / 2 - 0.4, deck_y + 3.2), sign_mat))
	parts.append(box("OwnerFrame", (9.8, 0.12, 3.1), (0, deck_z - deck_depth / 2 - 0.55, deck_y + 3.2), gold_mat))
	for slot in range(10):
		col = slot % 5
		row = slot // 5
		px = -16 + col * 8
		pz = deck_z - 4 + row * 7
		parts.append(cylinder("Plinth", 1.15, 0.55, (px, pz, deck_y + 0.6), stone_mat, segments=12))
		parts.append(cylinder("Pedestal", 0.85, 0.35, (px, pz, deck_y + 1.0), marble_mat, segments=16))
		parts.append(cylinder("Ring", 0.95, 0.06, (px, pz, deck_y + 1.2), gold_mat, segments=16))
	return parts


BUILDERS = {
	"Skateboard": build_skateboard,
	"MagicCarpet": build_magic_carpet,
	"MiniPlane": build_plane,
	"Sword": build_sword,
	"Mace": build_mace,
	"Axe": build_axe,
	"FishingDock": build_fishing_dock,
	"GoldMine": build_gold_mine,
	"VendorStall": build_vendor_stall,
	"TrainerStall": build_trainer_stall,
	"SignPost": build_signpost,
	"FishingSign": build_fishing_sign,
	"Arena": build_arena,
	"PlayerPlot": build_player_plot,
}


def requested_names() -> list[str]:
	if "--" not in sys.argv:
		return list(BUILDERS)
	extra = sys.argv[sys.argv.index("--") + 1 :]
	if "--only" not in extra:
		return list(BUILDERS)
	raw = extra[extra.index("--only") + 1]
	wanted = [piece.strip() for piece in raw.split(",") if piece.strip()]
	missing = [name for name in wanted if name not in BUILDERS]
	if missing:
		known = ", ".join(BUILDERS)
		raise SystemExit(f"Unknown prop(s): {', '.join(missing)}. Choose from: {known}")
	return wanted


def main():
	names = requested_names()
	for name in names:
		reset_scene()
		objects = BUILDERS[name]()
		ground_and_export(name, objects)
	print(f"[make_props] finished {len(names)} props in {OUT_DIR}")


if __name__ == "__main__":
	main()
