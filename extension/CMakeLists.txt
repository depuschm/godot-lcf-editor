cmake_minimum_required(VERSION 3.17)
project(lcf_editor LANGUAGES CXX)

# Builds the GDExtension that exposes liblcf to Godot.
# The library is written to addons/lcf_editor/bin/, where lcf_editor.gdextension expects it.

set(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
# One C runtime for all bundled libraries (matters for MSVC only).
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL" CACHE STRING "")

# Keep Godot from scanning the build folder when it lives inside the project.
file(WRITE "${CMAKE_BINARY_DIR}/.gdignore" "")

option(LCF_WITH_ICU "Use ICU for text encodings (needed for Japanese, Polish, ... projects)" ON)

# --- expat (static), so liblcf can read its XML format back ---
set(EXPAT_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(EXPAT_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(EXPAT_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(EXPAT_BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(EXPAT_BUILD_PKGCONFIG OFF CACHE BOOL "" FORCE)
set(EXPAT_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(EXPAT_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory("${REPO_ROOT}/thirdparty/libexpat/expat" expat EXCLUDE_FROM_ALL)
# liblcf looks for expat with find_package(expat CONFIG); point it at the target above.
file(WRITE "${CMAKE_BINARY_DIR}/expat-stub/expat-config.cmake" "# expat::expat is built in this project\n")
set(expat_DIR "${CMAKE_BINARY_DIR}/expat-stub" CACHE PATH "" FORCE)

# --- liblcf (static, only the parts the editor needs) ---
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LIBLCF_WITH_INI OFF CACHE BOOL "" FORCE)        # RPG_RT.ini is parsed in our own code
set(LIBLCF_WITH_XML ON CACHE BOOL "" FORCE)
set(LIBLCF_WITH_ICU ${LCF_WITH_ICU} CACHE BOOL "" FORCE)
set(LIBLCF_ENABLE_TOOLS OFF CACHE BOOL "" FORCE)
set(LIBLCF_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(LIBLCF_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(LIBLCF_UPDATE_MIMEDB OFF CACHE BOOL "" FORCE)
add_subdirectory("${REPO_ROOT}/thirdparty/liblcf" liblcf EXCLUDE_FROM_ALL)

# --- godot-cpp ---
set(GODOT_CPP_DIR "${REPO_ROOT}/thirdparty/godot-cpp" CACHE PATH "Path to godot-cpp")
add_subdirectory("${GODOT_CPP_DIR}" godot-cpp EXCLUDE_FROM_ALL)
get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)

# --- the extension ---
add_library(lcf_editor SHARED
    src/register_types.cpp
    src/lcf_project.cpp
    src/lcf_chipset.cpp
    src/database_sections.cpp
)
target_link_libraries(lcf_editor PRIVATE godot-cpp lcf)

set(OUTPUT_DIR "${REPO_ROOT}/addons/lcf_editor/bin")
set_target_properties(lcf_editor PROPERTIES
    CXX_STANDARD 17
    CXX_EXTENSIONS OFF
    CXX_VISIBILITY_PRESET hidden
    BUILD_RPATH_USE_ORIGIN ON
    PREFIX "lib"
    OUTPUT_NAME "lcf_editor${GODOTCPP_SUFFIX}"
    LIBRARY_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    RUNTIME_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
)
if(CMAKE_SYSTEM_NAME STREQUAL Darwin)
    set_target_properties(lcf_editor PROPERTIES SUFFIX ".dylib")
endif()
