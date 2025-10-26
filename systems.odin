package gungnir

import "core:math"
import "core:fmt"
import "shared"

global_ecs_api : shared.ECS_API

global_offset: f32 = 0.0 // Internal state for movement system

@(export)
gn_ECS_Set_API :: proc(api: shared.ECS_API) {
    global_ecs_api = api
}

@(export)
gn_ECS_Movement_System :: proc(dt: f32) {
    entities := global_ecs_api.query(typeid_of(shared.POSITION_COMPONENT))
    defer delete(entities)
    for entity in entities {
        pos := cast(^shared.POSITION_COMPONENT) global_ecs_api.get_component(entity, typeid_of(shared.POSITION_COMPONENT))
        if pos == nil {
            fmt.printf("Entity %d has no POSITION_COMPONENT!\n", entity)
            continue
        }
        pos.phase += dt
        pos.x = math.sin(pos.phase) * 1.5
        pos.y = math.cos(pos.phase) * 0.5
        pos.z = math.sin(pos.phase * 2) * 0.2
    } 
}

@(export)
gn_ECS_Movement_Save_State :: proc() -> f32 {
    return global_offset // Save the internal state
}

@(export)
gn_ECS_Movement_Load_State :: proc(phase: f32) {
    global_offset = phase // Load the internal state
}