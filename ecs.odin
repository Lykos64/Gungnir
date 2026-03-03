// ecs.odin
package gungnir

import "core:fmt"
import "core:slice"
import "core:math"
import "shared"
import "core:sync"
import gl "vendor:OpenGL"

// Set to true when building this file as ecs.dll
IS_ECS_DLL :: #config(IS_ECS_DLL, false)

// Global mutex protecting system list during hot-reload
ecs_mutex: sync.Mutex

// Global containers
next_entity_id: shared.ENTITY = 1
ecs_systems: [dynamic]gn_ECS_System
ecs_entities: map[shared.ENTITY]map[typeid]rawptr

// ECS system procedure signature
gn_ECS_System :: proc(dt: f32) // Maybe add more params later for shared states

// Initialize ECS globals
gn_ECS_Init :: proc() {
    ecs_entities = make(map[shared.ENTITY]map[typeid]rawptr)
    ecs_systems = make([dynamic]gn_ECS_System)

    // Make a better way to register systems later
}

gn_ECS_Shutdown :: proc() {
    for _, comp_map in ecs_entities {
        for _, ptr in comp_map { free(ptr) }
        delete(comp_map)
    }
    render_entities := gn_ECS_Query(typeid_of(shared.RENDER_COMPONENT))
    for entity in render_entities {
        rc := cast(^shared.RENDER_COMPONENT) gn_ECS_Get_Component(entity, typeid_of(shared.RENDER_COMPONENT))
        if rc != nil {
            gl.DeleteVertexArrays(1, &rc.vao)
            gl.DeleteBuffers(1, &rc.vbo)
            if rc.ebo != 0 {
                gl.DeleteBuffers(1, &rc.ebo)
            }
    }
}
delete(render_entities)

    delete(ecs_entities)
    delete(ecs_systems)
}

gn_ECS_Create_Entity :: proc() -> shared.ENTITY {
    id := next_entity_id
    next_entity_id += 1
    ecs_entities[id] = make(map[typeid]rawptr)
    return id
}

gn_ECS_Add_Component :: proc(entity: shared.ENTITY, component: $T) {
    if entity not_in ecs_entities {
        return
    }
    ptr := new_clone(component)
    comp_map := ecs_entities[entity]
    comp_map[typeid_of(T)] = ptr
    ecs_entities[entity] = comp_map
}

// Query entities that have a specific component type
gn_ECS_Query :: proc(component_tid: typeid) -> [dynamic]shared.ENTITY {
    result := make([dynamic]shared.ENTITY)
    for entity, comp_map in ecs_entities {
        if component_tid in comp_map {
            append(&result, entity)
        }
    }
    return result 

    // Make it bitset based later for performance
}

gn_ECS_Get_Component :: proc(entity: shared.ENTITY, component_tid: typeid) -> rawptr {
    if entity in ecs_entities {
        if component_tid in ecs_entities[entity] {
            return ecs_entities[entity][component_tid]
        }
    }
    return nil
}

gn_ECS_Update :: proc(dt: f32 = 0.016) { // Default ~60 FPS
    sync.mutex_lock(&ecs_mutex)  
    for sys in ecs_systems {
        sys(dt)
    }
    sync.mutex_unlock(&ecs_mutex)
}

// Hot-reloaded ECS DLL part 
when IS_ECS_DLL {
    global_ecs_api : shared.ECS_API
    global_ecs_offset: f32 = 0.0 // Internal state for movement system

    // Set ECS API for DLL use
    @(export)
    gn_ECS_Set_API :: proc(api: shared.ECS_API) {
        global_ecs_api = api
    }

    // Movement system updates positions sinusoidally
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
            pos.x = math.sin(pos.phase) * 0.5
            pos.y = math.cos(pos.phase) * 0.5
            pos.z = math.sin(pos.phase * 2) * 0.2
        } 
    }

    @(export)
    gn_ECS_Movement_Save_State :: proc() -> f32 {
        return global_ecs_offset // Save the internal state
    }

    @(export)
    gn_ECS_Movement_Load_State :: proc(phase: f32) {
        global_ecs_offset = phase // Load the internal state
    }
}

