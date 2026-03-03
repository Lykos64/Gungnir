// hotreload.odin
package gungnir

import "core:os"
import "core:thread"
import "core:time"
import "core:fmt"
import "core:dynlib"
import "core:strings"
import "shared"
import "core:sync"

// ====================== STATE ======================
HOTRELOAD_STATE :: struct {
    lib_handle:    dynlib.Library,
    last_mod_time: time.Time,
    system_proc:   gn_ECS_System,   
    temp_path:     string,
}

hot_state:        HOTRELOAD_STATE
render_hot_state: HOTRELOAD_STATE

ecs_reload_needed:    bool = false
render_reload_needed: bool = false

// ====================== CLEANUP ======================
// Deletes ALL old temp DLLs on startup
gn_Hotreload_Cleanup_Old_Temps :: proc() {
    dir_handle, open_err := os.open(".")
    if open_err != nil {
        fmt.eprintf("Cleanup: cannot open current dir\n")
        return
    }
    defer os.close(dir_handle)

    files, read_err := os.read_dir(dir_handle, -1, context.temp_allocator)
    if read_err != nil {
        return
    }
    defer delete(files, context.temp_allocator)

    for &f in files {
        name := f.name
        if (strings.has_prefix(name, "ecs_temp_") || strings.has_prefix(name, "render_temp_")) &&
           strings.has_suffix(name, ".dll") {
            if os.remove(name) == nil {
                fmt.printf("🧹 Cleaned old temp: %s\n", name)
            }
        }
    }
}

// ====================== ECS ======================
gn_Hotreload_ECS_DLL_startup :: proc() {
    fmt.printf("=== GUNGNIR ECS COLD START ===\n")
    gn_Hotreload_Cleanup_Old_Temps()
    gn_Hotreload_ECS_Load("ecs.dll")
    thread.create_and_start(gn_Hotreload_Thread_Proc)
}

gn_Hotreload_ECS_Load :: proc(src: string) {
    unique_temp := fmt.tprintf("ecs_temp_%d.dll", time.now()._nsec % 1_000_000)

    if !gn_Utils_Copy_File(src, unique_temp) { return }

    lib, ok := dynlib.load_library(unique_temp)
    if !ok { return }

    hot_state.lib_handle = lib
    hot_state.temp_path  = unique_temp

    if addr, found := dynlib.symbol_address(lib, "gn_ECS_Movement_System"); found {
        hot_state.system_proc = cast(gn_ECS_System)addr
    }

    if set_api_addr, ok := dynlib.symbol_address(lib, "gn_ECS_Set_API"); ok {
        set_api := cast(proc(shared.ECS_API))set_api_addr
        set_api(shared.ECS_API{query = gn_ECS_Query, get_component = gn_ECS_Get_Component})
    }

    sync.mutex_lock(&ecs_mutex)
    append(&ecs_systems, hot_state.system_proc)
    sync.mutex_unlock(&ecs_mutex)

    if info, err := os.stat(src, context.allocator); err == nil {
        hot_state.last_mod_time = info.modification_time
    }
}

gn_Hotreload_ECS_Unload :: proc() {
    if hot_state.lib_handle != nil {
        dynlib.unload_library(hot_state.lib_handle)
        hot_state.lib_handle = nil
    }
    if hot_state.temp_path != "" {
        for i := 0; i < 8; i += 1 {
            if os.remove(hot_state.temp_path) == nil { break }
            time.sleep(50 * time.Millisecond)
        }
        hot_state.temp_path = ""
    }
}

gn_Hotreload_ECS_Reload :: proc() {
    fmt.printf("ECS hot-reload\n")
    sync.mutex_lock(&ecs_mutex)
    for i := 0; i < len(ecs_systems); {
        if ecs_systems[i] == hot_state.system_proc {
            ordered_remove(&ecs_systems, i)
            continue
        }
        i += 1
    }
    sync.mutex_unlock(&ecs_mutex)

    gn_Hotreload_ECS_Unload()
    time.sleep(150 * time.Millisecond)
    gn_Hotreload_ECS_Load("ecs.dll")
    fmt.printf("ECS hot-reload complete\n")
}

// ====================== RENDER ======================
gn_Hotreload_Render_DLL_startup :: proc() {
    fmt.printf("=== GUNGNIR RENDER COLD START ===\n")
    gn_Hotreload_Cleanup_Old_Temps()
    gn_Hotreload_Render_Load("render.dll")
    thread.create_and_start(gn_Hotreload_Render_Thread_Proc)
}

gn_Hotreload_Render_Load :: proc(src: string) {
    unique_temp := fmt.tprintf("render_temp_%d.dll", time.now()._nsec % 1_000_000)

    if !gn_Utils_Copy_File(src, unique_temp) { return }

    lib, ok := dynlib.load_library(unique_temp)
    if !ok { return }

    render_hot_state.lib_handle = lib
    render_hot_state.temp_path  = unique_temp

    if addr, found := dynlib.symbol_address(lib, "gn_Render_ECS_System"); found {
        render_hot_state.system_proc = cast(gn_ECS_System)addr
    }

    if gl_api_addr, ok := dynlib.symbol_address(lib, "gn_Render_Set_GL_API"); ok {
        set_gl := cast(proc(shared.RENDER_GL_API))gl_api_addr
        set_gl(global_render_gl_api)
    }

    if ecs_api_addr, ok := dynlib.symbol_address(lib, "gn_Render_Set_API"); ok {
        set_ecs := cast(proc(shared.ECS_API))ecs_api_addr
        set_ecs(shared.ECS_API{query = gn_ECS_Query, get_component = gn_ECS_Get_Component})
    }

    if init_addr, ok := dynlib.symbol_address(lib, "gn_Render_Init"); ok {
        init_proc := cast(proc() -> bool)init_addr
        init_proc()
    }

    sync.mutex_lock(&ecs_mutex)
    append(&ecs_systems, render_hot_state.system_proc)
    sync.mutex_unlock(&ecs_mutex)

    if info, err := os.stat(src, context.allocator); err == nil {
        render_hot_state.last_mod_time = info.modification_time
    }
}

gn_Hotreload_Render_Unload :: proc() {
    if render_hot_state.lib_handle != nil {
        dynlib.unload_library(render_hot_state.lib_handle)
        render_hot_state.lib_handle = nil
    }
    if render_hot_state.temp_path != "" {
        for i := 0; i < 8; i += 1 {
            if os.remove(render_hot_state.temp_path) == nil { break }
            time.sleep(50 * time.Millisecond)
        }
        render_hot_state.temp_path = ""
    }
}

gn_Hotreload_Render_Reload :: proc() {
    fmt.printf("Render hot-reload\n")
    sync.mutex_lock(&ecs_mutex)
    for i := 0; i < len(ecs_systems); {
        if ecs_systems[i] == render_hot_state.system_proc {
            ordered_remove(&ecs_systems, i)
            continue
        }
        i += 1
    }
    sync.mutex_unlock(&ecs_mutex)

    gn_Hotreload_Render_Unload()
    time.sleep(400 * time.Millisecond)
    gn_Hotreload_Render_Load("render.dll")
    fmt.printf("Render hot-reload complete\n")
}

// ====================== THREADS ======================
gn_Hotreload_Thread_Proc :: proc() {
    for {
        time.sleep(500 * time.Millisecond)
        if info, err := os.stat("ecs.dll", context.allocator); err == nil &&
           info.modification_time._nsec > hot_state.last_mod_time._nsec {
            ecs_reload_needed = true
        }
    }
}

gn_Hotreload_Render_Thread_Proc :: proc() {
    for {
        time.sleep(500 * time.Millisecond)
        if info, err := os.stat("render.dll", context.allocator); err == nil &&
           info.modification_time._nsec > render_hot_state.last_mod_time._nsec {
            render_reload_needed = true
        }
    }
}

// ====================== INIT ======================
gn_Hotreload_Init :: proc() {
    gn_Hotreload_Cleanup_Old_Temps()
    gn_Hotreload_ECS_DLL_startup()
    gn_Hotreload_Render_DLL_startup()
}