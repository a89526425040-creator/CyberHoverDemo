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
print("=== MATERIAL DIAGNOSTICS ===")
for material in bpy.data.materials:
    print("MATERIAL:", material.name, "diffuse_color:", tuple(round(float(v), 4) for v in material.diffuse_color))
    if material.use_nodes and material.node_tree:
        for node in material.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                base = node.inputs.get("Base Color")
                emission = node.inputs.get("Emission Color") or node.inputs.get("Emission")
                print("  PRINCIPLED:", node.name,
                      "base_color:", tuple(round(float(v), 4) for v in base.default_value) if base else None,
                      "emission:", tuple(round(float(v), 4) for v in emission.default_value) if emission else None)
            elif node.type == "TEX_IMAGE":
                links = []
                for link in material.node_tree.links:
                    if link.from_node == node:
                        links.append(link.to_node.name + "." + link.to_socket.name)
                print("  IMAGE:", node.name,
                      "file:", bpy.path.basename(node.image.filepath) if node.image else None,
                      "targets:", links)
print("=== END MATERIAL DIAGNOSTICS ===")
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

# Never delete source meshes automatically: large vehicle hulls can exceed
# arbitrary dimension thresholds and must remain part of the exported model.
mesh_inventory = []
for obj in bpy.context.scene.objects:
    if obj.type == "MESH":
        mesh_inventory.append((obj.name, tuple(round(float(v), 3) for v in obj.dimensions)))
print("Preserved source mesh count:", len(mesh_inventory))
print("Source mesh inventory:", mesh_inventory)

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
print("Removed ground/backdrop meshes: [] (no automatic mesh deletion)")
