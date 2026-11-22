import bpy, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ASSETS = os.path.join(ROOT, "assets")
BLEND = os.path.join(ASSETS, "source", "cdp-test-7.blend")
OUTPUT = os.path.join(ASSETS, "hovercar.glb")

if not os.path.isfile(BLEND):
    raise RuntimeError("Missing assets/source/cdp-test-7.blend")
bpy.ops.wm.open_mainfile(filepath=BLEND)

# Build a recursive texture index. The archive may place textures in nested
# folders, so do not assume a single fixed "assets/textures" directory.
texture_index = {}
for folder, _, files in os.walk(ASSETS):
    for filename in files:
        if filename.lower().endswith((".png", ".jpg", ".jpeg", ".tga", ".tif", ".tiff", ".webp")):
            texture_index.setdefault(filename.lower(), os.path.join(folder, filename))

missing = []
relinked = []
for image in list(bpy.data.images):
    if image.source != "FILE" or image.packed_file:
        continue
    original_name = os.path.basename(bpy.path.abspath(image.filepath)).lower()
    candidate = texture_index.get(original_name)
    if candidate and os.path.isfile(candidate):
        image.filepath = candidate
        image.reload()
        if image.size[0] > 0 and image.size[1] > 0:
            relinked.append(original_name)
        else:
            missing.append(original_name)
    else:
        missing.append(original_name)
        for material in bpy.data.materials:
            if not material.use_nodes or not material.node_tree:
                continue
            for node in material.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image == image:
                    node.image = None
        bpy.data.images.remove(image, do_unlink=True)

# Remove an accidental ground/backdrop plane from the source scene. Keep all
# vehicle parts; only discard clearly oversized, flat meshes or named ground.
removed_planes = []
for obj in list(bpy.context.scene.objects):
    if obj.type != "MESH":
        continue
    name = obj.name.lower()
    dims = obj.dimensions
    horizontal_span = max(dims.x, dims.y)
    flatness = min(dims.x, dims.y, dims.z)
    named_ground = name in ("plane", "ground", "floor", "ground_plane", "floor_plane")
    oversized_flat = horizontal_span > 12.0 and flatness < 0.2
    enormous = max(dims.x, dims.y, dims.z) > 25.0
    if named_ground or oversized_flat or enormous:
        removed_planes.append(obj.name)
        bpy.data.objects.remove(obj, do_unlink=True)

# Export all remaining vehicle meshes and embed every successfully linked map.
bpy.ops.export_scene.gltf(
    filepath=OUTPUT,
    export_format="GLB",
    export_apply=True,
    export_image_format="AUTO",
)
if not os.path.isfile(OUTPUT) or os.path.getsize(OUTPUT) < 1024:
    raise RuntimeError("GLB export did not produce a valid model file")
print("Exported model:", OUTPUT, "size:", os.path.getsize(OUTPUT))
print("Textures relinked:", len(relinked), sorted(relinked))
print("Missing image files:", len(missing), sorted(missing))
print("Removed ground/backdrop meshes:", removed_planes)
