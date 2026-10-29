cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "browser_channel.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Pinned native WebView2 SDK; restore in the build tree, never vendor binaries.
find_program(NUGET nuget REQUIRED)
set(WEBVIEW2_VERSION "1.0.2903.40")
set(WEBVIEW2_ROOT "${CMAKE_CURRENT_BINARY_DIR}/packages/Microsoft.Web.WebView2.${WEBVIEW2_VERSION}")
if(NOT EXISTS "${WEBVIEW2_ROOT}/build/native/include/WebView2.h")
  execute_process(COMMAND ${NUGET} install Microsoft.Web.WebView2 -Version ${WEBVIEW2_VERSION}
    -OutputDirectory "${CMAKE_CURRENT_BINARY_DIR}/packages" -NonInteractive
    RESULT_VARIABLE WEBVIEW2_RESTORE)
  if(NOT WEBVIEW2_RESTORE EQUAL 0)
    message(FATAL_ERROR "WebView2 SDK restore failed")
  endif()
endif()
target_include_directories(${BINARY_NAME} PRIVATE "${WEBVIEW2_ROOT}/build/native/include")
if(FLUTTER_TARGET_PLATFORM STREQUAL "windows-arm64")
  set(WEBVIEW2_ARCH arm64)
else()
  set(WEBVIEW2_ARCH x64)
endif()
target_link_libraries(${BINARY_NAME} PRIVATE
  "${WEBVIEW2_ROOT}/build/native/${WEBVIEW2_ARCH}/WebView2LoaderStatic.lib" shlwapi.lib version.lib)
