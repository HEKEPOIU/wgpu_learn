package main
import "core:log"
import "core:mem"
import "vendor:glfw"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"


Color :: [4]f32
Vertex_2d :: struct {
    position: [2]f32,
    // vertex_color: Color,
}

Drawable_2d :: struct {
    index_buffer:         wgpu.Buffer,
    index_buffer_size:    u64,
    vertices_buffer:      wgpu.Buffer,
    vertices_buffer_size: u64,
    transform_buffer:     wgpu.Buffer,
    transform_group:      wgpu.BindGroup,
    global_transform:     Transform_2D,
    vertices:             []Vertex_2d,
    index:                [][3]u32,
}


Graphics :: struct {
    instance:       wgpu.Instance,
    surface:        wgpu.Surface,
    surface_format: wgpu.TextureFormat,
    device:         wgpu.Device,
    queue:          wgpu.Queue,
    state_2d:       Render_State_2d,
}

Render_State_2d :: struct {
    pipeline_2d:       wgpu.RenderPipeline,
    camera:            Camera_2D,
    bind_group_layout: wgpu.BindGroupLayout,
    drawable:          [dynamic]Drawable_2d,
}

Transform_2DGPU :: struct {
    model:      Mat4x3,
    view:       Mat4x3,
    projection: Mat4x3,
}

create_render_pipeline_2d :: proc(g: ^Graphics) {
    shader, err := load_shader_from_file(g.device, "shader_2d.spv")
    log.ensuref(err == nil, "Failed to load shader: {}", err)
    color_target_state := wgpu.ColorTargetState {
        format    = g.surface_format,
        blend     = &{
            color = {srcFactor = .SrcAlpha, dstFactor = .OneMinusSrcAlpha, operation = .Add},
            alpha = {srcFactor = .Zero, dstFactor = .One, operation = .Add},
        },
        writeMask = wgpu.ColorWriteMaskFlags_All,
    }

    vertex_attribute := []wgpu.VertexAttribute {
        {format = .Float32x2, offset = 0, shaderLocation = 0},
    }
    vertex_buffer_layout := wgpu.VertexBufferLayout {
        arrayStride    = u64(size_of(Vertex_2d)),
        stepMode       = .Vertex,
        attributeCount = uint(len(vertex_attribute)),
        attributes     = raw_data(vertex_attribute),
    }

    g.state_2d.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
        g.device,
        &{
            label = "Transform bind_group layout",
            entryCount = 1,
            entries = &wgpu.BindGroupLayoutEntry {
                binding = 0,
                visibility = {.Vertex},
                bindingArraySize = 0,
                buffer = {
                    type = .Uniform,
                    hasDynamicOffset = false,
                    minBindingSize = size_of(Transform_2DGPU),
                },
            },
        },
    )

    pipeline_layout := wgpu.DeviceCreatePipelineLayout(
        g.device,
        &{
            label = "2d pipeline layout",
            bindGroupLayoutCount = 1,
            bindGroupLayouts = &g.state_2d.bind_group_layout,
            immediateSize = 0,
        },
    )

    g.state_2d.pipeline_2d = wgpu.DeviceCreateRenderPipeline(
        g.device,
        &{
            label = "Render 2d Pipeline",
            layout = pipeline_layout,
            vertex = {
                module = shader,
                entryPoint = "vs_main",
                bufferCount = 1,
                buffers = &vertex_buffer_layout,
            },
            primitive = {
                topology = .TriangleList,
                stripIndexFormat = .Undefined,
                frontFace = .CCW,
                cullMode = .Back,
            },
            fragment = &{
                module = shader,
                entryPoint = "fs_main",
                targetCount = 1,
                targets = &color_target_state,
            },
            multisample = {count = 1, mask = ~u32(0), alphaToCoverageEnabled = false},
        },
    )
    wgpu.PipelineLayoutRelease(pipeline_layout)
    wgpu.ShaderModuleRelease(shader)
}

push_square :: proc(
    g: ^Graphics,
    position: [2]f32,
    size: [2]f32,
    rotation: f32 = 0,
    color: Color = {1, 1, 1, 1},
) {
    log.assert(size.x > 0 && size.y > 0, "not allow negative size")
    hs := size / 2
    square := Drawable_2d {
        global_transform = make_transform(position, rotation),
        vertices         = {
            {position = {-hs.x, hs.y}},
            {position = {-hs.x, -hs.y}},
            {position = {hs.x, -hs.y}},
            {position = {hs.x, hs.y}},
        },
        index            = {{0, 1, 2}, {0, 2, 3}},
    }
    vertex_buffer_size := uint(len(square.vertices) * size_of(Vertex_2d))
    index_buffer_size := uint(size_of(square.index[0]) * len(square.index))
    align_vertex_buffer_size := u64(mem.align_forward_uint(vertex_buffer_size, 4))
    align_index_buffer_size := u64(mem.align_forward_uint(index_buffer_size, 4))
    upload_buffer_size := u64(align_index_buffer_size + align_vertex_buffer_size)
    square.vertices_buffer_size = align_vertex_buffer_size
    square.index_buffer_size = align_index_buffer_size

    upload_buffer := wgpu.DeviceCreateBuffer(
        g.device,
        &{
            label = "upload buffer",
            usage = {.CopySrc, .MapWrite},
            mappedAtCreation = true,
            size = upload_buffer_size,
        },
    )
    log.ensuref(
        upload_buffer != nil,
        "Create Upload_buffer failed, buffer size: {}",
        upload_buffer_size,
    )

    {
        begin := wgpu.BufferGetMappedRange(upload_buffer, 0, uint(upload_buffer_size))
        offset := mem.ptr_offset(raw_data(begin), align_vertex_buffer_size)
        mem.copy(raw_data(begin), raw_data(square.vertices), int(vertex_buffer_size))
        mem.copy(offset, raw_data(square.index), int(index_buffer_size))
        wgpu.BufferUnmap(upload_buffer)
    }

    // create vertex buffer, index buffer.
    vertex_buffer := wgpu.DeviceCreateBuffer(
        g.device,
        &{
            label = "square vertex buffer",
            usage = {.CopyDst, .Vertex},
            size = align_vertex_buffer_size,
            mappedAtCreation = false,
        },
    )
    log.ensure(vertex_buffer != nil, "failed to create vertex_buffer")
    index_buffer := wgpu.DeviceCreateBuffer(
        g.device,
        &{
            label = "square index buffer",
            usage = {.CopyDst, .Index},
            size = align_index_buffer_size,
            mappedAtCreation = false,
        },
    )
    log.ensure(index_buffer != nil, "failed to create vertex_buffer")
    encoder := wgpu.DeviceCreateCommandEncoder(g.device, &{label = "upload encoder"})
    wgpu.CommandEncoderCopyBufferToBuffer(
        encoder,
        upload_buffer,
        0,
        vertex_buffer,
        0,
        align_vertex_buffer_size,
    )
    wgpu.CommandEncoderCopyBufferToBuffer(
        encoder,
        upload_buffer,
        align_vertex_buffer_size,
        index_buffer,
        0,
        align_index_buffer_size,
    )
    upload_command_buffer := wgpu.CommandEncoderFinish(encoder, &{})
    wgpu.CommandEncoderRelease(encoder)
    wgpu.QueueSubmit(g.queue, {upload_command_buffer})

    wgpu.DevicePoll(g.device, true)
    square.index_buffer = index_buffer
    square.vertices_buffer = vertex_buffer

    wgpu.BufferDestroy(upload_buffer)

    // Create BindGroup

    square.transform_buffer = wgpu.DeviceCreateBuffer(
        g.device,
        &{
            label = "square transform buffer",
            usage = {.CopyDst, .Uniform},
            mappedAtCreation = false,
            size = size_of(Transform_2DGPU),
        },
    )
    log.ensuref(square.transform_buffer != nil, "Failed to create transform buffer")

    trans := Transform_2DGPU {
        model      = to_mat4x3(make_matrix(square.global_transform)),
        view       = to_mat4x3(make_view_matrix(g.state_2d.camera)),
        projection = to_mat4x3(make_ortho_matrix(WINDOWS_WIDTH, WINDOWS_HEIGHT)),
    }
    wgpu.QueueWriteBuffer(g.queue, square.transform_buffer, 0, &trans, size_of(Transform_2DGPU))

    bind_group_entry := wgpu.BindGroupEntry {
        binding = 0,
        buffer  = square.transform_buffer,
        offset  = 0,
        size    = size_of(Transform_2DGPU),
    }

    square.transform_group = wgpu.DeviceCreateBindGroup(
        g.device,
        &{
            label = "Transform bindgroup",
            entryCount = 1,
            entries = &bind_group_entry,
            layout = g.state_2d.bind_group_layout,
        },
    )


    append(&g.state_2d.drawable, square)
}

create_graphic :: proc(window: glfw.WindowHandle) -> (g: Graphics) {
    c := context
    g.instance = wgpu.CreateInstance(&{})
    ensure(g.instance != nil)

    g.surface = glfwglue.GetSurface(g.instance, window)
    adapter := request_adapter_sync(g.instance, &{compatibleSurface = g.surface})
    log_adapter_info(adapter)


    g.device = request_device_sync(
        adapter,
        &{
            label = "Learn WGPU Device",
            defaultQueue = {label = "Learn WGPU Default Queue"},
            deviceLostCallbackInfo = {
                callback = proc "c" (
                    device: ^wgpu.Device,
                    reason: wgpu.DeviceLostReason,
                    message: wgpu.StringView,
                    userdata1: rawptr,
                    userdata2: rawptr,
                ) {
                    context = get_context(userdata2)
                    log.info(
                        "The device {} lost, reason: {}, message: {}",
                        device,
                        reason,
                        message,
                    )
                },
                userdata2 = &c,
            },
            uncapturedErrorCallbackInfo = {
                callback = proc "c" (
                    device: ^wgpu.Device,
                    type: wgpu.ErrorType,
                    message: wgpu.StringView,
                    userdata1: rawptr,
                    userdata2: rawptr,
                ) {
                    context = get_context(userdata2)
                    log.warnf("uncaptured error,type: {}, message {}", type, message)
                },
                userdata2 = &c,
            },
        },
    )

    f, w := wgpu.SurfaceGetCapabilities(g.surface, adapter)
    log.ensuref(w == .Success, "Failed to get surface capabilities")
    g.surface_format = f.formats[0]
    wgpu.SurfaceConfigure(
        g.surface,
        &{
            width = WINDOWS_WIDTH,
            height = WINDOWS_HEIGHT,
            format = g.surface_format,
            usage = {.RenderAttachment},
            device = g.device,
            presentMode = .Fifo,
            alphaMode = .Auto,
        },
    )
    log_device_info(g.device)


    wgpu.AdapterRelease(adapter)
    g.queue = wgpu.DeviceGetQueue(g.device)
    create_render_pipeline_2d(&g)
    g.state_2d.camera = make_camera({WINDOWS_WIDTH / 2, WINDOWS_HEIGHT / 2}, zoom = {1, 1})
    push_square(&g, {WINDOWS_WIDTH / 2, WINDOWS_HEIGHT / 2}, {300, 300})
    return
}

release_graphic :: proc(g: Graphics) {
    wgpu.BindGroupLayoutRelease(g.state_2d.bind_group_layout)
    for d in g.state_2d.drawable {
        wgpu.BufferRelease(d.index_buffer)
        wgpu.BufferRelease(d.vertices_buffer)
        wgpu.BufferRelease(d.transform_buffer)
        wgpu.BindGroupRelease(d.transform_group)
    }
    delete(g.state_2d.drawable)
    wgpu.RenderPipelineRelease(g.state_2d.pipeline_2d)
    wgpu.DeviceRelease(g.device)
    wgpu.SurfaceUnconfigure(g.surface)
    wgpu.SurfaceRelease(g.surface)
    wgpu.InstanceRelease(g.instance)
}

draw_graphic :: proc(g: Graphics) {
    surface_texture, texture_view := get_next_surfaceview_data(g.surface)
    if texture_view == nil do return
    defer wgpu.TextureRelease(surface_texture.texture)
    defer wgpu.TextureViewRelease(texture_view)

    encoder := wgpu.DeviceCreateCommandEncoder(g.device, &{label = "Learn Command Encoder"})
    render_pass_color_attachment := wgpu.RenderPassColorAttachment {
        view       = texture_view,
        loadOp     = .Clear,
        storeOp    = .Store,
        clearValue = {0.9, 0.1, 0.2, 1.0},
        depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
    }
    render_pass := wgpu.CommandEncoderBeginRenderPass(
        encoder,
        &{colorAttachmentCount = 1, colorAttachments = &render_pass_color_attachment},
    )
    wgpu.RenderPassEncoderSetPipeline(render_pass, g.state_2d.pipeline_2d)

    wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, g.state_2d.drawable[0].transform_group, {})

    wgpu.RenderPassEncoderSetVertexBuffer(
        render_pass,
        0,
        g.state_2d.drawable[0].vertices_buffer,
        0,
        g.state_2d.drawable[0].vertices_buffer_size,
    )

    wgpu.RenderPassEncoderSetIndexBuffer(
        render_pass,
        g.state_2d.drawable[0].index_buffer,
        .Uint32,
        0,
        g.state_2d.drawable[0].index_buffer_size,
    )

    wgpu.RenderPassEncoderDrawIndexed(render_pass, 6, 1, 0, 0, 0)

    wgpu.RenderPassEncoderEnd(render_pass)
    wgpu.RenderPassEncoderRelease(render_pass)

    command := wgpu.CommandEncoderFinish(encoder)
    wgpu.CommandEncoderRelease(encoder)

    wgpu.QueueSubmit(g.queue, {command})
    wgpu.CommandBufferRelease(command)
    wgpu.SurfacePresent(g.surface)
}

