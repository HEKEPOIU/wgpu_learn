#!/usr/bin/env bash
source "var.sh"

slangc "$ASSETS_PATH/shader_2d.slang" -target spirv -entry vs_main -stage vertex -entry fs_main -stage fragment -o "$ASSETS_PATH/shader_2d.spv"

mkdir -p "$BUILD_PATH/$ASSETS_PATH"
mv "$ASSETS_PATH"/*.spv "$BUILD_PATH/$ASSETS_PATH"

odin build . -define:WGPU_DEBUG=true -out:"$BUILD_PATH/wgpu_learn" -debug -vet-shadowing -vet-semicolon -show-more-timings -linker:mold
