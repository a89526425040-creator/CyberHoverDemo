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
images = {}
for folder, _, files in os.walk(ASSETS):
    for filename in files:
        if filename.lower().endswith((".png", ".jpg", ".jpeg", ".tga", ".tif", ".tiff", ".webp")):
            images[filename.lower()] = os.path.join(folder, filename)

def load_map(filename, non_color=False):
    path = images.get(filename.lower())
    if not path:
        missing.append(filename)
        return None
    image = bpy.data.images.load(path, check_existing=True)
    if non_color:
        image.colorspace_settings.name = "Non-Color"
    relinked.append(filename)
    return image

def image_node(tree, filename, non_color=False):
    image = load_map(filename, non_color)
    if image is None:
        return None
    node = tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    node.label = filename
    return node

def ensure_principled(material):
    material.use_nodes = True
    tree = material.node_tree
    tree.nodes.clear()
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    output.location = (520, 0)
    shader = tree.nodes.new("ShaderNodeBsdfPrincipled")
    shader.location = (240, 0)
    tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    shader.inputs["Base Color"].default_value = material.diffuse_color
    shader.inputs["Metallic"].default_value = 0.0
    shader.inputs["Roughness"].default_value = 0.48
    return tree, shader

for material in bpy.data.materials:
    old_color = material.diffuse_color[:]
    tree, shader = ensure_principled(material)
    name = material.name.lower()
    if name == "cdp_body":
        # The source package has no body albedo image; retain its authored base
        # color and restore the supplied normal, glossiness and AO maps.
        normal = image_node(tree, "cdp_body_normal.png", True)
        if normal:
            normal.location = (-620, -180)
            normal_map = tree.nodes.new("ShaderNodeNormalMap")
            normal_map.location = (-360, -180)
            tree.links.new(normal.outputs["Color"], normal_map.inputs["Color"])
            tree.links.new(normal_map.outputs["Normal"], shader.inputs["Normal"])
        gloss = image_node(tree, "cdp_body_Glossiness.png", True)
        if gloss:
            gloss.location = (-620, 160)
            invert = tree.nodes.new("ShaderNodeInvert")
            invert.location = (-360, 160)
            tree.links.new(gloss.outputs["Color"], invert.inputs["Color"])
            tree.links.new(invert.outputs["Color"], shader.inputs["Roughness"])
        ao = image_node(tree, "cdp_body_Mixed_AO.png", True)
        if ao:
            ao.location = (-620, 420)
    elif name == "cdp_metal":
        diffuse = image_node(tree, "cdp_metal_Diffuse.png")
        if diffuse:
            diffuse.location = (-420, 80)
            tree.links.new(diffuse.outputs["Color"], shader.inputs["Base Color"])
        gloss = image_node(tree, "cdp_metal_Glossiness.png", True)
        if gloss:
            gloss.location = (-420, -160)
            invert = tree.nodes.new("ShaderNodeInvert")
            invert.location = (-180, -160)
            tree.links.new(gloss.outputs["Color"], invert.inputs["Color"])
            tree.links.new(invert.outputs["Color"], shader.inputs["Roughness"])
        shader.inputs["Metallic"].default_value = 0.8
    elif name == "cdp_plastic":
        diffuse = image_node(tree, "cdp_plastic_Diffuse.png")
        if diffuse:
            diffuse.location = (-420, 80)
            tree.links.new(diffuse.outputs["Color"], shader.inputs["Base Color"])
        shader.inputs["Metallic"].default_value = 0.12
        shader.inputs["Roughness"].default_value = 0.42
    elif name == "white light":
        emissive = image_node(tree, "white_light_Emissive.png")
        if emissive:
            emissive.location = (-420, 80)
            emission_input = shader.inputs.get("Emission") or shader.inputs.get("Emission Color")
            if emission_input:
                tree.links.new(emissive.outputs["Color"], emission_input)
            strength = shader.inputs.get("Emission Strength")
            if strength:
                strength.default_value = 2.0
    elif name == "paint":
        shader.inputs["Metallic"].default_value = 0.72
        shader.inputs["Roughness"].default_value = 0.28
    elif name == "thruster":
        shader.inputs["Metallic"].default_value = 0.45
        shader.inputs["Emission"].default_value = old_color
        if shader.inputs.get("Emission Strength"):
            shader.inputs["Emission Strength"].default_value = 1.6

# Fail the export if the source maps that actually exist in the package were
# not attached to the corresponding materials.
required_maps = ["cdp_body_normal.png", "cdp_body_Glossiness.png",
                 "cdp_metal_Diffuse.png", "cdp_metal_Glossiness.png",
                 "cdp_plastic_Diffuse.png", "white_light_Emissive.png"]
not_linked = [name for name in required_maps if name not in relinked]
if not_linked:
    raise RuntimeError("Required vehicle texture maps were not loaded: " + repr(not_linked))
print("=== RESTORED MATERIALS ===")
for material in bpy.data.materials:
    if material.use_nodes and material.node_tree:
        for node in material.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image:
                print("MATERIAL MAP:", material.name, node.image.name)
print("=== END RESTORED MATERIALS ===")

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
