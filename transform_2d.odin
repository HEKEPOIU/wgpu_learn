package main

import "core:math"

Mat3x3 :: matrix[3, 3]f32
Mat4x3 :: matrix[4, 3]f32

Transform_2D :: struct {
    position: [2]f32,
    rotation: f32, /* Radian*/
    scale:    [2]f32,
}
GpuMat3x3 :: struct {
    col0: [3]f32, pad0: f32,
    col1: [3]f32, pad1: f32,
    col2: [3]f32, pad2: f32,
}


to_mat4x3 :: proc(m: Mat3x3) -> Mat4x3 {
    // odinfmt: disable
    return {
        m[0,0], m[0,1]  , m[0,2],
        m[1,0], m[1,1]  , m[1,2],
        m[2,0], m[2,1]  , m[2,2],
        0     , 0       , 0     ,
    }
    // odinfmt: enable
}

make_transform :: proc(
    position: [2]f32,
    rotation: f32 = 0,
    scale: [2]f32 = {1, 1},
) -> (
    trans: Transform_2D,
) {
    trans = {
        position = position,
        rotation = rotation,
        scale = scale,
    }
    return 
}


make_matrix :: proc(trans: Transform_2D) -> Mat3x3 {
    return(
        make_translate_matrix(trans.position) *
        make_rotation_matrix(trans.rotation) *
        make_scale_matrix(trans.scale) \
    )
}

make_translate_matrix :: #force_inline proc(pos: [2]f32) -> Mat3x3 {
    // odinfmt: disable
    return {
        1, 0, pos.x,
        0, 1, pos.y,
        0, 0,     1, 
    } 
    // odinfmt: enable
}

make_rotation_matrix :: #force_inline proc(rotation: f32) -> Mat3x3 {
    cos := math.cos(-rotation)
    sin := math.sin(-rotation)
    // odinfmt: disable
    return {
        cos , sin   , 0,
        -sin, cos   , 0,
        0   , 0     , 1,
    }
    // odinfmt: enable
}

make_scale_matrix :: #force_inline proc(scale: [2]f32) -> Mat3x3 {
    // odinfmt: disable
    return {
        scale.x , 0         , 0,
        0       , scale.y   , 0,
        0       , 0         , 1,
    }
    // odinfmt: enable
}

