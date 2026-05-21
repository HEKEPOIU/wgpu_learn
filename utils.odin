package main

import "base:runtime"
import "core:mem"
import "core:path/filepath"
import "core:strings"
import "core:sys/linux"

get_context :: #force_inline proc(p: rawptr) -> runtime.Context {
    return (^runtime.Context)(p)^
}

get_exe_dir :: proc(
    allocator := context.temp_allocator,
) -> (
    res: string,
    err: mem.Allocator_Error,
) {
    defer if allocator != context.temp_allocator {
        free_all(context.temp_allocator)
    }
    when ODIN_OS == .Windows {
        buf: [win.MAX_PATH]u16
        len := win.GetModuleFileNameW(nil, &buf[0], win.MAX_PATH)
        res = win.utf16_to_utf8_alloc(buf[:len], context.temp_allocator) or_return
        res = filepath.dir(res)
        return
    } else when ODIN_OS == .Linux {
        FILE_NAME_MAX :: 4096
        buf: [FILE_NAME_MAX]u8
        len, _ := linux.readlink("/proc/self/exe", buf[:])
        res = strings.clone_from(buf[:], context.temp_allocator) or_return
        res = filepath.dir(res)
        return
    } else {
        #panic("Not Implement for current platform")
    }
}


get_asset_path :: proc(
    asset: string,
    allocator := context.allocator,
) -> (
    res: string,
    err: mem.Allocator_Error,
) #optional_allocator_error {
    s := get_exe_dir() or_return
    defer if allocator != context.temp_allocator {
        free_all(context.temp_allocator)
    }
    paths := [3]string{s, ASSET_PATH, asset}
    res = filepath.join(paths[:], allocator) or_return
    return
}

