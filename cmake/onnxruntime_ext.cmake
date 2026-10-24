project(onnxruntme_ext)
set(ONNX_EXT_NAME onnxruntime_ext)
include(ExternalProject)

if(NOT EXISTS ${DEP_ROOT_DIR}/${ONNX_EXT_NAME})
    file(MAKE_DIRECTORY ${DEP_ROOT_DIR}/${ONNX_EXT_NAME})
else()
    file(REMOVE_RECURSE ${DEP_ROOT_DIR}/${ONNX_EXT_NAME})
    file(MAKE_DIRECTORY ${DEP_ROOT_DIR}/${ONNX_EXT_NAME})
endif()

ExternalProject_Add(
    onnxruntime_ext
    GIT_REPOSITORY https://github.com/microsoft/onnxruntime-extensions
    GIT_TAG origin/rel-0.6.0
    SOURCE_DIR ${DEP_ROOT_DIR}/${ONNX_EXT_NAME}
    PATCH_COMMAND ${CMAKE_COMMAND}
        -DONNX_EXT_SOURCE_DIR=<SOURCE_DIR>
        -P ${CMAKE_CURRENT_LIST_DIR}/onnxruntime_ext_patch.cmake
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ""
)
