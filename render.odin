package gungnir

import "core:fmt"
import "core:c"
import "shared" 
import "core:math"
import "core:math/linalg"

IS_RENDER_DLL :: #config(IS_RENDER_DLL, false)

when IS_RENDER_DLL {

    // Global state for rendering
    global_shader_program : u32
    global_position_loc   : i32
    global_ecs_api        : shared.ECS_API
    global_gl             : shared.RENDER_GL_API   // ← correct name

    // Set ECS API for DLL use
    @(export)
    gn_Render_Set_API :: proc(api: shared.ECS_API) {
        global_ecs_api = api
    }

    // Set OpenGL API proxy
    @(export)
    gn_Render_Set_GL_API :: proc(api: shared.RENDER_GL_API) {   // name can be anything, we use this one in hotreload.odin
        global_gl = api
    }

    // Render system that draws entities
    @(export)
    gn_Render_ECS_System :: proc(dt: f32) {
        if global_shader_program == 0 { return }

        global_gl.UseProgram(global_shader_program)

        // === Query camera from ECS (works after hot-reload) ===
        cam_entities := global_ecs_api.query(typeid_of(shared.CAMERA_COMPONENT))
        defer delete(cam_entities)
        if len(cam_entities) == 0 { return }

        cam_ptr := cast(^shared.CAMERA_COMPONENT)global_ecs_api.get_component(cam_entities[0], typeid_of(shared.CAMERA_COMPONENT))
        if cam_ptr == nil { return }
        cam := cam_ptr^

        // Build view + projection (all f32 for linalg)
        yaw_rad   := linalg.to_radians(cam.yaw)
        pitch_rad := linalg.to_radians(cam.pitch)

        front := linalg.vector_normalize([3]f32{
            math.cos(yaw_rad) * math.cos(pitch_rad),
            math.sin(pitch_rad),
            math.sin(yaw_rad) * math.cos(pitch_rad),
        })

        view := linalg.matrix4_look_at(
            cam.position,
            cam.position + front,
            [3]f32{0, 1, 0},
        )

        aspect := f32(800) / f32(600)  // your window size from config
        proj := linalg.matrix4_perspective_f32(   // ← explicit f32 version (fixes the error)
            f32(linalg.to_radians(60.0)),
            aspect,
            0.1,
            1000.0,
        )

        // Uniform locations
        model_loc := global_gl.GetUniformLocation(global_shader_program, cstring("u_model"))
        view_loc  := global_gl.GetUniformLocation(global_shader_program, cstring("u_view"))
        proj_loc  := global_gl.GetUniformLocation(global_shader_program, cstring("u_proj"))

        global_gl.UniformMatrix4fv(view_loc,  1, false, &view[0,0])
        global_gl.UniformMatrix4fv(proj_loc,  1, false, &proj[0,0])

        // Draw all renderable entities
        entities := global_ecs_api.query(typeid_of(shared.RENDER_COMPONENT))
        defer delete(entities)

        for entity in entities {
            rc := cast(^shared.RENDER_COMPONENT)global_ecs_api.get_component(entity, typeid_of(shared.RENDER_COMPONENT))
            if rc == nil { continue }

            // Model matrix from POSITION_COMPONENT (sinusoidal movement)
            pos := [3]f32{0, 0, 0}
            if p := cast(^shared.POSITION_COMPONENT)global_ecs_api.get_component(entity, typeid_of(shared.POSITION_COMPONENT)); p != nil {
                pos = {p.x, p.y, p.z}
            }
            model := linalg.matrix4_translate(pos)

            global_gl.UniformMatrix4fv(model_loc, 1, false, &model[0,0])

            global_gl.BindVertexArray(rc.vao)

            if rc.index_count > 0 && rc.ebo != 0 {
                global_gl.DrawElements(shared.GL_TRIANGLES, rc.index_count, rc.index_type, nil)
            } else {
                global_gl.DrawArrays(shared.GL_TRIANGLES, 0, rc.vertex_count)
            }

            global_gl.BindVertexArray(0)
        }

        global_gl.UseProgram(0)
    }   

    // Cleanup rendering resources
    @(export)
    gn_Render_Cleanup :: proc() {
        if global_shader_program != 0 {
            global_gl.DeleteProgram(global_shader_program)
            global_shader_program = 0
        }
    }

    // Initialize rendering resources (shader compilation)
    @(export)
    gn_Render_Init :: proc() -> bool {
        // Clean old program if any (important on hot-reload)
        if global_shader_program != 0 {
            global_gl.DeleteProgram(global_shader_program)
            global_shader_program = 0
        }

        // Pure ASCII, explicitly converted to cstring
        vertex_src := cstring(  `#version 330 core
                                layout (location = 0) in vec3 aPos;
                                uniform mat4 u_model;
                                uniform mat4 u_view;
                                uniform mat4 u_proj;
                                void main() {
                                    gl_Position = u_proj * u_view * u_model * vec4(aPos, 1.0);
                                }
                                `)

        fragment_src := cstring("#version 330 core\nout vec4 FragColor;\nvoid main() { FragColor = vec4(1.0, 0.3, 0.5, 1.0); }\n")

        vs := global_gl.CreateShader(shared.GL_VERTEX_SHADER)
        defer global_gl.DeleteShader(vs)
        global_gl.ShaderSource(vs, 1, &vertex_src, nil)
        global_gl.CompileShader(vs)

        success: i32
        global_gl.GetShaderiv(vs, shared.GL_COMPILE_STATUS, &success)
        if success == 0 {
            info_log: [1024]byte
            global_gl.GetShaderInfoLog(vs, 1024, nil, &info_log[0])
            fmt.eprintf("VERTEX SHADER COMPILATION FAILED:\n%s\n", cstring(&info_log[0]))
            return false
        }

        fs := global_gl.CreateShader(shared.GL_FRAGMENT_SHADER)
        defer global_gl.DeleteShader(fs)
        global_gl.ShaderSource(fs, 1, &fragment_src, nil)
        global_gl.CompileShader(fs)

        global_gl.GetShaderiv(fs, shared.GL_COMPILE_STATUS, &success)
        if success == 0 {
            info_log: [1024]byte
            global_gl.GetShaderInfoLog(fs, 1024, nil, &info_log[0])
            fmt.eprintf("FRAGMENT SHADER COMPILATION FAILED:\n%s\n", cstring(&info_log[0]))
            return false
        }

        global_shader_program = global_gl.CreateProgram()
        global_gl.AttachShader(global_shader_program, vs)
        global_gl.AttachShader(global_shader_program, fs)
        global_gl.LinkProgram(global_shader_program)

        global_gl.GetProgramiv(global_shader_program, shared.GL_LINK_STATUS, &success)
        if success == 0 {
            info_log: [1024]byte
            global_gl.GetProgramInfoLog(global_shader_program, 1024, nil, &info_log[0])
            fmt.eprintf("PROGRAM LINK FAILED:\n%s\n", cstring(&info_log[0]))
            global_gl.DeleteProgram(global_shader_program)
            global_shader_program = 0
            return false
        }

        global_position_loc = global_gl.GetUniformLocation(
            global_shader_program,
            cstring("u_position_offset"),
        )

        if global_position_loc == -1 {
            fmt.eprintf("WARNING: uniform 'u_position_offset' not found or optimized out!\n")
            // You can still continue — just don't upload every frame
            // or fall back to a dummy location
        }

        fmt.printf("RENDER INIT SUCCESS: program=%d, pos_loc=%d\n", global_shader_program, global_position_loc)
        return true
    }
} // End when IS_RENDER_DLL