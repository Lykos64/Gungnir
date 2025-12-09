// hotreload.odin
package gungnir

import "core:os"
import "core:thread"
import "core:time"
import "core:fmt"
import "core:dynlib"
import "shared"
import "core:sync"

// Hot-reload state for ECS DLL
HOTRELOAD_STATE :: struct {
    lib_handle: dynlib.Library,
    last_mod_time: time.Time,
    movement_proc: gn_ECS_System,
}

hot_state: HOTRELOAD_STATE

// Hot-reload state for Render DLL
RENDER_HOTRELOAD_STATE :: struct {
    lib_handle: dynlib.Library,
    last_mod_time: time.Time,
    render_proc: gn_ECS_System,
}

render_hot_state: RENDER_HOTRELOAD_STATE

ecs_reload_needed: bool = false
render_reload_needed: bool = false

// Initialize hot-reloading for DLLs (ECS and Render)
gn_Hotreload_Init :: proc() {
    fmt.printf("=== GUNGNIR COLD START HOT-RELOAD ===\n")

    gn_Hotreload_ECS_DLL_startup()
    if info, err := os.stat("ecs.dll"); err == os.ERROR_NONE {
        hot_state.last_mod_time = info.modification_time
    }

    gn_Hotreload_Render_DLL_startup()
    if info, err := os.stat("render.dll"); err == os.ERROR_NONE {
        render_hot_state.last_mod_time = info.modification_time
    }

    thread.create_and_start(gn_Hotreload_Thread_Proc)
    thread.create_and_start(gn_Hotreload_Render_Thread_Proc)
}

// Thread to watch for ECS DLL changes
gn_Hotreload_Thread_Proc :: proc() {
    for {
        time.sleep(500 * time.Millisecond)
        info, err := os.stat("ecs.dll")
        if err != os.ERROR_NONE { continue }
        else if info.modification_time._nsec > hot_state.last_mod_time._nsec {
            hot_state.last_mod_time = info.modification_time
            ecs_reload_needed = true
            fmt.printf("ECS hot-reload queued\n")
        }
    }
}

// Perform ECS DLL reload
gn_Hotreload_ECS_Reload :: proc() {
    fmt.printf("Performing ECS hot-reload!\n")
    TEMP_DLL_PATH :: "ecs_temp.dll"

    old_proc := hot_state.movement_proc

    // Remove old system
    sync.mutex_lock(&ecs_mutex)
    for i := 0; i < len(ecs_systems); {
        if ecs_systems[i] == old_proc {
            ordered_remove(&ecs_systems, i)
            continue
        }
        i += 1
    }
    sync.mutex_unlock(&ecs_mutex)

    // Save state + unload old DLL
    if hot_state.lib_handle != nil {
        if save_addr, ok := dynlib.symbol_address(hot_state.lib_handle, "gn_ECS_Movement_Save_State"); ok {
            save_proc := cast(shared.RENDER_STATE_SAVE_PROC)save_addr
            // Store it temporarily – will be restored in new DLL after load
            _ = save_proc() 
        }
        dynlib.unload_library(hot_state.lib_handle)
        os.remove(TEMP_DLL_PATH)
    }

    time.sleep(500 * time.Millisecond)

    // Load new version
    if !gn_Utils_Copy_File("ecs.dll", TEMP_DLL_PATH) {
        fmt.eprintf("Failed to copy ecs.dll for reload\n")
        return
    }

    new_lib, ok := dynlib.load_library(TEMP_DLL_PATH)
    if !ok {
        fmt.eprintf("Failed to load new ecs_temp.dll\n")
        return
    }
    hot_state.lib_handle = new_lib

    // Get new system proc
    proc_addr, found := dynlib.symbol_address(new_lib, "gn_ECS_Movement_System")
    if !found {
        fmt.eprintf("gn_ECS_Movement_System not found after reload!\n")
        return
    }
    hot_state.movement_proc = cast(gn_ECS_System)proc_addr

    // Inject ECS API 
    if set_api_addr, ok := dynlib.symbol_address(new_lib, "gn_ECS_Set_API"); ok {
        set_api := cast(proc(api: shared.ECS_API))set_api_addr
        set_api(shared.ECS_API{
            query = gn_ECS_Query,
            get_component = gn_ECS_Get_Component,
        })
    }

    // Register new system
    sync.mutex_lock(&ecs_mutex)
    append(&ecs_systems, hot_state.movement_proc)
    sync.mutex_unlock(&ecs_mutex)

    fmt.printf("ECS hot-reload complete\n")
}

// Load ECS DLL on startup
gn_Hotreload_ECS_DLL_startup :: proc() {
    TEMP_DLL_PATH :: "ecs_temp.dll"

    if !gn_Utils_Copy_File("ecs.dll", TEMP_DLL_PATH) {
        fmt.eprintf("Cold load: failed to copy ecs.dll\n")
        return
    }

    lib, ok := dynlib.load_library(TEMP_DLL_PATH)
    if !ok {
        fmt.eprintf("Cold load: failed to load ecs_temp.dll\n")
        return
    }
    hot_state.lib_handle = lib

    proc_addr, found := dynlib.symbol_address(lib, "gn_ECS_Movement_System")
    if !found {
        fmt.eprintf("Cold load: gn_ECS_Movement_System missing\n")
        return
    }
    hot_state.movement_proc = cast(gn_ECS_System)proc_addr

    // Inject ECS API on cold load too
    if set_api_addr, ok := dynlib.symbol_address(lib, "gn_ECS_Set_API"); ok {
        set_api := cast(proc(api: shared.ECS_API))set_api_addr
        set_api(shared.ECS_API{
            query = gn_ECS_Query,
            get_component = gn_ECS_Get_Component,
        })
    }

    sync.mutex_lock(&ecs_mutex)
    append(&ecs_systems, hot_state.movement_proc)
    sync.mutex_unlock(&ecs_mutex)

    fmt.printf("Cold ECS load complete - movement system active\n")
}

// Thread to watch for Render DLL changes
gn_Hotreload_Render_Thread_Proc :: proc() {
    DLL_PATH :: "render.dll"
    for {
        time.sleep(500 * time.Millisecond)
        info, err := os.stat(DLL_PATH)
        if err != os.ERROR_NONE { continue }
        if info.modification_time._nsec > render_hot_state.last_mod_time._nsec {
            render_hot_state.last_mod_time = info.modification_time
            render_reload_needed = true
            fmt.printf("Render.dll changed → hot-reload queued\n")
        }
    }
}

// Perform Render DLL reload
gn_Hotreload_Render_Reload :: proc() {
    fmt.printf("Performing Render hot-reload!\n")
    TEMP_DLL_PATH :: "render_temp.dll"
    old_proc := render_hot_state.render_proc

    // Cleanup old DLL
    if render_hot_state.lib_handle != nil {
        sync.mutex_lock(&ecs_mutex)
        for i := 0; i < len(ecs_systems); {
            if ecs_systems[i] == old_proc {
                ordered_remove(&ecs_systems, i)
                continue
            }
            i += 1
        }
        sync.mutex_unlock(&ecs_mutex)

        // Save state (if exists)
        if save_addr, ok := dynlib.symbol_address(render_hot_state.lib_handle, "gn_Render_Save_State"); ok {
            save_proc := cast(shared.RENDER_STATE_SAVE_PROC)save_addr
            _ = save_proc()
        }

        // Cleanup OpenGL objects created by old DLL
        if cleanup_addr, ok := dynlib.symbol_address(render_hot_state.lib_handle, "gn_Render_Cleanup"); ok {
            cleanup := cast(proc())cleanup_addr
            cleanup()
        }

        dynlib.unload_library(render_hot_state.lib_handle)
        render_hot_state.lib_handle = nil
        os.remove(TEMP_DLL_PATH)
    }

    time.sleep(800 * time.Millisecond) // give Windows time to release the file lock

    // Load new DLL
    if !gn_Utils_Copy_File("render.dll", TEMP_DLL_PATH) {
        fmt.eprintf("Render reload: copy failed\n")
        return
    }

    new_lib, ok := dynlib.load_library(TEMP_DLL_PATH)
    if !ok {
        fmt.eprintf("Render reload: failed to load render_temp.dll\n")
        return
    }
    render_hot_state.lib_handle = new_lib

    // Get render system proc
    proc_addr, found := dynlib.symbol_address(new_lib, "gn_Render_ECS_System")
    if !found {
        fmt.eprintf("gn_Render_ECS_System not found!\n")
        return
    }
    new_render_proc := cast(gn_ECS_System)proc_addr

    // Inject BOTH APIs
    // 1. OpenGL proxy API
    if gl_api_addr, ok := dynlib.symbol_address(new_lib, "gn_Render_Set_GL_API"); ok {
        set_gl := cast(proc(api: shared.RENDER_GL_API))gl_api_addr
        set_gl(global_render_gl_api)
    }

    // 2. ECS query/get API 
    if ecs_api_addr, ok := dynlib.symbol_address(new_lib, "gn_Render_Set_API"); ok {
        set_ecs := cast(proc(api: shared.ECS_API))ecs_api_addr
        set_ecs(shared.ECS_API{
            query = gn_ECS_Query,
            get_component = gn_ECS_Get_Component,
        })
    } else {
        fmt.eprintf("FATAL: gn_Render_Set_API not found in render.dll – cannot continue\n")
        dynlib.unload_library(new_lib)
        return
    }

    // Init shaders in the new DLL
    init_success := false
    if init_addr, ok := dynlib.symbol_address(new_lib, "gn_Render_Init"); ok {
        init_proc := cast(proc() -> bool)init_addr
        init_success = init_proc()
    }

    if !init_success {
        fmt.eprintf("FATAL: gn_Render_Init failed after hot-reload\n")
        dynlib.unload_library(new_lib)
        render_hot_state.lib_handle = nil
        return
    }

    // Register the new render system
    render_hot_state.render_proc = new_render_proc
    sync.mutex_lock(&ecs_mutex)
    append(&ecs_systems, render_hot_state.render_proc)
    sync.mutex_unlock(&ecs_mutex)

    fmt.printf("Render hot-reload complete – rendering active again\n")
}

// Load Render DLL on startup
gn_Hotreload_Render_DLL_startup :: proc() {
    TEMP_DLL_PATH :: "render_temp.dll"

    if !gn_Utils_Copy_File("render.dll", TEMP_DLL_PATH) {
        fmt.eprintf("Cold load: failed to copy render.dll\n")
        return
    }

    lib, ok := dynlib.load_library(TEMP_DLL_PATH)
    if !ok {
        fmt.eprintf("Cold load: failed to load render_temp.dll\n")
        return
    }
    render_hot_state.lib_handle = lib

    proc_addr, found := dynlib.symbol_address(lib, "gn_Render_ECS_System")
    if !found {
        fmt.eprintf("Cold load: gn_Render_ECS_System missing\n")
        return
    }
    render_hot_state.render_proc = cast(gn_ECS_System)proc_addr

    // Inject OpenGL proxy API
    if gl_api_addr, ok := dynlib.symbol_address(lib, "gn_Render_Set_GL_API"); ok {
        set_gl := cast(proc(api: shared.RENDER_GL_API))gl_api_addr
        set_gl(global_render_gl_api)
    }

    // Inject ECS API 
    if ecs_api_addr, ok := dynlib.symbol_address(lib, "gn_Render_Set_API"); ok {
        set_ecs := cast(proc(api: shared.ECS_API))ecs_api_addr
        set_ecs(shared.ECS_API{
            query = gn_ECS_Query,
            get_component = gn_ECS_Get_Component,
        })
    } else {
        fmt.eprintf("FATAL: gn_Render_Set_API missing on cold load\n")
        dynlib.unload_library(lib)
        return
    }

    // Initialise shaders
    init_success := false
    if init_addr, ok := dynlib.symbol_address(lib, "gn_Render_Init"); ok {
        init_proc := cast(proc() -> bool)init_addr
        init_success = init_proc()
    }

    if !init_success {
        fmt.eprintf("FATAL: Render cold-load init failed\n")
        dynlib.unload_library(lib)
        render_hot_state.lib_handle = nil
        return
    }

    sync.mutex_lock(&ecs_mutex)
    append(&ecs_systems, render_hot_state.render_proc)
    sync.mutex_unlock(&ecs_mutex)

    fmt.printf("Cold Render load successful - shaders compiled, ready to draw\n")
}