package gungnir

import "core:fmt"
import "core:os"
import "core:time"
import glfw "vendor:glfw" // Assuming vendored in root
import gl "vendor:OpenGL" // Ditto
import "shared"
import "core:sync"
import "core:math"
import "core:math/linalg"
import "base:runtime"

render_ready := false

// Camera mouse look state (persistent across callback calls)
last_mouse_x, last_mouse_y: f64 = 400, 300
first_mouse: bool = true

global_camera: shared.CAMERA_COMPONENT
camera_entity: shared.ENTITY

main :: proc () {
    // Init config (modular: pass to subsystems)
    config :=  gn_Config_Defaults()

    // Init windowing system
    if !gn_Window_Init(&config) {
        fmt.eprintln ("Window init failed!")
        return
    }
    defer gn_Window_Shutdown()

    // Init ECS, events and hot-reload (backbones)
    gn_Events_Init()
    defer gn_Events_Shutdown()
    gn_Events_Register(key_press_event, gn_Handle_Key_Press) // Integrate handler
    
    gn_ECS_Init()
    defer gn_ECS_Shutdown()

    gn_Hotreload_Init()

    // === CAMERA ===
    camera_entity = gn_ECS_Create_Entity()

    global_camera = shared.CAMERA_COMPONENT{
        position     = {0, 2, 5},
        yaw          = -90,
        pitch        = 0,
        speed        = 5.0,
        sensitivity  = 0.1,
    }
    gn_ECS_Add_Component(camera_entity, global_camera)

    // === Model ===
    entity := gn_ECS_Create_Entity()

    vao, vbo, ebo, vert_count, idx_count, idx_type, ok := gn_Load_GLTF_Mesh("assets/Box.glb") // or Duck.glb, etc.
    if !ok {
        fmt.eprintln("Failed to load glTF/GLB model")
        return
    }

    gn_ECS_Add_Component(entity, shared.RENDER_COMPONENT{
        vao          = vao,
        vbo          = vbo,
        ebo          = ebo,
        vertex_count = vert_count,
        index_count  = idx_count,
        index_type   = idx_type,
    })
    gn_ECS_Add_Component(entity, shared.POSITION_COMPONENT{x = 0, y = 0, z = 0})

    // Mouse setup for look
    glfw.SetInputMode(global_window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)
    glfw.SetCursorPosCallback(global_window.handle, gn_Window_Mouse_Callback)

    gl.Viewport(0, 0, global_window.width, global_window.height)
    gn_Utils_Check_gl_Error("Set Viewport")
    

    // Main loop
    last_time := time.now()
    for !gn_Window_Should_Close() {
        gn_Window_Poll_Events()
        gn_Events_Process()

        dt := f32(time.duration_seconds(time.since(last_time)))
        last_time = time.now()

        // Handle reloads here
        if ecs_reload_needed {
            gn_Hotreload_ECS_Reload()
            ecs_reload_needed = false
        }

        if render_reload_needed {
            gn_Hotreload_Render_Reload()
            fmt.printf("Render hot-reload done – enabling draw next frame\n")
            render_reload_needed = false
            render_ready = false 
        }

        if !render_ready {
            gn_Window_Clear()
            gn_Window_Swap()
            render_ready = true
            continue
        }

        gn_Window_Clear()       // Clears to light blue
        gn_Camera_Update(dt)    // Updates camera position based on input
        gn_ECS_Update(dt)       // Runs systems (movement + render)
        gn_Window_Swap()        // Shows the frame
    }

    // Cleanup
    // gl.DeleteVertexArrays(1, &vao)
    // gl.DeleteBuffers(1, &vbo)
    
}

gn_Camera_Update :: proc(dt: f32) {
    win := global_window.handle
    cam := &global_camera

    speed := cam.speed * dt

    // Forward direction (proper FPS camera math)
    yaw_rad   := linalg.to_radians(cam.yaw)
    pitch_rad := linalg.to_radians(cam.pitch)

    front := linalg.vector_normalize([3]f32{
        math.cos(yaw_rad) * math.cos(pitch_rad),
        math.sin(pitch_rad),
        math.sin(yaw_rad) * math.cos(pitch_rad),
    })

    right := linalg.vector_normalize(linalg.cross(front, [3]f32{0, 1, 0}))  // ← fixed type

    // Movement
    if glfw.GetKey(win, glfw.KEY_W)            == glfw.PRESS { cam.position += front * speed }
    if glfw.GetKey(win, glfw.KEY_S)            == glfw.PRESS { cam.position -= front * speed }
    if glfw.GetKey(win, glfw.KEY_A)            == glfw.PRESS { cam.position -= right * speed }
    if glfw.GetKey(win, glfw.KEY_D)            == glfw.PRESS { cam.position += right * speed }
    if glfw.GetKey(win, glfw.KEY_SPACE)        == glfw.PRESS { cam.position.y += speed }
    if glfw.GetKey(win, glfw.KEY_LEFT_CONTROL) == glfw.PRESS { cam.position.y -= speed }

    // Sync back to ECS component
    if comp := cast(^shared.CAMERA_COMPONENT)gn_ECS_Get_Component(camera_entity, typeid_of(shared.CAMERA_COMPONENT)); comp != nil {
        comp^ = global_camera
    }
}

gn_Window_Mouse_Callback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
    context = runtime.default_context()

    if first_mouse {
        last_mouse_x, last_mouse_y = xpos, ypos
        first_mouse = false
        return
    }

    xoffset := f32(xpos - last_mouse_x)
    yoffset := f32(last_mouse_y - ypos) // reversed for natural feel
    last_mouse_x, last_mouse_y = xpos, ypos

    global_camera.yaw   += xoffset * global_camera.sensitivity
    global_camera.pitch += yoffset * global_camera.sensitivity

    global_camera.pitch = math.clamp(global_camera.pitch, -89, 89)
}