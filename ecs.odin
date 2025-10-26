package gungnir

import "core:fmt"
import "core:slice"
import "core:math"
import "shared"
import "core:sync"

ecs_mutex: sync.Mutex

next_entity_id: shared.ENTITY = 1

gn_ECS_System :: proc(dt: f32) // Maybe add more params later for shared states

ecs_systems: [dynamic]gn_ECS_System
ecs_entities: map[shared.ENTITY]map[typeid]rawptr

gn_ECS_Init :: proc() {
    ecs_entities = make(map[shared.ENTITY]map[typeid]rawptr)
    ecs_systems = make([dynamic]gn_ECS_System)
    
    // Register sample system
    sync.mutex_lock(&ecs_mutex)
    append(&ecs_systems, gn_Render_ECS_System)
    sync.mutex_unlock(&ecs_mutex)

    // Make a better way to register systems later
}

gn_ECS_Shutdown :: proc() {
    for _, comp_map in ecs_entities {
        for _, ptr in comp_map { free(ptr) }
        delete(comp_map)
    }
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





