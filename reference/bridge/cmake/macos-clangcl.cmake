# Cross-compiles a Windows x64 DLL on macOS: Homebrew's clang-cl and lld-link against the
# Windows SDK and MSVC headers that `xwin splat` wrote. The prebuilt CommonLibSSE-NG library
# was built with clang-cl 22.1, so the compiler must be 22.1 too.
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR AMD64)

set(_llvm "${LLVM_PREFIX}/bin")
set(CMAKE_C_COMPILER "${_llvm}/clang-cl")
set(CMAKE_CXX_COMPILER "${_llvm}/clang-cl")
set(CMAKE_LINKER "${LLD_PREFIX}/bin/lld-link")
set(CMAKE_AR "${_llvm}/llvm-lib")
set(CMAKE_RC_COMPILER "${_llvm}/llvm-rc")
set(CMAKE_MT "${_llvm}/llvm-mt")

set(_sysroot "--target=x86_64-pc-windows-msvc /winsysroot\"${XWIN_SYSROOT}\"")
set(CMAKE_C_FLAGS_INIT "${_sysroot}")
set(CMAKE_CXX_FLAGS_INIT "${_sysroot} /EHsc")
set(CMAKE_RC_FLAGS_INIT "${_sysroot}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "/winsysroot:\"${XWIN_SYSROOT}\"")
set(CMAKE_EXE_LINKER_FLAGS_INIT "/winsysroot:\"${XWIN_SYSROOT}\"")

# xwin writes only the release CRT, so CMake's compiler check links in Release too.
set(CMAKE_TRY_COMPILE_CONFIGURATION Release)
