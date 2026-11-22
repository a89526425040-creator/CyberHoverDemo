import bpy, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BLEND = os.path.join(ROOT, "assets", "source", "cdp-test-7.blend")
TEXTURES = os.path.join(ROOT, "assets", "textures")
OUTPUT = os.path.join(ROOT, "assets", "hovercar.glb")

if not os.path.isfile(BLEND):
    raise RuntimeError("Missing assets/source/cdp-test-7.blend")
bpy.ops.wm.open_mainfile(filepath=BLEND)

# Relink every supplied texture by filename. The source blend also refers
# to four baked maps that are not included in the uploaded archive.
missing = set()
for image in bpy.data.images:
    if image.source != "FILE":
        continue
    original_name = os.path.basename(bpy.path.abspath(image.filepath))
    candidate = os.path.join(TEXTURES, original_name)
    if os.path.isfile(candidate):
        image.filepath = candidate
        image.reload()
    else:
        missing.add(original_name)

# Disconnect only image nodes whose source files are genuinely absent.
for material in bpy.data.materials:
    if not material.use_nodes or not material.node_tree:
        continue
    for node in material.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image:
            path = bpy.path.abspath(node.image.filepath)
            if node.image.source == "FILE" and not os.path.isfile(path):
                node.image = None

# Pack the available textures into the exported GLB.
bpy.ops.file.pack_all()
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
