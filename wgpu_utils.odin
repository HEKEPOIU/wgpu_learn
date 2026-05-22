package main

import "base:runtime"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "vendor:wgpu"

get_next_surfaceview_data :: proc(s: wgpu.Surface) -> (wgpu.SurfaceTexture, wgpu.TextureView, wgpu.SurfaceGetCurrentTextureStatus) {
    st := wgpu.SurfaceGetCurrentTexture(s)
    if st.status == .SuccessSuboptimal {
        log.info("underline surface change.")
    } else if st.status != .SuccessOptimal {
        log.infof("status: {}", st.status)
        return st, nil, st.status
    }
    texture_view := wgpu.TextureCreateView(
        st.texture,
        &{
            label = "Surface Texture View",
            format = wgpu.TextureGetFormat(st.texture),
            dimension = ._2D,
            baseMipLevel = 0,
            mipLevelCount = 1,
            baseArrayLayer = 0,
            arrayLayerCount = 1,
            aspect = .All,
        },
    )
    return st, texture_view, st.status
}

request_adapter_sync :: proc(
    instance: wgpu.Instance,
    options: ^wgpu.RequestAdapterOptions,
) -> wgpu.Adapter {
    User_Data :: struct {
        adapter:       wgpu.Adapter,
        request_ended: bool,
    }
    data: User_Data
    c := context

    wgpu.InstanceRequestAdapter(instance, options, {
        callback = proc "c" (
            status: wgpu.RequestAdapterStatus,
            adapter: wgpu.Adapter,
            message: wgpu.StringView,
            userdata1: rawptr,
            userdata2: rawptr,
        ) {
            context = get_context(userdata2)
            user_data := (^User_Data)(userdata1)
            log.ensuref(status == .Success, "Cant get adapter: {}", message)
            user_data.adapter = adapter
            user_data.request_ended = true
        },
        userdata1 = rawptr(&data),
        userdata2 = &c,
    })

    when ODIN_OS == .JS {
        // Need to wait on web, but I don't care web.
        panic("handle await")
    }

    assert(data.request_ended)
    return data.adapter
}

request_device_sync :: proc(a: wgpu.Adapter, device_desc: ^wgpu.DeviceDescriptor) -> wgpu.Device {
    User_Data :: struct {
        device:        wgpu.Device,
        request_ended: bool,
    }
    c := context
    data: User_Data
    wgpu.AdapterRequestDevice(a, device_desc, {
        callback = proc "c" (
            status: wgpu.RequestDeviceStatus,
            device: wgpu.Device,
            message: wgpu.StringView,
            userdata1: rawptr,
            userdata2: rawptr,
        ) {
            context = get_context(userdata2)
            log.ensuref(status == .Success, "Request Device Not Success: {}", message)
            ud := (^User_Data)(userdata1)
            ud.device = device
            ud.request_ended = true
        },
        userdata1 = rawptr(&data),
        userdata2 = &c,
    })

    when ODIN_OS == .JS {
        // Need to wait on web, but I don't care web.
        panic("handle await")
    }

    assert(data.request_ended)

    return data.device
}

log_adapter_info :: proc(a: wgpu.Adapter) {
    assert(a != nil)

    // res, _ := wgpu.AdapterGetLimits(a)
    // log.info(res)
    res, _ := wgpu.AdapterGetInfo(a)

    log.infof("vendor: {} (id:{})", res.vendor, res.vendorID)
    log.infof("architecture: {}", res.architecture)
    log.infof("device: {} (id:{})", res.device, res.deviceID)
    log.infof("desc: {}", res.description) 
    log.info(res.backendType)
    log.info(res.adapterType)
}

log_device_info :: proc(d: wgpu.Device) {
    assert(d != nil)
    support_feature := wgpu.DeviceGetFeatures(d)
    log.info(support_feature)

    // limits, _ := wgpu.DeviceGetLimits(d)
    // log.info(limits.minUniformBufferOffsetAlignment)
}


load_shader_from_file :: proc(
    device: wgpu.Device,
    path: string,
) -> (
    shader: wgpu.ShaderModule,
    err: os.Error,
) {
    ext := filepath.ext(path)
    if ext != ".wgsl" && ext != ".spv" do return nil, os.General_Error.Invalid_File

    defer free_all(context.temp_allocator)
    shader_path := get_asset_path(path, context.temp_allocator) or_return
    data := os.read_entire_file(shader_path, context.temp_allocator) or_return
    switch ext {
    case ".wgsl":
        desc := wgpu.ShaderSourceWGSL {
            sType = .ShaderSourceWGSL,
            code  = string(data),
        }

        shader = wgpu.DeviceCreateShaderModule(device, &{nextInChain = &desc})
    case ".spv":
        // spv spc.
        if (len(data) % 4 != 0) do return nil, os.General_Error.Invalid_File
        u32_count := len(data) / 4
        u32_data := make([]u32, u32_count, context.temp_allocator)

        mem.copy(raw_data(u32_data), raw_data(data), len(data))
        desc := wgpu.ShaderSourceSPIRV {
            sType    = .ShaderSourceSPIRV,
            code     = raw_data(u32_data),
            codeSize = u32(u32_count),
        }

        shader = wgpu.DeviceCreateShaderModule(device, &{nextInChain = &desc})
    }

    return
}

