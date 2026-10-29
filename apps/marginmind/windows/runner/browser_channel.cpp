#include "browser_channel.h"
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <WebView2.h>
#include <wrl.h>
#include <shlobj.h>
#include <map>
#include <string>
#include <functional>

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using Channel = flutter::MethodChannel<Value>;
using Result = flutter::MethodResult<Value>;
namespace {
std::wstring Wide(const std::string& value) {
  int n = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
  std::wstring out(n, 0);
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), out.data(), n);
  return out;
}
std::string Utf8(const wchar_t* value) {
  if (!value) return "";
  int n = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
  std::string out(n, 0);
  WideCharToMultiByte(CP_UTF8, 0, value, -1, out.data(), n, nullptr, nullptr);
  if (!out.empty()) out.pop_back();
  return out;
}
std::string Text(const Map& map, const char* key) {
  auto it = map.find(Value(key));
  return it != map.end() && std::holds_alternative<std::string>(it->second) ? std::get<std::string>(it->second) : "";
}
double Number(const Map& map, const char* key) {
  auto it = map.find(Value(key));
  if (it == map.end()) return 0;
  if (auto v = std::get_if<double>(&it->second)) return *v;
  if (auto v = std::get_if<int32_t>(&it->second)) return *v;
  if (auto v = std::get_if<int64_t>(&it->second)) return static_cast<double>(*v);
  return 0;
}
bool Allowed(const wchar_t* value) {
  auto raw = Utf8(value);
  // Parsed a second time by WebView2; never dispatch OS protocol handlers.
  return raw.rfind("https://", 0) == 0 || raw.rfind("http://", 0) == 0;
}
const char* ErrorCategory(COREWEBVIEW2_WEB_ERROR_STATUS status) {
  switch (status) {
    case COREWEBVIEW2_WEB_ERROR_STATUS_TIMEOUT: return "timeout";
    case COREWEBVIEW2_WEB_ERROR_STATUS_HOST_NAME_NOT_RESOLVED: return "host";
    case COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_COMMON_NAME_IS_INCORRECT:
    case COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_EXPIRED:
    case COREWEBVIEW2_WEB_ERROR_STATUS_CLIENT_CERTIFICATE_CONTAINS_ERRORS:
    case COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_REVOKED:
    case COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_IS_INVALID: return "certificate";
    case COREWEBVIEW2_WEB_ERROR_STATUS_SERVER_UNREACHABLE:
    case COREWEBVIEW2_WEB_ERROR_STATUS_DISCONNECTED: return "offline";
    default: return "other";
  }
}
std::wstring Profile() {
  PWSTR path = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &path))) return L"";
  std::wstring profile = std::wstring(path) + L"\\MarginMind\\Browser";
  CoTaskMemFree(path);
  return profile;
}
struct Tab : std::enable_shared_from_this<Tab> {
  std::unique_ptr<Channel> channel;
  ComPtr<ICoreWebView2Controller> controller;
  ComPtr<ICoreWebView2> web;
  int generation = 0;
  UINT64 navigation_id = 0;
  bool closed = false;
  bool download_cancelled = false;
  std::function<void()> on_close;
  void Close() {
    if (closed) return;
    closed = true;
    if (channel) channel->SetMethodCallHandler(nullptr);
    if (controller) controller->Close();
    web.Reset(); controller.Reset();
    if (on_close) on_close();
  }
  ~Tab() { Close(); }
  void Emit(const char* kind, const char* error = "other") {
    if (closed || !web) return;
    LPWSTR source = nullptr; web->get_Source(&source);
    BOOL back = FALSE, forward = FALSE;
    web->get_CanGoBack(&back); web->get_CanGoForward(&forward);
    channel->InvokeMethod("event", std::make_unique<Value>(Map{
      {Value("kind"), Value(kind)}, {Value("navigationId"), Value(generation)}, {Value("error"), Value(error)},
      {Value("url"), Value(Utf8(source))}, {Value("back"), Value(back != FALSE)}, {Value("forward"), Value(forward != FALSE)}}));
    CoTaskMemFree(source);
  }
  void Initialize() {
    ComPtr<ICoreWebView2Settings> settings;
    web->get_Settings(&settings);
    // No AddHostObjectToScript or web message bridge, including WebView2's
    // default chrome.webview channel. Page scripts cannot invoke app commands.
    settings->put_IsWebMessageEnabled(FALSE);
    settings->put_AreHostObjectsAllowed(FALSE);
    settings->put_AreDefaultScriptDialogsEnabled(FALSE);
    settings->put_AreDefaultContextMenusEnabled(FALSE);
    settings->put_IsStatusBarEnabled(FALSE);
    EventRegistrationToken token;
    std::weak_ptr<Tab> weak = shared_from_this();
    web->add_NavigationStarting(Callback<ICoreWebView2NavigationStartingEventHandler>(
      [weak](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
        auto self = weak.lock(); if (!self || self->closed) return S_OK;
        LPWSTR uri = nullptr; args->get_Uri(&uri); bool allowed = Allowed(uri); CoTaskMemFree(uri);
        if (!allowed) { args->put_Cancel(TRUE); return S_OK; }
        args->get_NavigationId(&self->navigation_id);
        self->download_cancelled = false;
        ++self->generation; self->Emit("start"); return S_OK;
      }).Get(), &token);
    web->add_FrameNavigationStarting(Callback<ICoreWebView2NavigationStartingEventHandler>(
      [](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
        LPWSTR uri = nullptr; args->get_Uri(&uri);
        if (!Allowed(uri)) args->put_Cancel(TRUE);
        CoTaskMemFree(uri); return S_OK;
      }).Get(), &token);
    web->add_NavigationCompleted(Callback<ICoreWebView2NavigationCompletedEventHandler>(
      [weak](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
        auto self = weak.lock(); if (!self || self->closed) return S_OK;
        UINT64 id = 0; args->get_NavigationId(&id);
        if (id != self->navigation_id) return S_OK;
        if (self->download_cancelled) return S_OK;
        BOOL success = FALSE; args->get_IsSuccess(&success);
        COREWEBVIEW2_WEB_ERROR_STATUS status = COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
        args->get_WebErrorStatus(&status);
        ComPtr<ICoreWebView2NavigationCompletedEventArgs2> response;
        int http_status = 0;
        if (SUCCEEDED(args->QueryInterface(IID_PPV_ARGS(&response)))) response->get_HttpStatusCode(&http_status);
        // IsSuccess is also false for HTTP 4xx/5xx; those documents remain
        // readable and convertible. Only transport failures replace the page.
        if (success || (http_status >= 400 && http_status <= 599)) self->Emit("loaded");
        else if (status == COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED) self->Emit("download");
        else self->Emit("failed", ErrorCategory(status));
        return S_OK;
      }).Get(), &token);
    web->add_NewWindowRequested(Callback<ICoreWebView2NewWindowRequestedEventHandler>(
      [weak](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT {
        args->put_Handled(TRUE);
        auto self = weak.lock(); if (!self || self->closed) return S_OK;
        LPWSTR uri = nullptr; args->get_Uri(&uri);
        if (Allowed(uri)) self->web->Navigate(uri);
        CoTaskMemFree(uri); return S_OK;
      }).Get(), &token);
    web->add_PermissionRequested(Callback<ICoreWebView2PermissionRequestedEventHandler>(
      [](ICoreWebView2*, ICoreWebView2PermissionRequestedEventArgs* args) -> HRESULT {
        args->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY); return S_OK;
      }).Get(), &token);
    ComPtr<ICoreWebView2_4> downloads;
    if (SUCCEEDED(web.As(&downloads))) downloads->add_DownloadStarting(
      Callback<ICoreWebView2DownloadStartingEventHandler>(
        [weak](ICoreWebView2*, ICoreWebView2DownloadStartingEventArgs* args) -> HRESULT {
          auto self = weak.lock();
          if (self) self->download_cancelled = true;
          args->put_Cancel(TRUE); args->put_Handled(TRUE);
          if (self) self->Emit("download");
          return S_OK;
        }).Get(), &token);
    channel->SetMethodCallHandler([weak](const flutter::MethodCall<Value>& call, std::unique_ptr<Result> result) {
      auto self = weak.lock();
      if (!self || self->closed) { result->Success(); return; }
      auto args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      const Map empty; const Map& a = args ? *args : empty;
      const auto& method = call.method_name();
      if (method == "navigate") {
        auto uri = Wide(Text(a, "url"));
        if (!Allowed(uri.c_str())) { result->Error("invalid_url"); return; }
        self->web->Navigate(uri.c_str());
      } else if (method == "back") self->web->GoBack();
      else if (method == "forward") self->web->GoForward();
      else if (method == "reload") self->web->Reload();
      else if (method == "stop") self->web->Stop();
      else if (method == "dispose") self->Close();
      else if (method == "bounds") {
        RECT rect{static_cast<LONG>(Number(a,"x")), static_cast<LONG>(Number(a,"y")),
          static_cast<LONG>(Number(a,"x")+Number(a,"width")), static_cast<LONG>(Number(a,"y")+Number(a,"height"))};
        self->controller->put_Bounds(rect);
        auto visible = a.find(Value("visible"));
        self->controller->put_IsVisible(visible != a.end() && std::get<bool>(visible->second));
      } else if (method == "evaluate") {
        // ExecuteScript returns JSON encoding of the string returned by our
        // closure. Return the decoded string using Flutter's JSON codec.
        auto response = std::shared_ptr<Result>(std::move(result));
        auto hr = self->web->ExecuteScript(Wide(Text(a,"script")).c_str(),
          Callback<ICoreWebView2ExecuteScriptCompletedHandler>([response](HRESULT error, LPCWSTR json) -> HRESULT {
            if (FAILED(error)) response->Error("script_failed");
            else response->Success(Value(Utf8(json))); return S_OK;
          }).Get());
        if (FAILED(hr)) response->Error("script_failed");
        return;
      } else { result->NotImplemented(); return; }
      result->Success();
    });
  }
};
}
struct BrowserHost::Impl : std::enable_shared_from_this<Impl> {
  flutter::BinaryMessenger* messenger;
  HWND parent;
  std::unique_ptr<Channel> channel;
  ComPtr<ICoreWebView2Environment> environment;
  ComPtr<ICoreWebView2Profile2> profile;
  std::map<int, std::shared_ptr<Tab>> tabs;
  Impl(flutter::BinaryMessenger* m, HWND p) : messenger(m), parent(p) {}
  void Create(int id, std::shared_ptr<Result> result) {
    auto tab = std::make_shared<Tab>();
    tab->channel = std::make_unique<Channel>(messenger, "marginmind/browser/" + std::to_string(id), &flutter::StandardMethodCodec::GetInstance());
    std::weak_ptr<Impl> weak = shared_from_this();
    tab->on_close = [weak,id]() { if (auto host = weak.lock()) host->tabs.erase(id); };
    tabs[id] = tab;
    std::weak_ptr<Impl> owner = shared_from_this();
    environment->CreateCoreWebView2Controller(parent,
      Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>([tab, result, owner](HRESULT hr, ICoreWebView2Controller* controller) -> HRESULT {
        if (FAILED(hr) || !controller) { result->Error("webview_unavailable"); return S_OK; }
        if (tab->closed) { controller->Close(); result->Error("disposed"); return S_OK; }
        tab->controller = controller; controller->put_IsVisible(FALSE); controller->get_CoreWebView2(&tab->web);
        ComPtr<ICoreWebView2_13> view;
        if (auto host = owner.lock(); host && SUCCEEDED(tab->web.As(&view))) {
          ComPtr<ICoreWebView2Profile> base; view->get_Profile(&base); base.As(&host->profile);
        }
        tab->Initialize(); result->Success(); return S_OK;
      }).Get());
  }
  void Start() {
    channel = std::make_unique<Channel>(messenger, "marginmind/browser", &flutter::StandardMethodCodec::GetInstance());
    std::weak_ptr<Impl> weak = shared_from_this();
    channel->SetMethodCallHandler([weak](const flutter::MethodCall<Value>& call, std::unique_ptr<Result> result) {
      auto self = weak.lock(); if (!self) { result->Error("disposed"); return; }
      if (call.method_name() == "clearData") {
        // Clear through WebView2's profile API, then close every controller.
        // This covers cookies, cache, DOM storage and service workers.
        if (self->profile) {
          auto clear = self->profile;
          for (auto& item : self->tabs) {
            if (item.second->controller) item.second->controller->put_IsVisible(FALSE);
            if (item.second->web) item.second->web->Stop();
          }
          auto response = std::shared_ptr<Result>(std::move(result));
          clear->ClearBrowsingDataAll(Callback<ICoreWebView2ClearBrowsingDataCompletedHandler>([weak,response](HRESULT hr) -> HRESULT {
            if (auto host = weak.lock()) {
              auto closing = std::move(host->tabs); host->tabs.clear();
              for (auto& item : closing) item.second->Close();
            }
            if (FAILED(hr)) response->Error("clear_failed"); else response->Success(); return S_OK;
          }).Get());
        } else {
          // Initialize a hidden controller so a user can clear a persisted
          // profile before opening their first page after restarting the app.
          result->Error("clear_requires_view");
        }
        return;
      }
      if (call.method_name() != "create") { result->NotImplemented(); return; }
      auto args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      if (!args) { result->Error("invalid_request"); return; }
      int id = static_cast<int>(Number(*args, "id"));
      auto response = std::shared_ptr<Result>(std::move(result));
      if (self->environment) { self->Create(id, response); return; }
      auto path = Profile();
      if (path.empty()) { response->Error("profile_unavailable"); return; }
      CreateCoreWebView2EnvironmentWithOptions(nullptr, path.c_str(), nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>([weak,id,response](HRESULT hr, ICoreWebView2Environment* env) -> HRESULT {
          auto owner = weak.lock(); if (!owner || FAILED(hr) || !env) { response->Error("webview_unavailable"); return S_OK; }
          owner->environment = env; owner->Create(id,response); return S_OK;
        }).Get());
    });
  }
  ~Impl() { auto closing = std::move(tabs); for (auto& item : closing) item.second->Close(); }
};
BrowserHost::BrowserHost(flutter::BinaryMessenger* messenger, HWND parent) : impl_(std::make_shared<Impl>(messenger,parent)) { impl_->Start(); }
BrowserHost::~BrowserHost() = default;
