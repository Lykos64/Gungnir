package gungnir

import glfw "vendor:glfw" 
import gl "vendor:OpenGL" 
import "core:fmt"
import "base:runtime"

Window :: struct {
    handle: glfw.WindowHandle,
    width, height: i32,
}

global_window : Window

gn_Window_Init :: proc(config: ^ENGINE_CONFIG) -> bool {
    if !glfw.Init() { 
        fmt.eprintln("Failed to initialize GLFW")
        return false
     }
    
    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

    global_window.handle = glfw.CreateWindow(config.window_width, // Width
                                             config.window_height, // Height
                                             config.window_title, // Title
                                             nil, nil)
    {
        if global_window.handle == nil {
            fmt.eprintln("Failed to create GLFW window") 
            return false
        }
    }
    
    // Set globals form config for later use (e.g. viewport)
    global_window.width = config.window_width
    global_window.height = config.window_height

    glfw.MakeContextCurrent(global_window.handle)
    gl.load_up_to(3, 3, glfw.gl_set_proc_address) // Load OpenGL functions

    // Input setup
    glfw.SetKeyCallback(global_window.handle, gn_Window_Key_Callback)
    
    return true
}

gn_Window_Shutdown :: proc() {
    glfw.DestroyWindow(global_window.handle)
    glfw.Terminate()
}

gn_Window_Should_Close :: proc() -> b32 {
    return glfw.WindowShouldClose(global_window.handle)
}

gn_Window_Poll_Events :: proc() {
    glfw.PollEvents()
}

// Example callback: Fire events
gn_Window_Key_Callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
    context = runtime.default_context()
    fmt.printf("Key callback: key=%d action=%d\n", key, action)
    if action == glfw.PRESS {
        gn_Events_Fire(KEY_PRESS_EVENT{key = cast(u32)key}) //Fire to event System
    }
}