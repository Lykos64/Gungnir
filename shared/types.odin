package gungnir_shared

import "core:slice" // If needed for [dynamic]

// Shared types used by both executable and DLL

ENTITY :: u64

COMPONENT :: struct {
    // Add component data here    
}

POSITION_COMPONENT :: struct {
    using base: COMPONENT,
    phase: f32,
    x, y, z: f32,
}

RENDER_COMPONENT :: struct {
    using base: COMPONENT,
    vao: u32,  // OpenGL Vertex Array Object
    vertex_count: i32,
}

ECS_API :: struct {
    query : proc "odin" (T: typeid) -> [dynamic]ENTITY,
    get_component : proc "odin" (entity: ENTITY, T: typeid) -> rawptr,
}
