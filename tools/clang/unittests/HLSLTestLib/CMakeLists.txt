
if(WIN32)
find_package(TAEF REQUIRED)
include_directories(${TAEF_INCLUDE_DIRS})
endif(WIN32)
include_directories(${LLVM_MAIN_SRC_DIR}/utils/unittest/googletest/include)
include_directories(${LLVM_MAIN_SRC_DIR}/utils/unittest/googlemock/include)

add_clang_library(HLSLTestLib
  DxcTestUtils.cpp
  FileCheckerTest.cpp
  FileCheckForTest.cpp
)

add_dependencies(HLSLTestLib TablegenHLSLOptions)

set_target_properties(HLSLTestLib PROPERTIES FOLDER "Clang tests")
