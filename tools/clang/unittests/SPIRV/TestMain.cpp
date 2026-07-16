//===--- utils/unittest/SPIRV/TestMain.cpp - unittest driver --------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//

#include "gmock/gmock.h"
#include "gtest/gtest.h"

#include "llvm/Support/Signals.h"

#include "SpirvTestOptions.h"
#include "dxc/Support/Global.h"

#if defined(_WIN32)
#include <windows.h>
#include <crtdbg.h>
#ifndef NDEBUG
#include <DbgHelp.h>
#pragma comment(lib, "dbghelp.lib")
#include <csignal>
#include <cstdlib>
#include <exception>
#include <iostream>
#include <iomanip>
#endif // NDEBUG
#endif // _WIN32

namespace {
using namespace ::testing;

//===----------------------------------------------------------------------===//
// Debug infrastructure: stack traces on crash, no message boxes
//===----------------------------------------------------------------------===//

#if defined(_WIN32) && !defined(NDEBUG)

/// Print a verbose stack trace with DbgHelp symbol resolution.
void print_stack_trace() {
  void *stack[100];
  auto process = GetCurrentProcess();
  static bool sym_initialized = false;
  if (!sym_initialized) {
    SymSetOptions(SYMOPT_LOAD_LINES | SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS);
    sym_initialized = SymInitialize(process, nullptr, TRUE);
  }
  auto frame_count = CaptureStackBackTrace(0, 100, stack, nullptr);
  std::cerr << "\n=== Stack trace (" << frame_count << " frames) ===\n";

  // Allocate symbol info buffer
  char symbolBuffer[sizeof(SYMBOL_INFO) + MAX_SYM_NAME * sizeof(TCHAR)];
  auto *symbol = reinterpret_cast<SYMBOL_INFO *>(symbolBuffer);
  symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
  symbol->MaxNameLen = MAX_SYM_NAME;

  IMAGEHLP_MODULE64 moduleInfo;
  moduleInfo.SizeOfStruct = sizeof(IMAGEHLP_MODULE64);

  for (unsigned i = 0; i < frame_count; ++i) {
    DWORD64 address = reinterpret_cast<DWORD64>(stack[i]);
    DWORD64 displacement = 0;

    std::cerr << "  [" << std::setw(2) << i << "] ";

    if (SymFromAddr(process, address, &displacement, symbol)) {
      std::cerr << symbol->Name;
      if (displacement)
        std::cerr << "+0x" << std::hex << displacement << std::dec;

      if (SymGetModuleInfo64(process, address, &moduleInfo)) {
        std::cerr << "  at " << moduleInfo.ModuleName
                  << "+0x" << std::hex << (address - moduleInfo.BaseOfImage)
                  << std::dec;
      }
    } else {
      std::cerr << "0x" << std::hex << address << std::dec;
    }
    std::cerr << "\n";
  }
  std::cerr << std::flush;
}

LONG WINAPI UnhandledExceptionFilter(EXCEPTION_POINTERS *) {
  std::cerr << "\n!!! Unhandled structured exception !!!\n";
  print_stack_trace();
  ExitProcess(1);
  return EXCEPTION_EXECUTE_HANDLER;
}

void OnTerminate() {
  std::cerr << "\n!!! std::terminate called (uncaught exception) !!!\n";
  print_stack_trace();
  ExitProcess(1);
}

void OnSigAbort(int) {
  std::cerr << "\n!!! SIGABRT / std::abort() called !!!\n";
  print_stack_trace();
  _exit(3);
}

struct StackTracerInit {
  StackTracerInit() noexcept {
    SetUnhandledExceptionFilter(UnhandledExceptionFilter);
    std::set_terminate(OnTerminate);
    std::signal(SIGABRT, OnSigAbort);
  }
};

static StackTracerInit stack_tracer_init;

#endif // _WIN32 && !NDEBUG

// Unconditionally disable Windows error dialogs and redirect to stderr.
// Not gated on _MSC_VER -- works with clang-cl too.
#if defined(_WIN32)
struct DisableMessageBoxInit {
  DisableMessageBoxInit() noexcept {
#ifndef NDEBUG
    _CrtSetReportMode(_CRT_WARN, _CRTDBG_MODE_FILE);
    _CrtSetReportFile(_CRT_WARN, _CRTDBG_FILE_STDERR);
    _CrtSetReportMode(_CRT_ERROR, _CRTDBG_MODE_FILE);
    _CrtSetReportFile(_CRT_ERROR, _CRTDBG_FILE_STDERR);
    _CrtSetReportMode(_CRT_ASSERT, _CRTDBG_MODE_FILE);
    _CrtSetReportFile(_CRT_ASSERT, _CRTDBG_FILE_STDERR);
#endif
    _set_error_mode(_OUT_TO_STDERR);
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
  }
};

static DisableMessageBoxInit disable_message_box;
#endif

/// A GoogleTest event printer that only prints test failures.
class FailurePrinter : public TestEventListener {
public:
  explicit FailurePrinter(TestEventListener *listener)
      : defaultListener(listener) {}

  ~FailurePrinter() override { delete defaultListener; }

  void OnTestProgramStart(const UnitTest &ut) override {
    defaultListener->OnTestProgramStart(ut);
  }

  void OnTestIterationStart(const UnitTest &ut, int iteration) override {
    defaultListener->OnTestIterationStart(ut, iteration);
  }

  void OnEnvironmentsSetUpStart(const UnitTest &ut) override {
    defaultListener->OnEnvironmentsSetUpStart(ut);
  }

  void OnEnvironmentsSetUpEnd(const UnitTest &ut) override {
    defaultListener->OnEnvironmentsSetUpEnd(ut);
  }

  void OnTestCaseStart(const TestCase &tc) override {
    defaultListener->OnTestCaseStart(tc);
  }

  void OnTestStart(const TestInfo &ti) override {
    // Do not output on test start
    // defaultListener->OnTestStart(ti);
  }

  void OnTestPartResult(const TestPartResult &result) override {
    defaultListener->OnTestPartResult(result);
  }

  void OnTestEnd(const TestInfo &ti) override {
    // Only output if failure on test end
    if (ti.result()->Failed())
      defaultListener->OnTestEnd(ti);
  }

  void OnTestCaseEnd(const TestCase &tc) override {
    defaultListener->OnTestCaseEnd(tc);
  }

  void OnEnvironmentsTearDownStart(const UnitTest &ut) override {
    defaultListener->OnEnvironmentsTearDownStart(ut);
  }

  void OnEnvironmentsTearDownEnd(const UnitTest &ut) override {
    defaultListener->OnEnvironmentsTearDownEnd(ut);
  }

  void OnTestIterationEnd(const UnitTest &ut, int iteration) override {
    defaultListener->OnTestIterationEnd(ut, iteration);
  }

  void OnTestProgramEnd(const UnitTest &ut) override {
    defaultListener->OnTestProgramEnd(ut);
  }

private:
  TestEventListener *defaultListener;
};
} // namespace

const char *TestMainArgv0;

int main(int argc, char **argv) {
  llvm::sys::PrintStackTraceOnErrorSignal(true /* Disable crash reporting */);

  for (int i = 1; i < argc; ++i) {
    if (std::string("--spirv-test-root") == argv[i]) {
      // Allow the user set the root directory for test input files.
      if (i + 1 < argc) {
        clang::spirv::testOptions::inputDataDir = argv[++i];
      } else {
        fprintf(stderr, "Error: --spirv-test-root requires an argument\n");
        return 1;
      }
    }
  }

  // Initialize both gmock and gtest.
  testing::InitGoogleMock(&argc, argv);

  // Switch event listener to one that only prints failures.
  testing::TestEventListeners &listeners =
      ::testing::UnitTest::GetInstance()->listeners();
  auto *defaultPrinter = listeners.Release(listeners.default_result_printer());
  // Google Test takes the ownership.
  listeners.Append(new FailurePrinter(defaultPrinter));

  // Make it easy for a test to re-execute itself by saving argv[0].
  TestMainArgv0 = argv[0];

#if defined(_WIN32)
  // Disable all of the possible ways Windows conspires to make automated
  // testing impossible.
  ::SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
#if defined(_MSC_VER)
  ::_set_error_mode(_OUT_TO_STDERR);
  _CrtSetReportMode(_CRT_WARN, _CRTDBG_MODE_FILE | _CRTDBG_MODE_DEBUG);
  _CrtSetReportFile(_CRT_WARN, _CRTDBG_FILE_STDERR);
  _CrtSetReportMode(_CRT_ERROR, _CRTDBG_MODE_FILE | _CRTDBG_MODE_DEBUG);
  _CrtSetReportFile(_CRT_ERROR, _CRTDBG_FILE_STDERR);
  _CrtSetReportMode(_CRT_ASSERT, _CRTDBG_MODE_FILE | _CRTDBG_MODE_DEBUG);
  _CrtSetReportFile(_CRT_ASSERT, _CRTDBG_FILE_STDERR);
#endif
#endif

  // DxcInitThreadMalloc()/DxcCleanupThreadMalloc() only once for module.
  DxcInitThreadMalloc();
  int result = RUN_ALL_TESTS();
  DxcCleanupThreadMalloc();

  return result;
}
