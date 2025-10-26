package gungnir

import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import "core:fmt"
import "core:c"
import "shared"

shader_program: u32 // Global for simplicity
position_loc: i32 // Global uniform location

gn_Render_Init :: proc() {
    gl.ClearColor(0.2, 0.3, 0.3, 1.0)
    gn_Utils_Check_gl_Error("Set Clear Color")
    gl.Enable(gl.DEPTH_TEST)
    gn_Utils_Check_gl_Error("Enable Depth Test")
    
    // Hardcoded simple shaders
    vertex_shader_src : cstring = `#version 330 core
    layout (location = 0) in vec3 aPos;
    uniform vec3 position;
    void main()
    {
        gl_Position = vec4(aPos + position, 1.0);
    }` 

    fragment_shader_src : cstring = `#version 330 core
    out vec4 FragColor;
    void main()
    {
        FragColor = vec4(1.0, 0.0, 0.0, 1.0);
    }` 

    // Compile vertex
    vs := gl.CreateShader(gl.VERTEX_SHADER)
    gl.ShaderSource(vs, 1, &vertex_shader_src, nil)
    gl.CompileShader(vs)
    gn_Utils_Check_gl_Error("Compile Vertex Shader")
    success: i32
    gl.GetShaderiv(vs, gl.COMPILE_STATUS, &success)
    if success == 0 {
        info_log: [512]byte
        gl.GetShaderInfoLog(vs, 512, nil, &info_log[0])
        fmt.eprintf("Vertex shader compile failed: %s\n", cstring(&info_log[0]))
    }
    
    // Compile fragment
    fs := gl.CreateShader(gl.FRAGMENT_SHADER)
    gl.ShaderSource(fs, 1, &fragment_shader_src, nil)
    gl.CompileShader(fs)
    gn_Utils_Check_gl_Error("Compile Fragment Shader")
    gl.GetShaderiv(fs, gl.COMPILE_STATUS, &success)
    if success == 0 {
        info_log: [512]byte
        gl.GetShaderInfoLog(fs, 512, nil, &info_log[0])
        fmt.eprintf("Fragment shader compile failed: %s\n", cstring(&info_log[0]))
    }
    
    // Link program
    shader_program = gl.CreateProgram()
    gl.AttachShader(shader_program, vs)
    gn_Utils_Check_gl_Error("Attach Vertex Shader")
    gl.AttachShader(shader_program, fs)
    gn_Utils_Check_gl_Error("Attach Fragment Shader")
    gl.LinkProgram(shader_program)
    gn_Utils_Check_gl_Error("Link Shader Program")
    gl.GetProgramiv(shader_program, gl.LINK_STATUS, &success)
    if success == 0 {
        info_log: [512]byte
        gl.GetProgramInfoLog(shader_program, 512, nil, &info_log[0])
        fmt.eprintf("Shader link failed: %s\n", cstring(&info_log[0]))
    }

    position_loc = gl.GetUniformLocation(shader_program, cstring("position"))
    if position_loc == -1 {
        fmt.eprintln("Could not find uniform 'position' in shader")
    }
    gn_Utils_Check_gl_Error("Get Uniform Location")
    
    // Cleanup
    gl.DeleteShader(vs)
    gl.DeleteShader(fs)
}

gn_Render_Begin :: proc() {
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
    // Actual rendering happens in gn_Render_System via ECS
    gn_Utils_Check_gl_Error("Clear Frame")
}

gn_Render_End :: proc() {
    glfw.SwapBuffers(global_window.handle)
    gn_Utils_Check_gl_Error("Swap Buffers")
}

gn_Render_ECS_System :: proc(dt: f32) {
    gl.UseProgram(shader_program)
    gn_Utils_Check_gl_Error("Use Shader Program")
    
    render_entities := gn_ECS_Query(typeid_of(shared.RENDER_COMPONENT))
    defer delete(render_entities)
    for entity in render_entities {
        rc := cast(^shared.RENDER_COMPONENT) gn_ECS_Get_Component(entity, typeid_of(shared.RENDER_COMPONENT))
        if rc != nil { 
            gl.BindVertexArray(rc.vao)
            gn_Utils_Check_gl_Error("Bind VAO")

            // Apply position if entity has a POSITION_COMPONENT 
            pos_x, pos_y, pos_z: f32 = 0.0, 0.0, 0.0 // Uniform position
            if pos := cast(^shared.POSITION_COMPONENT) gn_ECS_Get_Component(entity, typeid_of(shared.POSITION_COMPONENT)); pos != nil {
                pos_x = pos.x
                pos_y = pos.y
                pos_z = pos.z
            }
            gl.Uniform3f(position_loc, pos_x, pos_y, pos_z)
            gn_Utils_Check_gl_Error("Set Uniform Position")

            gl.DrawArrays(gl.TRIANGLES, 0, rc.vertex_count)
            gn_Utils_Check_gl_Error("Draw Arrays")
            gl.BindVertexArray(0)
            gn_Utils_Check_gl_Error("Unbind VAO")
        }
    }

    gl.UseProgram(0)
    gn_Utils_Check_gl_Error("Unuse Shader Program")
}
