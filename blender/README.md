# Brainrot Arena — Blender props

Procedural world props for Roblox Studio. **1 Blender unit = 1 stud.** Each export is grounded and centered at the origin.

## Props

| Prop | Use |
|------|-----|
| `Arena` | Colosseum / battle ring |
| `PlayerPlot` | Player homestead + pedestals |
| `GoldMine` | Plot mine upgrade |
| `FishingDock` | Lakeside fishing |
| `VendorStall` / `TrainerStall` | Plaza shops |
| `SignPost` / `FishingSign` | Wayfinding |
| `Sword` / `Mace` / `Axe` | Weapon display |
| `Skateboard` / `MagicCarpet` / `MiniPlane` | Mount / travel cosmetics |

## Rebuild exports

Requires Blender 4.x on `PATH`.

```bash
# everything → blender/exports/*.fbx + *.glb
blender --background --python blender/make_props.py

# subset
blender --background --python blender/make_props.py -- --only Sword,Mace,Axe
```

## Import into Roblox Studio

1. Open the Brainrot Arena place.
2. **File → Import 3D** and pick the `.fbx` from `blender/exports/`.
3. Enable **Upload to Roblox** so MeshParts get asset IDs.
4. Parent under the matching world folder (Arena, Plots, Plaza, etc.).
5. Save the place. Commit any Lua wiring that references the new instances.

Prefer **FBX** for Studio. GLB is kept for previews and non-Studio tooling.

## Notes

- Materials are simple Principled colors (no UVs required).
- Re-run the script after editing a `build_*` function in `make_props.py`.
- Do not hand-edit files under `exports/` — regenerate them.
