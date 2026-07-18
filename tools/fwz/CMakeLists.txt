# Builds `fwz`, the one program that turns a stock firmware file into yours.
#
# It is here so that installing needs nothing on your machine. Windows cannot write a Linux
# filesystem, a Mac has no tool for it either, and asking people to install WSL, Docker or
# Homebrew to flash a doorbell is not a reasonable trade. So the work is done by a single
# program that we build for each system and you simply download.
#
#     cmake -B build -DCMAKE_BUILD_TYPE=Release
#     cmake --build build
#
# It links no libraries you have to install. Two dependencies, both compiled in:
#
#   lwext4   reads and writes ext4 without a kernel, so without root. Written for
#            microcontrollers, which is exactly why it is portable enough for this
#   miniz    deflate, inflate and crc32, in one file
#
# The pinned lwext4 commit is deliberate. This writes firmware, and a silent change in how
# the filesystem is written is not something to discover on a device that will not boot.
cmake_minimum_required(VERSION 3.14)
project(fwz C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

include(FetchContent)
FetchContent_Declare(lwext4
    GIT_REPOSITORY https://github.com/gkostka/lwext4.git
    GIT_TAG        58bcf89a121b72d4fb66334f1693d3b30e4cb9c5
)
# Populate only. Its own CMake build wants a toolchain file and builds demo programs we do
# not want, so we take the source and compile it ourselves.
FetchContent_GetProperties(lwext4)
if(NOT lwext4_POPULATED)
    FetchContent_Populate(lwext4)
endif()
# One fix carried locally, and it is worth knowing why.
#
# ext4_block_get_noread hands back a cache buffer without reading anything into it -- the
# caller is expected to fill it. But the buffer either came straight from malloc, or was
# last used for a different block. Whatever it holds reaches the disk in every byte the
# caller does not overwrite.
#
# In a firmware image that shows up as heap addresses sitting in the padding after a
# directory entry, different on every build. Two people cannot then confirm they built the
# same file, and fragments of the building process travel inside a published one.
#
# Only when the buffer is newly assigned to this block. If it is already cached for this
# same block it may be holding writes that have not reached the disk yet, and clearing it
# would throw them away.
#
# patches/ carries the same change as a reviewable diff, with the full reasoning.
# Reported upstream.
set(BDEV ${lwext4_SOURCE_DIR}/src/ext4_blockdev.c)
file(READ ${BDEV} BDEV_SRC)
if(NOT BDEV_SRC MATCHES "fwz: cleared")
    string(REPLACE
        "	if (!b->data)\n		return ENOMEM;\n\n	return EOK;\n}\n\nint ext4_block_get("
        "	if (!b->data)\n		return ENOMEM;\n\n	/* fwz: cleared, because \"noread\" must not mean \"whatever was here before\" */\n	if (is_new)\n		memset(b->data, 0, bdev->bc->itemsize);\n\n	return EOK;\n}\n\nint ext4_block_get("
        BDEV_SRC "${BDEV_SRC}")
    file(WRITE ${BDEV} "${BDEV_SRC}")
    message(STATUS "lwext4: a no-read buffer is now cleared before it is handed out")
endif()

file(GLOB LWEXT4_SOURCES ${lwext4_SOURCE_DIR}/src/*.c)

add_executable(fwz
    src/main.c
    src/blockdev.c
    src/zip.c
    src/gz.c
    src/md5crypt.c
    src/ops.c
    src/tar.c
    vendor/miniz.c
    ${LWEXT4_SOURCES}
)

target_include_directories(fwz PRIVATE
    src
    vendor
    ${lwext4_SOURCE_DIR}/include
)

# lwext4 normally has its build system write a header of settings. We are not using its
# build system, so we take its built-in defaults and set the handful that matter here.
target_compile_definitions(fwz PRIVATE
    CONFIG_USE_DEFAULT_CFG=1        # skip the generated header; the defaults are right
    CONFIG_HAVE_OWN_OFLAGS=0        # this machine has its own open flags and errno
    CONFIG_HAVE_OWN_ERRNO=0
    CONFIG_HAVE_OWN_ASSERT=0
    CONFIG_BLOCK_DEV_CACHE_SIZE=16
    CONFIG_JOURNALING_ENABLE=1      # so a journal left behind can be replayed first
    CONFIG_EXTENTS_ENABLE=1         # the firmware's filesystem uses extents
    CONFIG_XATTR_ENABLE=1
    CONFIG_DIR_INDEX_ENABLE=1
    CONFIG_DEBUG_PRINTF=0           # its own chatter is not our user's business
    CONFIG_DEBUG_ASSERT=0
)

# lwext4 is written for embedded targets and is noisy under a desktop compiler's warnings.
# Ours are kept strict; theirs are not our business.
if(MSVC)
    target_compile_options(fwz PRIVATE /W3 /wd4996)
    target_compile_definitions(fwz PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(fwz PRIVATE -Wall -Wno-unused-function)
endif()
set_source_files_properties(${LWEXT4_SOURCES} PROPERTIES COMPILE_OPTIONS "")

# A program people download should not also need the right runtime libraries to be present.
if(MINGW)
    target_link_options(fwz PRIVATE -static -static-libgcc)
elseif(MSVC)
    set_property(TARGET fwz PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded")
elseif(NOT APPLE)
    # macOS does not support fully static linking and does not need it
    target_link_options(fwz PRIVATE -static)
endif()

install(TARGETS fwz RUNTIME DESTINATION bin)
