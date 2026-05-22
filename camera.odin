package main

import "vendor:wgpu"
Camera_2D :: struct {
    transform: Transform_2D,
    zoom:      [2]f32,
    size:      [2]f32,
}

make_camera :: proc(
    position: [2]f32,
    size: [2]f32 = {WINDOWS_WIDTH, WINDOWS_HEIGHT},
    rotation: f32 = 0,
    zoom: [2]f32 = {1, 1},
) -> (
    camera: Camera_2D,
) {
    camera = {
        transform = make_transform(position, rotation),
        zoom      = zoom,
        size      = size,
    }
    return
}


make_view_matrix :: proc(camera: Camera_2D) -> Mat3x3 {
    inv_t := make_translate_matrix(-camera.transform.position)
    inv_r := make_rotation_matrix(-camera.transform.rotation)
    zoom := camera.zoom == 0 ? 0.01 : camera.zoom
    inv_s := make_scale_matrix(zoom)

    return inv_t * inv_r * inv_s
}


make_ortho_matrix :: proc(c: Camera_2D) -> Mat3x3 {
    // aspect := w / h
    // half_w := w / 2
    // half_h := h / 2
    //
    // left := -half_w
    // right := half_w
    // top := half_h
    // bottom := -half_h

    // x' =  ((x - left)/(right - left)) * 2 - 1
    // y' =  ((y - top)/(top - bottom)) * 2 - 1

    // odinfmt: disable
    return {
        2 / c.size.x, 0             , 0,
        0           , -2 / c.size.y  , 0,
        0           , 0             , 1,
    }
    // odinfmt: enable
}


update_vm_to_buffer :: proc(queue: wgpu.Queue, buffer: wgpu.Buffer, c: Camera_2D) {
    trans := Transform_2DGPU {
        view       = to_mat4x3(make_view_matrix(c)),
        projection = to_mat4x3(make_ortho_matrix(c)),
    }
    wgpu.QueueWriteBuffer(queue, buffer, 0, &trans, size_of(trans))
}

