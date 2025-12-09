package gungnir

import "core:fmt"
import "core:c"
import "shared"

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

        entities := global_ecs_api.query(typeid_of(shared.RENDER_COMPONENT))
        defer delete(entities)

        for entity in entities {
            rc := cast(^shared.RENDER_COMPONENT)global_ecs_api.get_component(entity, typeid_of(shared.RENDER_COMPONENT))
            if rc == nil { continue }

            global_gl.BindVertexArray(rc.vao)

            pos_x, pos_y, pos_z : f32 = 0, 0, 0
            if pos := cast(^shared.POSITION_COMPONENT)global_ecs_api.get_component(entity, typeid_of(shared.POSITION_COMPONENT)); pos != nil {
                pos_x = pos.x
                pos_y = pos.y
                pos_z = pos.z
            }
            
            if global_position_loc != -1 {
                global_gl.Uniform3f(global_position_loc, pos_x, pos_y, pos_z)
            }

            global_gl.Uniform3f(global_position_loc, pos_x, pos_y, pos_z)
            global_gl.DrawArrays(shared.GL_TRIANGLES, 0, rc.vertex_count)
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
        vertex_src   := cstring("#version 330 core\nlayout (location = 0) in vec3 aPos;\nuniform vec3 u_position_offset;\nvoid main() { gl_Position = vec4(aPos + u_position_offset, 1.0); }\n")
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