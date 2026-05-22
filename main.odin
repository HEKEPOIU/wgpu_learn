package main

import "base:runtime"
import "core:log"
import "vendor:glfw"

main :: proc() {
    context.logger = log.create_console_logger()
    c := context

    log.ensuref(glfw.Init() == true, "Failed to initialize GLFW")
    defer glfw.Terminate()
    platform := glfw.GetPlatform()
    log.infof("GLFW platform: {}", platform)
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)
    glfw.WindowHint(glfw.FLOATING, glfw.TRUE)
    glfw.WindowHint(glfw.SCALE_TO_MONITOR, glfw.FALSE)
    glfw.WindowHint(glfw.DECORATED, glfw.FALSE)
    window := glfw.CreateWindow(WINDOWS_WIDTH, WINDOWS_HEIGHT, "Learn WebGPU", nil, nil)
    w,h := glfw.GetWindowSize(window)
    log.info("size of window: {} {}", w, h)
    glfw.SetWindowSize(window, WINDOWS_WIDTH, WINDOWS_HEIGHT)
    w,h = glfw.GetWindowSize(window)
    log.info("size of window: {} {}", w, h)
    log.ensure(window != nil, "Failed to create glfw window")
    defer glfw.DestroyWindow(window)

    graphics := create_graphic(window)
    defer release_graphic(graphics)
    is_left_click_down := false

    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents()

        left_click_state := glfw.GetMouseButton(window, glfw.MOUSE_BUTTON_LEFT)
        if left_click_state == glfw.PRESS && is_left_click_down == false {
            is_left_click_down = true
            x, y := glfw.GetCursorPos(window)
            log.infof("click: {}, {}", x, y)
            x_scale, y_scale := glfw.GetWindowContentScale(window)
            log.infof("scale: {}, {}", x_scale, y_scale)
            push_square(&graphics, {f32(x), f32(y)}, {20, 20})
        }
        if (left_click_state == glfw.RELEASE) && is_left_click_down {
            is_left_click_down = false
            log.info("Release")
        }

        draw_graphic(graphics, window)
    }
}

