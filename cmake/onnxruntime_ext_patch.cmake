find_package(Git REQUIRED)

set(COMPAT_PATCH "${CMAKE_CURRENT_LIST_DIR}/onnx_ext.patch")
set(INTEGER_PATCH "${CMAKE_CURRENT_LIST_DIR}/../bazel/onnx-extensions-cstdint.patch")
set(NAMESPACE_PATCH "${CMAKE_CURRENT_LIST_DIR}/../bazel/onnx-extensions-namespace.patch")

function(apply_onnx_patch patch_file strip_level)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" apply "-p${strip_level}" ${ARGN} "${patch_file}"
        WORKING_DIRECTORY "${ONNX_EXT_SOURCE_DIR}"
        COMMAND_ERROR_IS_FATAL ANY
    )
endfunction()

# Undo the existing stack in reverse order before reapplying overlapping patches.
execute_process(
    COMMAND "${GIT_EXECUTABLE}" apply -p0 --reverse --check "${NAMESPACE_PATCH}"
    WORKING_DIRECTORY "${ONNX_EXT_SOURCE_DIR}"
    RESULT_VARIABLE NAMESPACE_APPLIED
    OUTPUT_QUIET ERROR_QUIET
)
if(NAMESPACE_APPLIED EQUAL 0)
    apply_onnx_patch("${NAMESPACE_PATCH}" 0 --reverse)
    apply_onnx_patch("${INTEGER_PATCH}" 0 --reverse)
    apply_onnx_patch("${COMPAT_PATCH}" 1 --reverse)
endif()

apply_onnx_patch("${COMPAT_PATCH}" 1)
apply_onnx_patch("${INTEGER_PATCH}" 0)
apply_onnx_patch("${NAMESPACE_PATCH}" 0)

set(OPERATORS_DIR "${ONNX_EXT_SOURCE_DIR}/operators")
file(MAKE_DIRECTORY "${OPERATORS_DIR}/src_dir/tokenizer")
file(COPY
    "${OPERATORS_DIR}/base64.h" "${OPERATORS_DIR}/base64.cc"
    "${OPERATORS_DIR}/string_utils_onnx.h" "${OPERATORS_DIR}/string_utils_onnx.cc"
    "${OPERATORS_DIR}/ustring.h" "${OPERATORS_DIR}/ustring.cc"
    DESTINATION "${OPERATORS_DIR}/src_dir"
)
file(COPY
    "${OPERATORS_DIR}/tokenizer/bert_tokenizer.hpp"
    "${OPERATORS_DIR}/tokenizer/bert_tokenizer.cc"
    "${OPERATORS_DIR}/tokenizer/basic_tokenizer.hpp"
    "${OPERATORS_DIR}/tokenizer/basic_tokenizer.cc"
    DESTINATION "${OPERATORS_DIR}/src_dir/tokenizer"
)
