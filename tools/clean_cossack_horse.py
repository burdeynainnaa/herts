import collections
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import struct


MODEL = Path("assets/models/cossack_horse_linked/3d_bc3a2645651a410faf385800_1795863139610.glb")
SOURCE_HASH = "2f822a67cdbf1d49698f19a5e107a0238a2bd7b4e717579b648e395891725e39"
HOOF_CENTERS = ((-0.11, -0.298), (0.086, -0.29), (-0.128, 0.752), (0.121, 0.618))
GROUND_Y = -0.8 / 2.1


def world_point(position):
    return (-2.1 * position[0], 0.8 + 2.1 * position[1], -2.1 * position[2])


def read_accessor(document, binary, index, count_format):
    accessor = document["accessors"][index]
    view = document["bufferViews"][accessor["bufferView"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    size = struct.calcsize(count_format) * accessor["count"]
    return list(struct.iter_unpack(count_format, binary[start:start + size]))


def normalize(vector):
    length = math.sqrt(sum(value * value for value in vector))
    return tuple(value / length for value in vector) if length else (0.0, 1.0, 0.0)


def interpolate(first, second):
    amount = (GROUND_Y - first[0][1]) / (second[0][1] - first[0][1])
    position = tuple(first[0][axis] + amount * (second[0][axis] - first[0][axis]) for axis in range(3))
    normal = normalize(tuple(first[1][axis] + amount * (second[1][axis] - first[1][axis]) for axis in range(3)))
    uv = tuple(first[2][axis] + amount * (second[2][axis] - first[2][axis]) for axis in range(2))
    return position, normal, uv


class MeshBuilder:
    def __init__(self):
        self.vertices = []
        self.indices = []
        self.lookup = {}

    def vertex(self, key, value):
        if key not in self.lookup:
            self.lookup[key] = len(self.vertices)
            self.vertices.append(value)
        return self.lookup[key]

    def triangle(self, polygon):
        for first, second, third in ((polygon[0], polygon[index], polygon[index + 1]) for index in range(1, len(polygon) - 1)):
            self.indices.extend(self.vertex(key, value) for key, value in (first, second, third))


def tail_components(vertices, indices):
    parent = list(range(len(vertices)))

    def root(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    def union(first, second):
        parent[root(second)] = root(first)

    for index in range(0, len(indices), 3):
        union(indices[index], indices[index + 1])
        union(indices[index], indices[index + 2])

    positions = {}
    for index, vertex in enumerate(vertices):
        key = tuple(round(value, 5) for value in world_point(vertex[0]))
        if key in positions:
            union(index, positions[key])
        else:
            positions[key] = index

    components = collections.defaultdict(list)
    for index, vertex in enumerate(vertices):
        components[root(index)].append(world_point(vertex[0]))
    tail_roots = set()
    for component, points in components.items():
        minimum = tuple(min(point[axis] for point in points) for axis in range(3))
        maximum = tuple(max(point[axis] for point in points) for axis in range(3))
        if (len(points) >= 30 and minimum[2] > 0.57 and minimum[1] > 0.2
                and maximum[1] > 0.9 and maximum[1] - minimum[1] > 0.5
                and minimum[0] > -0.11 and maximum[0] < 0.11):
            tail_roots.add(component)
    if len(tail_roots) != 14:
        raise ValueError(f"Expected 14 tail strands, found {len(tail_roots)}")
    return {index for index in range(len(vertices)) if root(index) in tail_roots}


def cleanup(vertices, indices, tail_indices):
    body = MeshBuilder()
    tail = MeshBuilder()
    boundary = collections.defaultdict(set)
    boundary_vertices = {}

    for offset in range(0, len(indices), 3):
        triangle = indices[offset:offset + 3]
        if all(index in tail_indices for index in triangle):
            tail.triangle([(("source", index), vertices[index]) for index in triangle])
            continue
        if any(index in tail_indices for index in triangle):
            raise ValueError("A triangle connects the tail to the body")

        points = [world_point(vertices[index][0]) for index in triangle]
        center = tuple(sum(point[axis] for point in points) / 3.0 for axis in range(3))
        near_hoof = any(abs(center[0] - x) < 0.16 and abs(center[2] - z) < 0.19 for x, z in HOOF_CENTERS)
        if center[1] < 0.22 and not near_hoof:
            continue

        clipped = []
        intersections = []
        for edge in range(3):
            first = triangle[edge]
            second = triangle[(edge + 1) % 3]
            first_vertex = vertices[first]
            second_vertex = vertices[second]
            first_inside = first_vertex[0][1] >= GROUND_Y
            second_inside = second_vertex[0][1] >= GROUND_Y
            if first_inside:
                clipped.append((("source", first), first_vertex))
            if first_inside != second_inside:
                value = interpolate(first_vertex, second_vertex)
                key = ("edge", min(first, second), max(first, second))
                clipped.append((key, value))
                point_key = tuple(round(value[0][axis], 5) for axis in (0, 2))
                intersections.append(point_key)
                boundary_vertices[point_key] = value
        if len(clipped) >= 3:
            body.triangle(clipped)
        if len(intersections) == 2 and intersections[0] != intersections[1]:
            boundary[intersections[0]].add(intersections[1])
            boundary[intersections[1]].add(intersections[0])

    if any(len(neighbors) != 2 for neighbors in boundary.values()):
        raise ValueError("Hoof boundaries are not closed")
    visited = set()
    loops = []
    for start in boundary:
        if start in visited:
            continue
        loop = [start]
        previous = None
        current = start
        while True:
            visited.add(current)
            neighbors = boundary[current]
            following = next(neighbor for neighbor in neighbors if neighbor != previous)
            if following == start:
                break
            if following in visited:
                raise ValueError("Unexpected hoof boundary")
            loop.append(following)
            previous, current = current, following
        loops.append(loop)
    if len(loops) != 4 or any(len(loop) < 3 for loop in loops):
        raise ValueError(f"Expected four hoof boundaries, found {len(loops)}")

    for loop_index, loop in enumerate(loops):
        area = sum(loop[index][0] * loop[(index + 1) % len(loop)][1] - loop[(index + 1) % len(loop)][0] * loop[index][1] for index in range(len(loop)))
        if area < 0:
            loop.reverse()
        center_position = (sum(point[0] for point in loop) / len(loop), GROUND_Y, sum(point[1] for point in loop) / len(loop))
        center_uv = tuple(sum(boundary_vertices[point][2][axis] for point in loop) / len(loop) for axis in range(2))
        center_vertex = (center_position, (0.0, -1.0, 0.0), center_uv)
        for index, point in enumerate(loop):
            next_point = loop[(index + 1) % len(loop)]
            first = boundary_vertices[point]
            second = boundary_vertices[next_point]
            first_cap = (first[0], (0.0, -1.0, 0.0), first[2])
            second_cap = (second[0], (0.0, -1.0, 0.0), second[2])
            body.triangle([(("cap_center", loop_index), center_vertex),
                           (("cap_edge", loop_index, point), first_cap),
                           (("cap_edge", loop_index, next_point), second_cap)])
    return body, tail


def append_mesh(document, binary, builder, name, material):
    def append_accessor(values, item_format, component_type, accessor_type, target, include_bounds=False):
        while len(binary) % 4:
            binary.append(0)
        start = len(binary)
        for value in values:
            binary.extend(struct.pack(item_format, *value))
        view = len(document["bufferViews"])
        document["bufferViews"].append({"buffer": 0, "byteOffset": start, "byteLength": len(binary) - start, "target": target})
        accessor = {"bufferView": view, "componentType": component_type, "count": len(values), "type": accessor_type}
        if include_bounds:
            accessor["min"] = [min(value[axis] for value in values) for axis in range(3)]
            accessor["max"] = [max(value[axis] for value in values) for axis in range(3)]
        index = len(document["accessors"])
        document["accessors"].append(accessor)
        return index

    positions = append_accessor([vertex[0] for vertex in builder.vertices], "<fff", 5126, "VEC3", 34962, True)
    normals = append_accessor([vertex[1] for vertex in builder.vertices], "<fff", 5126, "VEC3", 34962)
    uvs = append_accessor([vertex[2] for vertex in builder.vertices], "<ff", 5126, "VEC2", 34962)
    indices = append_accessor([(index,) for index in builder.indices], "<I", 5125, "SCALAR", 34963)
    return {"name": name, "primitives": [{"attributes": {"POSITION": positions, "NORMAL": normals, "TEXCOORD_0": uvs}, "indices": indices, "mode": 4, "material": material}]}


def main():
    original = MODEL.read_bytes()
    if hashlib.sha256(original).hexdigest() != SOURCE_HASH:
        raise ValueError("Model does not match the expected original; no changes made")
    magic, version, total_length = struct.unpack_from("<4sII", original, 0)
    json_length, json_type = struct.unpack_from("<I4s", original, 12)
    if magic != b"glTF" or version != 2 or total_length != len(original) or json_type != b"JSON":
        raise ValueError("Invalid GLB")
    document = json.loads(original[20:20 + json_length])
    binary_offset = 20 + json_length
    binary_length, binary_type = struct.unpack_from("<I4s", original, binary_offset)
    if binary_type != b"BIN\0":
        raise ValueError("Missing binary chunk")
    binary = bytearray(original[binary_offset + 8:binary_offset + 8 + binary_length])
    primitive = document["meshes"][0]["primitives"][0]
    attributes = primitive["attributes"]
    positions = read_accessor(document, binary, attributes["POSITION"], "<fff")
    normals = read_accessor(document, binary, attributes["NORMAL"], "<fff")
    uvs = read_accessor(document, binary, attributes["TEXCOORD_0"], "<ff")
    indices = [item[0] for item in read_accessor(document, binary, primitive["indices"], "<I")]
    vertices = list(zip(positions, normals, uvs))
    body, tail = cleanup(vertices, indices, tail_components(vertices, indices))
    document["meshes"] = [append_mesh(document, binary, body, "HorseBody", primitive["material"]),
                           append_mesh(document, binary, tail, "Tail", primitive["material"])]
    document["nodes"] = [{"name": "HorseBody", "mesh": 0}, {"name": "Tail", "mesh": 1}]
    document["scenes"][document.get("scene", 0)]["nodes"] = [0, 1]
    while len(binary) % 4:
        binary.append(0)
    document["buffers"][0]["byteLength"] = len(binary)
    encoded = json.dumps(document, separators=(",", ":")).encode("utf-8")
    encoded += b" " * ((-len(encoded)) % 4)
    result = (struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(encoded) + 8 + len(binary))
              + struct.pack("<I4s", len(encoded), b"JSON") + encoded
              + struct.pack("<I4s", len(binary), b"BIN\0") + binary)
    backup = MODEL.with_suffix(".glb.bak")
    if backup.exists():
        raise ValueError("Backup already exists; no changes made")
    shutil.copyfile(MODEL, backup)
    temporary = MODEL.with_suffix(".glb.tmp")
    temporary.write_bytes(result)
    os.replace(temporary, MODEL)
    print(f"Saved {len(body.indices) // 3} body triangles, {len(tail.indices) // 3} tail triangles and four capped hooves")


if __name__ == "__main__":
    main()
