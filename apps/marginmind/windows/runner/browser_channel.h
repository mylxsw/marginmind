#ifndef RUNNER_BROWSER_CHANNEL_H_
#define RUNNER_BROWSER_CHANNEL_H_
#include <flutter/binary_messenger.h>
#include <windows.h>
#include <memory>
class BrowserHost {
 public:
  BrowserHost(flutter::BinaryMessenger* messenger, HWND parent);
  ~BrowserHost();
 private:
  struct Impl;
  std::shared_ptr<Impl> impl_;
};
#endif
