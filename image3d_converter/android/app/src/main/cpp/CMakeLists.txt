cmake_minimum_required(VERSION 3.14)

add_library(
    native_mesh
    SHARED
    native_mesh.cpp
)

find_library(
    log-lib
    log
)

target_link_libraries(
    native_mesh
    ${log-lib}
)