package main

import "core:mem"
import "vendor:wgpu"


GPU_Buffer :: struct {
    buffer:     wgpu.Buffer,
    size:       u64,
    align_size: u64,
}


create_buffer :: proc(
    device: wgpu.Device,
    size: u64,
    usage: wgpu.BufferUsageFlags,
    label: wgpu.StringView,
    is_map: b32 = false,
) -> (
    b: GPU_Buffer,
    ok: bool ,
) {
    align_size := u64(mem.align_forward_uint(uint(size), 4))
    b = {
        buffer     = wgpu.DeviceCreateBuffer(
            device,
            &{label = label, usage = usage, size = align_size, mappedAtCreation = is_map},
        ),
        size       = size,
        align_size = align_size,
    }

    if b.buffer == nil do return b, false


    return b, true
}

destroy_buffer :: proc(b: GPU_Buffer) {
    wgpu.BufferDestroy(b.buffer)
}

