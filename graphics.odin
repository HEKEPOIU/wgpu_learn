package main
import "core:log"
import "core:mem"
import "vendor:glfw"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"


MAX_2D_OBJECT :: 100

Color :: [4]f32
Vertex_2d :: struct {
    position: [2]f32,
    color:    Color,
}


Drawable_2d :: struct {
    index_buffer:     GPU_Buffer,
    vertices_buffer:  GPU_Buffer,
    global_transform: Transform_2D,
    vertices:         []Vertex_2d,
    index:            [][3]u32,
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
    pipeline_2d:         wgpu.RenderPipeline,
    global_buffer:       wgpu.Buffer,
    global_group_layout: wgpu.BindGroupLayout,
    global_group:        wgpu.BindGroup,
    models_buffer:       wgpu.Buffer,
    models_group:        wgpu.BindGroup,
    models_layout:       wgpu.BindGroupLayout,
    camera:              Camera_2D,
    drawable:            [dynamic]Drawable_2d,
}

Transform_2DGPU :: struct {
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
        {format = .Float32x4, offset = u64(offset_of(Vertex_2d, color)), shaderLocation = 1},
    }
    vertex_buffer_layout := wgpu.VertexBufferLayout {
        arrayStride    = u64(size_of(Vertex_2d)),
        stepMode       = .Vertex,
        attributeCount = uint(len(vertex_attribute)),
        attributes     = raw_data(vertex_attribute),
    }
    vp_group_layout_entries := []wgpu.BindGroupLayoutEntry {
        {
            binding = 0,
            visibility = {.Vertex},
            bindingArraySize = 0,
            buffer = {
                type = .Uniform,
                hasDynamicOffset = false,
                minBindingSize = size_of(Transform_2DGPU),
            },
        },
    }

    model_group_layout_entries := []wgpu.BindGroupLayoutEntry {
        {
            binding = 0,
            visibility = {.Vertex},
            bindingArraySize = 0,
            buffer = {
                type = .ReadOnlyStorage,
                hasDynamicOffset = false,
                minBindingSize = size_of(Mat4x3),
            },
        },
    }

    g.state_2d.global_group_layout = wgpu.DeviceCreateBindGroupLayout(
        g.device,
        &{
            label = "Transform bind_group layout",
            entryCount = len(vp_group_layout_entries),
            entries = raw_data(vp_group_layout_entries),
        },
    )

    g.state_2d.models_layout = wgpu.DeviceCreateBindGroupLayout(
        g.device,
        &{
            label = "Transform bind_group layout",
            entryCount = len(model_group_layout_entries),
            entries = raw_data(model_group_layout_entries),
        },
    )

    layouts := []wgpu.BindGroupLayout{g.state_2d.global_group_layout, g.state_2d.models_layout}

    pipeline_layout := wgpu.DeviceCreatePipelineLayout(
        g.device,
        &{
            label = "2d pipeline layout",
            bindGroupLayoutCount = len(layouts),
            bindGroupLayouts = raw_data(layouts),
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
            {position = {-hs.x, -hs.y}, color = color},
            {position = {-hs.x, hs.y}, color = color},
            {position = {hs.x, hs.y}, color = color},
            {position = {hs.x, -hs.y}, color = color},
        },
        index            = {{0, 1, 2}, {0, 2, 3}},
    }
    {
        vertex_buffer_size := len(square.vertices) * size_of(Vertex_2d)
        vb, ok := create_buffer(
            g.device,
            u64(vertex_buffer_size),
            {.Vertex, .CopyDst},
            "square vertex buffer",
        )
        log.ensure(ok, "failed to create vertex buffer")
        square.vertices_buffer = vb
    }

    {
        index_buffer_size := size_of(square.index[0]) * len(square.index)
        ib, ok := create_buffer(
            g.device,
            u64(index_buffer_size),
            {.Index, .CopyDst},
            "square index buffer",
        )
        log.ensure(ok, "failed to create index buffer")
        square.index_buffer = ib
    }

    upload_buffer: GPU_Buffer
    {
        upload_buffer_size := square.index_buffer.align_size + square.vertices_buffer.align_size
        ub, ok := create_buffer(
            g.device,
            upload_buffer_size,
            {.CopySrc, .MapWrite},
            "upload buffer",
            true,
        )
        log.ensure(ok, "failed to create upload_buffer")
        upload_buffer = ub
    }

    {
        begin := wgpu.BufferGetMappedRange(upload_buffer.buffer, 0, uint(upload_buffer.align_size))
        offset := mem.ptr_offset(raw_data(begin), square.vertices_buffer.align_size)
        mem.copy(raw_data(begin), raw_data(square.vertices), int(square.vertices_buffer.size))
        mem.copy(offset, raw_data(square.index), int(square.index_buffer.size))
        wgpu.BufferUnmap(upload_buffer.buffer)
    }

    // create vertex buffer, index buffer.
    encoder := wgpu.DeviceCreateCommandEncoder(g.device, &{label = "upload encoder"})
    wgpu.CommandEncoderCopyBufferToBuffer(
        encoder,
        upload_buffer.buffer,
        0,
        square.vertices_buffer.buffer,
        0,
        square.vertices_buffer.align_size,
    )
    wgpu.CommandEncoderCopyBufferToBuffer(
        encoder,
        upload_buffer.buffer,
        square.vertices_buffer.align_size,
        square.index_buffer.buffer,
        0,
        square.index_buffer.align_size,
    )
    upload_command_buffer := wgpu.CommandEncoderFinish(encoder, &{})
    wgpu.CommandEncoderRelease(encoder)
    wgpu.QueueSubmit(g.queue, {upload_command_buffer})

    wgpu.DevicePoll(g.device, true)
    wgpu.CommandBufferRelease(upload_command_buffer)

    destroy_buffer(upload_buffer)
    append(&g.state_2d.drawable, square)
}

create_graphic :: proc(window: glfw.WindowHandle) -> (g: Graphics) {
    c := context
    g.instance = wgpu.CreateInstance(&{})
    ensure(g.instance != nil)

    g.surface = glfwglue.GetSurface(g.instance, window)
    adapter := request_adapter_sync(g.instance, &{compatibleSurface = g.surface})
    log_adapter_info(adapter)


    request_feature := []wgpu.FeatureName{}
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
            requiredFeatureCount = len(request_feature),
            requiredFeatures = raw_data(request_feature),
        },
    )

    {
        f, w := wgpu.SurfaceGetCapabilities(g.surface, adapter)
        log.ensuref(w == .Success, "Failed to get surface capabilities")
        g.surface_format = f.formats[0]
    }
    w, h := glfw.GetFramebufferSize(window)
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

    g.state_2d.global_buffer = wgpu.DeviceCreateBuffer(
        g.device,
        &{
            label = "global buffer",
            usage = {.Uniform, .CopyDst},
            size = size_of(Transform_2DGPU),
            mappedAtCreation = false,
        },
    )
    log.ensure(g.state_2d.global_buffer != nil, "failed to create global buffer")

    g.state_2d.global_group = wgpu.DeviceCreateBindGroup(
        g.device,
        &{
            label = "global bind group",
            layout = g.state_2d.global_group_layout,
            entryCount = 1,
            entries = &wgpu.BindGroupEntry {
                binding = 0,
                buffer = g.state_2d.global_buffer,
                offset = 0,
                size = size_of(Transform_2DGPU),
            },
        },
    )
    log.ensure(g.state_2d.global_group != nil, "failed to create global group")


    g.state_2d.models_buffer = wgpu.DeviceCreateBuffer(
        g.device,
        &{
            label = "models matrix buffer",
            usage = {.Storage, .CopyDst},
            size = MAX_2D_OBJECT * size_of(Mat4x3),
            mappedAtCreation = false,
        },
    )
    log.ensure(g.state_2d.models_buffer != nil, "failed to create models buffer")

    g.state_2d.models_group = wgpu.DeviceCreateBindGroup(
        g.device,
        &{
            label = "models bind group",
            layout = g.state_2d.models_layout,
            entryCount = 1,
            entries = &wgpu.BindGroupEntry {
                binding = 0,
                buffer = g.state_2d.models_buffer,
                offset = 0,
                size = size_of(Mat4x3) * MAX_2D_OBJECT,
            },
        },
    )
    log.ensure(g.state_2d.models_group != nil, "failed to create models group")


    wgpu.DevicePoll(g.device, true)


    return
}

release_graphic :: proc(g: Graphics) {
    wgpu.BindGroupLayoutRelease(g.state_2d.models_layout)
    wgpu.BindGroupLayoutRelease(g.state_2d.global_group_layout)
    wgpu.BindGroupRelease(g.state_2d.models_group)
    wgpu.BindGroupRelease(g.state_2d.global_group)
    wgpu.BufferRelease(g.state_2d.global_buffer)
    wgpu.BufferRelease(g.state_2d.models_buffer)
    for d in g.state_2d.drawable {
        destroy_buffer(d.index_buffer)
        destroy_buffer(d.vertices_buffer)
    }
    delete(g.state_2d.drawable)
    wgpu.RenderPipelineRelease(g.state_2d.pipeline_2d)
    wgpu.DeviceRelease(g.device)
    wgpu.SurfaceUnconfigure(g.surface)
    wgpu.SurfaceRelease(g.surface)
    wgpu.InstanceRelease(g.instance)
}

update_object_2d_uniform :: proc(g: Graphics) {
    models_mats := [dynamic; MAX_2D_OBJECT]Mat4x3{}
    for d in g.state_2d.drawable {
        append(&models_mats, to_mat4x3(make_matrix(d.global_transform)))
    }

    if len(models_mats) == 0 do return
    wgpu.QueueWriteBuffer(
        g.queue,
        g.state_2d.models_buffer,
        0,
        raw_data(models_mats[:]),
        len(models_mats) * size_of(Mat4x3),
    )
}

draw_graphic :: proc(g: Graphics, window: glfw.WindowHandle) {
    surface_texture, texture_view, state := get_next_surfaceview_data(g.surface)
    if state == .Outdated {
        w, h := glfw.GetFramebufferSize(window)
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
        return
    }
    if texture_view == nil do return
    defer wgpu.TextureRelease(surface_texture.texture)
    defer wgpu.TextureViewRelease(texture_view)

    update_vm_to_buffer(g.queue, g.state_2d.global_buffer, g.state_2d.camera)
    update_object_2d_uniform(g)

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
    // binding global states.
    wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, g.state_2d.global_group, {})

    for d, i in g.state_2d.drawable {
        wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, g.state_2d.models_group)
        wgpu.RenderPassEncoderSetVertexBuffer(
            render_pass,
            0,
            d.vertices_buffer.buffer,
            0,
            d.vertices_buffer.align_size,
        )

        wgpu.RenderPassEncoderSetIndexBuffer(
            render_pass,
            d.index_buffer.buffer,
            .Uint32,
            0,
            d.index_buffer.align_size,
        )

        wgpu.RenderPassEncoderDrawIndexed(render_pass, u32(len(d.index) * 3), 1, 0, 0, u32(i))
    }
    wgpu.RenderPassEncoderEnd(render_pass)

    command := wgpu.CommandEncoderFinish(encoder)
    wgpu.RenderPassEncoderRelease(render_pass)
    wgpu.CommandEncoderRelease(encoder)

    wgpu.QueueSubmit(g.queue, {command})
    wgpu.SurfacePresent(g.surface)
    wgpu.CommandBufferRelease(command)
}

