import bpy, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BLEND = os.path.join(ROOT, "assets", "source", "cdp-test-7.blend")
TEXTURES = os.path.join(ROOT, "assets", "textures")
OUTPUT = os.path.join(ROOT, "assets", "hovercar.glb")

if not os.path.isfile(BLEND):
    raise RuntimeError("Missing assets/source/cdp-test-7.blend")
bpy.ops.wm.open_mainfile(filepath=BLEND)

# Relink external images to the exact texture files supplied with the model.
for image in bpy.data.images:
    if image.source != "FILE":
        continue
    candidate = os.path.join(TEXTURES, os.path.basename(bpy.path.abspath(image.filepath)))
    if os.path.isfile(candidate):
        image.filepath = candidate
        image.reload()

# Pack images so GLB contains its texture data.
bpy.ops.file.pack_all()
bpy.ops.export_scene.gltf(
    filepath=OUTPUT,
    export_format="GLB",
    export_apply=True,
    export_image_format="AUTO",
)
if not os.path.isfile(OUTPUT) or os.path.getsize(OUTPUT) < 1024:
    raise RuntimeError("GLB export did not produce a valid model file")
print("Exported model:", OUTPUT)
