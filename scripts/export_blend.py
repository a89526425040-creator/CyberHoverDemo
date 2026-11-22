import bpy, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BLEND = os.path.join(ROOT, "assets", "source", "cdp-test-7.blend")
TEXTURES = os.path.join(ROOT, "assets", "textures")
OUTPUT = os.path.join(ROOT, "assets", "hovercar.glb")

if not os.path.isfile(BLEND):
    raise RuntimeError("Missing assets/source/cdp-test-7.blend")
bpy.ops.wm.open_mainfile(filepath=BLEND)

# Relink supplied textures and remove only image datablocks whose
# source files are absent. The GLB exporter embeds the remaining images.
missing = set()
for image in list(bpy.data.images):
    if image.source != "FILE":
        continue
    original_name = os.path.basename(bpy.path.abspath(image.filepath))
    candidate = os.path.join(TEXTURES, original_name)
    if os.path.isfile(candidate):
        image.filepath = candidate
        image.reload()
    else:
        missing.add(original_name)
        for material in bpy.data.materials:
            if not material.use_nodes or not material.node_tree:
                continue
            for node in material.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image == image:
                    node.image = None
        bpy.data.images.remove(image, do_unlink=True)

# Do not call pack_all(): Blender attempts to pack every datablock, including
# missing optional baked maps. glTF embeds the valid external texture files.
bpy.ops.export_scene.gltf(
    filepath=OUTPUT,
    export_format="GLB",
    export_apply=True,
    export_image_format="AUTO",
)
if not os.path.isfile(OUTPUT) or os.path.getsize(OUTPUT) < 1024:
    raise RuntimeError("GLB export did not produce a valid model file")
print("Exported model:", OUTPUT, "size:", os.path.getsize(OUTPUT))
if missing:
    print("Unavailable optional baked maps:", ", ".join(sorted(missing)))
