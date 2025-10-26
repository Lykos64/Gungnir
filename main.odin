package gungnir

import "core:fmt"
import "core:os"
import "core:time"
import glfw "vendor:glfw" // Assuming vendored in root
import gl "vendor:OpenGL" // Ditto
import "shared"
import "core:sync"

main :: proc () {
    // Init config (modular: pass to subsystems)
    config :=  gn_Config_Defaults()

    // Init windowing system
    if !gn_Window_Init(&config) {
        fmt.eprintln ("Window init failed!")
        return
    }
    defer gn_Window_Shutdown()

    // Init ECS and events (backbones)
    gn_Events_Init()
    defer gn_Events_Shutdown()
    gn_Events_Register(key_press_event, gn_Handle_Key_Press) // Integrate handler
    
    gn_ECS_Init()
    defer gn_ECS_Shutdown()

    gn_HotReload_Init()
    sync.mutex_lock(&ecs_mutex)
    append(&ecs_systems, hot_state.movement_proc) // Dynamic movement system
    sync.mutex_unlock(&ecs_mutex)

    gn_Render_Init()

    // Test entity: Simple triangle
    entity := gn_ECS_Create_Entity()
    // Setup VAO/VBO for triangle (stub: hardcode vertices)
    vertices := [9]f32{ -0.5, -0.5, 0.0, 0.5, -0.5, 0.0, 0.0, 0.5, 0.0 }
    vao, vbo: u32
    gl.GenVertexArrays(1, &vao)
    gn_Utils_Check_gl_Error("Generate VAO")
    gl.GenBuffers(1, &vbo)
    gn_Utils_Check_gl_Error("Generate VBO")
    gl.BindVertexArray(vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), raw_data(vertices[:]), gl.STATIC_DRAW)
    gn_Utils_Check_gl_Error("Buffer Data")
    gl.VertexAttribPointer(0, 3, gl.FLOAT, false, 3 * size_of(f32), 0)
    gn_Utils_Check_gl_Error("Vertex Attrib Pointer")
    gl.EnableVertexAttribArray(0)
    gn_Utils_Check_gl_Error("Enable Vertex Attrib Array")
    gl.BindBuffer(gl.ARRAY_BUFFER, 0)
    gl.BindVertexArray(0)
    gn_ECS_Add_Component(entity, shared.RENDER_COMPONENT{vao = vao, vertex_count = 3})
    gn_ECS_Add_Component(entity, shared.POSITION_COMPONENT{x = 0.0, y = 0.0, z = 0.0})

    defer gl.DeleteVertexArrays(1, &vao)
    defer gl.DeleteBuffers(1, &vbo)

    gl.Viewport(0, 0, global_window.width, global_window.height)
    gn_Utils_Check_gl_Error("Set Viewport")
    

    // Main loop
    last_time := time.now()
    for !gn_Window_Should_Close() {
        gn_Window_Poll_Events()
        gn_Events_Process()  // Handle events

        dt := f32(time.duration_seconds(time.since(last_time)))
        last_time = time.now()

        gn_Render_Begin()  // Clear here
        gn_ECS_Update(dt)  // Systems tick (includes render_system)
        gn_Render_End()    // Swap here
    }

    // Cleanup
    gl.DeleteVertexArrays(1, &vao)
    gl.DeleteBuffers(1, &vbo)
    
}