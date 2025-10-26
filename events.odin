package gungnir

import "core:slice"
import "core:fmt"
import glfw "vendor:glfw" 

// Event as tagged union for types
EVENT :: union {
    KEY_PRESS_EVENT,
    // Add more: Mouse_Move, Entity_Created, etc.
}

KEY_PRESS_EVENT :: struct {
    key: u32, // GLFW key code in u32
}

key_press_event := typeid_of(KEY_PRESS_EVENT)

gn_Events_Handler :: proc (event: EVENT) // Handler proc signature

// Registry: Map of handlers per event type
handlers: map[typeid][dynamic]gn_Events_Handler
event_queue: [dynamic]EVENT 

gn_Events_Init :: proc() {
    handlers = make(map[typeid][dynamic]gn_Events_Handler)
    event_queue = make([dynamic]EVENT) 
} 

gn_Events_Shutdown :: proc() {
    delete(handlers)
    delete(event_queue)
}

gn_Events_Register :: proc(T: typeid, handler: gn_Events_Handler) {
    if T not_in handlers {
        handlers[T] = make([dynamic]gn_Events_Handler)
    }
    append(&handlers[T], handler)
}

gn_Events_Fire :: proc(event: EVENT) {
    append(&event_queue, event) // Queue for later process
}

gn_Events_Process :: proc() {
    for event in event_queue {
        // Handle each variant explicitly to get correct typeid
        switch e in event {
        case KEY_PRESS_EVENT:
            tid := typeid_of(KEY_PRESS_EVENT)
            if tid in handlers {
                for handler in handlers[tid] {
                    handler(event)
                }
            } 
            else {
                fmt.printf("No handlers for event typeid: %v\n", tid)
            }
        case: // Unknown event
            fmt.printf("Unknown event: %v\n", event)
        }
    }
    clear(&event_queue)
}

// Example handler (register in main for systems)
gn_Handle_Key_Press :: proc(event: EVENT) {
    if e, ok := event.(KEY_PRESS_EVENT); ok {
        if e.key == glfw.KEY_ESCAPE {
            glfw.SetWindowShouldClose(global_window.handle, true)
        }
    }
}