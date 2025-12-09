// types.odin
package gungnir_shared

import "core:slice"
import glfw "vendor:glfw"

// Shared types used by both the main executable and hot-reloaded DLLs

// Unique identifier for every entity in the ECS
ENTITY :: u64

// Base component (empty, used for struct embedding)
COMPONENT :: struct {}

// Position component 
POSITION_COMPONENT :: struct {
	using base: COMPONENT,
	phase: f32, // Internal timer 
	x, y, z: f32, // World position
}

// Rendering data for an entity (OpenGL-specific)
RENDER_COMPONENT :: struct {
	using base: COMPONENT,
	vao: u32,           // Vertex Array Object handle
	vertex_count: i32,  // Number of vertices to draw
}

// Public API that the main exe gives to DLLs to access the ECS
ECS_API :: struct {
	query: proc "odin" (T: typeid) -> [dynamic]ENTITY,
	get_component: proc "odin" (entity: ENTITY, T: typeid) -> rawptr,
}

// Simple window wrapper
Window :: struct {
	handle: glfw.WindowHandle,
	width, height: i32,
}

// Function pointers for saving/loading state during hot-reload
RENDER_STATE_SAVE_PROC :: proc "odin" () -> f32
RENDER_STATE_LOAD_PROC :: proc "odin" (state: f32)

// Proxy OpenGL function table – avoids DLLs loading their own OpenGL (prevents crashes on Windows)
RENDER_GL_API :: struct {
	CreateShader:       proc "c" (u32) -> u32,
	ShaderSource:       proc "c" (u32, i32, [^]cstring, [^]i32),
	CompileShader:      proc "c" (u32),
	GetShaderiv:        proc "c" (u32, u32, [^]i32),
	GetShaderInfoLog:   proc "c" (u32, i32, ^i32, [^]u8),
	DeleteShader:       proc "c" (u32),
	CreateProgram:      proc "c" () -> u32,
	AttachShader:       proc "c" (u32, u32),
	LinkProgram:        proc "c" (u32),
	GetProgramiv:       proc "c" (u32, u32, [^]i32),
	GetProgramInfoLog:  proc "c" (u32, i32, ^i32, [^]u8),
	DeleteProgram:      proc "c" (u32),
	GetUniformLocation: proc "c" (u32, cstring) -> i32,
	UseProgram:         proc "c" (u32),
	BindVertexArray:    proc "c" (u32),
	Uniform3f:          proc "c" (i32, f32, f32, f32),
	DrawArrays:         proc "c" (u32, i32, i32),
	GetError:           proc "c" () -> u32,
}

// Hardcoded OpenGL constants – avoids importing the real OpenGL DLL in hot-reloaded modules
GL_VERTEX_SHADER   :: 0x8B31
GL_FRAGMENT_SHADER :: 0x8B30
GL_COMPILE_STATUS  :: 0x8B81
GL_LINK_STATUS     :: 0x8B82
GL_INFO_LOG_LENGTH :: 0x8B84
GL_TRIANGLES       :: 0x0004
GL_NO_ERROR        :: 0x0000