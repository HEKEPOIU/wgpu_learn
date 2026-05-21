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
    window := glfw.CreateWindow(WINDOWS_WIDTH, WINDOWS_HEIGHT, "Learn WebGPU", nil, nil)
    log.ensure(window != nil, "Failed to create glfw window")
    defer glfw.DestroyWindow(window)

    graphics := create_graphic(window)
    defer release_graphic(graphics)

    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents()
        draw_graphic(graphics)
    }
}

