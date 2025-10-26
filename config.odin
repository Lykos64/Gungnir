package gungnir

ENGINE_CONFIG :: struct{
    window_width: i32,
    window_height: i32,
    window_title: cstring,
    // Future: render_api: enum { OpenGL, Vulkan, DirectX 12 }
    // ECS tweaks, event queue sizes, etc.

}

gn_Config_Defaults :: proc() -> ENGINE_CONFIG {
    return ENGINE_CONFIG{        
        window_width = 800,
        window_height = 600,
        window_title = cstring("Gungnir"),
    }
}