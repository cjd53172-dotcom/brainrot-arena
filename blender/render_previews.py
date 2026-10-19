"""Render orthographic preview PNGs for a few props (walkthrough / README).

    blender --background --python render_previews.py
"""

from __future__ import annotations

import math
import os
import sys

import bpy
from mathutils import Vector

# Allow importing builders from make_props.py in the same folder.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
	sys.path.insert(0, SCRIPT_DIR)

import make_props as props  # noqa: E402

PREVIEW_DIR = os.path.join(SCRIPT_DIR, "previews")
PREVIEW_PROPS = ["Sword", "Arena", "PlayerPlot", "GoldMine", "VendorStall", "Skateboard"]


def frame_camera(cam: bpy.types.Object, objects: list) -> None:
	xs, ys, zs = [], [], []
	for obj in objects:
		for corner in obj.bound_box:
			world = obj.matrix_world @ Vector(corner)
			xs.append(world.x)
			ys.append(world.y)
			zs.append(world.z)
	cx = (min(xs) + max(xs)) / 2
	cy = (min(ys) + max(ys)) / 2
	cz = (min(zs) + max(zs)) / 2
	span = max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs), 1.0)
	dist = span * 1.55
	cam.location = (cx + dist * 0.85, cy - dist * 0.95, cz + dist * 0.7)
	direction = Vector((cx, cy, cz)) - cam.location
	cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
	cam.data.type = "ORTHO"
	cam.data.ortho_scale = span * 1.35


def render_one(name: str) -> str:
	props.reset_scene()
	objects = props.BUILDERS[name]()
	# Ground/center like export, but keep objects unparented for bounds.
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

	# Soft studio lighting
	light_data = bpy.data.lights.new(name="Key", type="AREA")
	light_data.energy = 1200
	light_data.size = 20
	key = bpy.data.objects.new("Key", light_data)
	bpy.context.scene.collection.objects.link(key)
	key.location = (12, -14, 18)

	fill_data = bpy.data.lights.new(name="Fill", type="AREA")
	fill_data.energy = 400
	fill_data.size = 25
	fill = bpy.data.objects.new("Fill", fill_data)
	bpy.context.scene.collection.objects.link(fill)
	fill.location = (-10, -8, 10)

	cam_data = bpy.data.cameras.new("PreviewCam")
	cam = bpy.data.objects.new("PreviewCam", cam_data)
	bpy.context.scene.collection.objects.link(cam)
	bpy.context.scene.camera = cam
	frame_camera(cam, objects)

	scene = bpy.context.scene
	scene.render.engine = "BLENDER_EEVEE"
	scene.render.resolution_x = 1024
	scene.render.resolution_y = 768
	scene.render.image_settings.file_format = "PNG"
	scene.render.film_transparent = True
	world = bpy.data.worlds.new("PreviewWorld")
	scene.world = world
	world.use_nodes = True
	bg = world.node_tree.nodes["Background"]
	bg.inputs[0].default_value = (0.12, 0.13, 0.16, 1.0)
	bg.inputs[1].default_value = 1.0

	os.makedirs(PREVIEW_DIR, exist_ok=True)
	out = os.path.join(PREVIEW_DIR, f"{name}.png")
	scene.render.filepath = out
	bpy.ops.render.render(write_still=True)
	print(f"[previews] {name} -> {out}")
	return out


def main() -> None:
	for name in PREVIEW_PROPS:
		render_one(name)
	print(f"[previews] done → {PREVIEW_DIR}")


if __name__ == "__main__":
	main()
