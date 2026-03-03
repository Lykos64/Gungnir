package gungnir

import "core:fmt"
import gl "vendor:OpenGL"
import "core:os"
import "base:runtime"
import cgltf "vendor:cgltf"
import "core:strings"




// Check for OpenGL errors and print them
gn_Utils_Check_gl_Error :: proc(error_context: string) {
    err := gl.GetError()
    for err != gl.NO_ERROR {
        fmt.eprintf("GL Error in %s: 0x%x\n", error_context, err)
        err = gl.GetError() // Drain all errors
    }
}

// Copy a file from source to destination
gn_Utils_Copy_File :: proc(src, dst: string) -> (ok: bool) {
    data, err := os.read_entire_file(src, context.allocator)   // ← new signature + allocator
    if err != nil {
        fmt.eprintf("Failed to read file %q: %v\n", src, err)
        return false
    }
    defer delete(data, context.allocator)   // ← now needs explicit allocator

    err = os.write_entire_file(dst, data)   // ← returns os.Error now
    if err != nil {
        fmt.eprintf("Failed to write file %q: %v\n", dst, err)
        return false
    }

    return true
}

// Loads the FIRST mesh / FIRST primitive from a .glb or .gltf file
// Returns ready-to-draw VAO/VBO/EBO + counts. Only POSITION attribute is uploaded (matches your current shader).
gn_Load_GLTF_Mesh :: proc(filename: string) -> (vao, vbo, ebo: u32, vertex_count, index_count: i32, index_type: u32, success: bool) {
    opts := cgltf.options{}  // auto-detects .gltf vs .glb

    cfilename := strings.clone_to_cstring(filename, context.temp_allocator)

    gltf_data, parse_res := cgltf.parse_file(opts, cfilename)
    if parse_res != .success {
        fmt.eprintf("cgltf.parse_file failed (%v): %s\n", parse_res, filename)
        return
    }
    defer cgltf.free(gltf_data)

    load_res := cgltf.load_buffers(opts, gltf_data, cfilename)
    if load_res != .success {
        fmt.eprintf("cgltf.load_buffers failed (%v)\n", load_res)
        return
    }

    if len(gltf_data.meshes) == 0 || len(gltf_data.meshes[0].primitives) == 0 {
        fmt.eprintf("No mesh or primitive found in %s\n", filename)
        return
    }

    prim := &gltf_data.meshes[0].primitives[0]

    // Locate POSITION attribute
    pos_acc: ^cgltf.accessor = nil
    for &attr in prim.attributes {
        if attr.type == .position {
            pos_acc = attr.data
            break
        }
    }
    if pos_acc == nil || pos_acc.component_type != .r_32f || pos_acc.type != .vec3 {
        fmt.eprintf("No valid POSITION (vec3 float) attribute in %s\n", filename)
        return
    }

    vertex_count = i32(pos_acc.count)

    gl.GenVertexArrays(1, &vao)
    gl.GenBuffers(1, &vbo)
    gl.BindVertexArray(vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)

    if bv := pos_acc.buffer_view; bv != nil {
        offset := uintptr(pos_acc.offset + bv.offset)
        data_ptr := rawptr(uintptr(bv.buffer.data) + offset)

        gl.BufferData(gl.ARRAY_BUFFER, int(vertex_count * 3 * size_of(f32)), data_ptr, gl.STATIC_DRAW)
    }

    gl.VertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0)
    gl.EnableVertexAttribArray(0)

    // Indices (most real glTF models use them)
    index_count = 0
    index_type  = gl.UNSIGNED_INT
    ebo         = 0

    if idx_acc := prim.indices; idx_acc != nil {
        index_count = i32(idx_acc.count)

        switch idx_acc.component_type {
        case .r_8u:
            index_type = gl.UNSIGNED_BYTE
        case .r_16u:
            index_type = gl.UNSIGNED_SHORT
        case .r_32u:
            index_type = gl.UNSIGNED_INT
        case .invalid, .r_8, .r_16, .r_32f:
            fmt.eprintf("Unsupported index type %v in %s → using UNSIGNED_INT fallback\n", idx_acc.component_type, filename)
            index_type = gl.UNSIGNED_INT
        }

        if ibv := idx_acc.buffer_view; ibv != nil {
            ioffset := uintptr(idx_acc.offset + ibv.offset)
            iptr := rawptr(uintptr(ibv.buffer.data) + ioffset)

            gl.GenBuffers(1, &ebo)
            gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo)

            elem_size := index_type == gl.UNSIGNED_BYTE  ? 1 :
                         index_type == gl.UNSIGNED_SHORT ? 2 : 4

            gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, int(index_count) * elem_size, iptr, gl.STATIC_DRAW)
        }
    }

    gl.BindVertexArray(0)
    success = true
    return
}