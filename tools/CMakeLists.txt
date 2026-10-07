cmake_minimum_required(VERSION 3.17)
project(lcf_editor_tools LANGUAGES CXX)

# Helper programs for development; not part of the Godot addon.

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LIBLCF_WITH_INI OFF CACHE BOOL "" FORCE)
set(LIBLCF_WITH_XML OFF CACHE BOOL "" FORCE)
set(LIBLCF_ENABLE_TOOLS OFF CACHE BOOL "" FORCE)
set(LIBLCF_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(LIBLCF_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(LIBLCF_UPDATE_MIMEDB OFF CACHE BOOL "" FORCE)
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../thirdparty/liblcf" liblcf EXCLUDE_FROM_ALL)

add_executable(make_demo_project make_demo_project.cpp)
target_link_libraries(make_demo_project PRIVATE lcf)
set_target_properties(make_demo_project PROPERTIES CXX_STANDARD 17 CXX_EXTENSIONS OFF)
