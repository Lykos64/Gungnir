package gungnir

import "core:fmt"
import gl "vendor:OpenGL"
import "core:os"

gn_Utils_Check_gl_Error :: proc(error_context: string) {
    err := gl.GetError()
    for err != gl.NO_ERROR {
        fmt.eprintf("GL Error in %s: 0x%x\n", error_context, err)
        err = gl.GetError() // Drain all errors
    }
}

gn_Utils_Copy_File :: proc(src, dst: string) -> (ok: bool) {
    data, read_ok := os.read_entire_file(src)
    if !read_ok { return false }
    defer delete(data)
    write_ok := os.write_entire_file(dst, data)
    return write_ok
}