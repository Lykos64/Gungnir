package gungnir

import "core:os"
import "core:thread"
import "core:time"
import "core:fmt"
import "core:dynlib"
import "shared"
import "core:sync"

HOTRELOAD_STATE :: struct {
    lib_handle: dynlib.Library,
    last_mod_time: time.Time, 
    movement_proc: gn_ECS_System,
}

hot_state: HOTRELOAD_STATE

gn_HotReload_Init :: proc() {
    hot_state.movement_proc = proc(dt: f32) {
        // Dummy initial proc; will be replaced on first load
    }
    hot_state.lib_handle = nil
    hot_state.last_mod_time = time.Time{}
    thread.create_and_start(gn_HotReload_Thread_Proc)
    
    // Initial dummy append to ECS systems
    append(&ecs_systems, hot_state.movement_proc) // Dynamic movement system
}

gn_HotReload_Thread_Proc :: proc() {
    DLL_PATH :: "systems.dll"
    TEMP_DLL_PATH :: "systems_temp.dll"  // Reusable temp name (deleted on unload)

    for {
        time.sleep(500 * time.Millisecond)  // Poll gently

        info, err := os.stat(DLL_PATH)
        if err != os.ERROR_NONE {
            fmt.eprintf("Stat %s failed: %v\n", DLL_PATH, err)
            continue
        }

        // Compare _nsec (i64, public in time.Time)
        if info.modification_time._nsec > hot_state.last_mod_time._nsec {
            hot_state.last_mod_time = info.modification_time  // Direct: both time.Time
            fmt.printf("Change detected in %s-hot-reloading!\n", DLL_PATH)

            // Save old proc BEFORE any changes
            old_proc := hot_state.movement_proc

            // Step 1: Lock and remove the current system to prevent calls during reload
            sync.mutex_lock(&ecs_mutex)
            for i := 0; i < len(ecs_systems); {
                if ecs_systems[i] == old_proc {
                    ordered_remove(&ecs_systems, i)
                    continue
                }
                i += 1
            }
            sync.mutex_unlock(&ecs_mutex)

            // Step 2: Now safe to save state and unload (system not in ECS)
            old_time: f32 = 0.0
            if hot_state.lib_handle != nil {
                save_addr, save_found := dynlib.symbol_address(hot_state.lib_handle, "gn_ECS_Movement_Save_State")
                if save_found {
                    save_proc := cast(proc "c" () -> f32) save_addr
                    old_time = save_proc()
                }
                dynlib.unload_library(hot_state.lib_handle)
                hot_state.lib_handle = nil

                // Delete old temp (now unlocked)
                del_err := os.remove(TEMP_DLL_PATH)
                if del_err != os.ERROR_NONE {
                    fmt.eprintf("Failed to delete old %s: %v\n", TEMP_DLL_PATH, del_err)
                    // Continue anyway; worst case, use a unique temp name next time
                }
            }

            // Step 3: Copy to temp
            copy_ok := gn_Utils_Copy_File(DLL_PATH, TEMP_DLL_PATH)
            if !copy_ok {
                fmt.eprintf("Failed to copy %s to %s\n", DLL_PATH, TEMP_DLL_PATH)
                // To recover, re-add old_proc if needed, but for now continue
                continue
            }

            // Step 4: Load new lib from temp
            new_lib, load_ok := dynlib.load_library(TEMP_DLL_PATH)
            if !load_ok {
                fmt.eprintf("Lib load failed!\n")
                continue
            }
            hot_state.lib_handle = new_lib

            proc_addr, proc_found := dynlib.symbol_address(hot_state.lib_handle, "gn_ECS_Movement_System")
            if !proc_found {
                fmt.eprintf("Movement proc not found!\n")
                continue
            }
            hot_state.movement_proc = cast(gn_ECS_System) proc_addr
            
            set_api_addr, set_api_found := dynlib.symbol_address(hot_state.lib_handle, "gn_ECS_Set_API")
            if set_api_found {
                set_api_proc := cast(proc "odin" (api: shared.ECS_API)) set_api_addr

                api: shared.ECS_API = {
                    query = gn_ECS_Query,
                    get_component = gn_ECS_Get_Component,
                }
                set_api_proc(api) // Pass pointers to DLL
            } 
            else {
                fmt.eprintf("Set API proc not found!\n")
            }

            // Step 5: Restore state
            load_addr, load_found := dynlib.symbol_address(hot_state.lib_handle, "gn_ECS_Movement_Load_State")
            if load_found {
                load_proc := cast(proc "c" (f32)) load_addr
                load_proc(old_time)
            }

            // Step 6: Lock and add the new system back
            sync.mutex_lock(&ecs_mutex)
            append(&ecs_systems, hot_state.movement_proc)
            sync.mutex_unlock(&ecs_mutex)

            fmt.printf("Hot-reload done: dynamic systems updated, state preserved!\n")
        }
    }
}   
   


