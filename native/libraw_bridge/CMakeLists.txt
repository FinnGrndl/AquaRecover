cmake_minimum_required(VERSION 3.18)
project(aqua_raw_bridge LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(aqua_raw_bridge SHARED libraw_bridge.cpp)
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBRAW REQUIRED libraw)
target_include_directories(aqua_raw_bridge PRIVATE ${LIBRAW_INCLUDE_DIRS})
target_link_libraries(aqua_raw_bridge PRIVATE ${LIBRAW_LIBRARIES})
