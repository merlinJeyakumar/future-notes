#include "desktop_file_actions.h"

#include <fcntl.h>
#include <gio/gunixfdlist.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

namespace {
constexpr char kPortalName[] = "org.freedesktop.portal.Desktop";
constexpr char kPortalPath[] = "/org/freedesktop/portal/desktop";
constexpr char kOpenInterface[] = "org.freedesktop.portal.OpenURI";
constexpr char kRequestInterface[] = "org.freedesktop.portal.Request";

class FileDescriptor {
 public:
  explicit FileDescriptor(int value = -1) : value_(value) {}
  ~FileDescriptor() { Reset(); }
  int get() const { return value_; }
  void Reset(int value = -1) {
    if (value_ >= 0) close(value_);
    value_ = value;
  }

 private:
  FileDescriptor(const FileDescriptor&) = delete;
  FileDescriptor& operator=(const FileDescriptor&) = delete;
  int value_;
};

// Follow descriptors, never symlinks, including intermediate path components.
bool PathParts(const std::string& path, std::vector<std::string>* parts) {
  if (path.empty() || path.front() != '/' ||
      !g_utf8_validate(path.c_str(), path.size(), nullptr)) {
    return false;
  }
  size_t start = 1;
  while (start < path.size()) {
    size_t end = path.find('/', start);
    if (end == std::string::npos) end = path.size();
    const std::string part = path.substr(start, end - start);
    if (part == "." || part == "..") return false;
    if (!part.empty()) parts->push_back(part);
    start = end + 1;
  }
  return true;
}

int OpenDirectory(const std::string& path, bool create) {
  std::vector<std::string> parts;
  if (!PathParts(path, &parts)) return -1;
  FileDescriptor directory(open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC));
  for (const auto& part : parts) {
    int next = openat(directory.get(), part.c_str(),
                      O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (next < 0 && errno == ENOENT && create) {
      if (mkdirat(directory.get(), part.c_str(), 0700) != 0 &&
          errno != EEXIST) {
        return -1;
      }
      next = openat(directory.get(), part.c_str(),
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    }
    if (next < 0) return -1;
    directory.Reset(next);
  }
  return directory.get() < 0 ? -1 : fcntl(directory.get(), F_DUPFD_CLOEXEC, 0);
}

int PrivateChild(int parent, const char* name) {
  if (mkdirat(parent, name, 0700) != 0 && errno != EEXIST) return -1;
  FileDescriptor child(
      openat(parent, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  struct stat metadata;
  if (child.get() < 0 || fstat(child.get(), &metadata) != 0 ||
      metadata.st_uid != geteuid() || !S_ISDIR(metadata.st_mode) ||
      fchmod(child.get(), 0700) != 0) {
    return -1;
  }
  return fcntl(child.get(), F_DUPFD_CLOEXEC, 0);
}

int CacheDirectory(std::string* path) {
  const char* base = g_get_user_cache_dir();
  if (base == nullptr) return -1;
  FileDescriptor cache(OpenDirectory(base, true));
  struct stat metadata;
  if (cache.get() < 0 || fstat(cache.get(), &metadata) != 0 ||
      metadata.st_uid != geteuid() || (metadata.st_mode & 0022) != 0) {
    return -1;
  }
  FileDescriptor application(PrivateChild(cache.get(), "future-notes"));
  if (application.get() < 0) return -1;
  FileDescriptor previews(
      PrivateChild(application.get(), "attachment-preview"));
  if (previews.get() < 0) return -1;
  g_autofree gchar* value =
      g_build_filename(base, "future-notes", "attachment-preview", nullptr);
  *path = value;
  return fcntl(previews.get(), F_DUPFD_CLOEXEC, 0);
}

int OpenLocalFile(const std::string& path, bool reveal) {
  std::vector<std::string> parts;
  if (!PathParts(path, &parts) || parts.empty()) return -1;
  FileDescriptor directory;
  if (!reveal) {
    std::string cache_path;
    directory.Reset(CacheDirectory(&cache_path));
    const std::string prefix = cache_path + "/";
    if (directory.get() < 0 || path.compare(0, prefix.size(), prefix) != 0) {
      return -1;
    }
    parts.clear();
    if (!PathParts("/" + path.substr(prefix.size()), &parts) || parts.empty()) {
      return -1;
    }
  } else {
    directory.Reset(open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC));
  }
  for (size_t index = 0; index + 1 < parts.size(); index++) {
    int next = openat(directory.get(), parts[index].c_str(),
                      O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (next < 0) return -1;
    directory.Reset(next);
  }
  FileDescriptor file(openat(directory.get(), parts.back().c_str(),
                             O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK));
  struct stat metadata;
  if (file.get() < 0 || fstat(file.get(), &metadata) != 0 ||
      (!S_ISREG(metadata.st_mode) && !(reveal && S_ISDIR(metadata.st_mode))) ||
      (!reveal && (metadata.st_uid != geteuid() || metadata.st_nlink != 1))) {
    return -1;
  }
  return fcntl(file.get(), F_DUPFD_CLOEXEC, 0);
}

void Respond(FlMethodCall* call, const char* code = nullptr,
             const char* message = nullptr, FlValue* value = nullptr) {
  g_autoptr(FlMethodResponse) response =
      code == nullptr
          ? FL_METHOD_RESPONSE(fl_method_success_response_new(value))
          : FL_METHOD_RESPONSE(
                fl_method_error_response_new(code, message, nullptr));
  // The engine may already be closing. Never log a file path or native error.
  fl_method_call_respond(call, response, nullptr);
}

struct Request;
using PendingRequest = std::shared_ptr<Request>;

struct Actions {
  explicit Actions(GtkWindow* value) { g_weak_ref_init(&window, value); }
  ~Actions() { g_weak_ref_clear(&window); }
  GWeakRef window;
  bool closed = false;
  std::vector<std::weak_ptr<Request>> requests;
};

struct Request {
  Request(std::shared_ptr<Actions> owner, FlMethodCall* method,
          std::string local_path, bool show_folder, int descriptor)
      : actions(std::move(owner)),
        call(FL_METHOD_CALL(g_object_ref(method))),
        path(std::move(local_path)),
        reveal(show_folder),
        file(descriptor),
        cancellation(g_cancellable_new()) {}
  ~Request() {
    g_clear_object(&call);
    g_clear_object(&connection);
    g_clear_object(&cancellation);
  }
  std::shared_ptr<Actions> actions;
  FlMethodCall* call;
  std::string path;
  bool reveal;
  FileDescriptor file;
  GCancellable* cancellation;
  GDBusConnection* connection = nullptr;
  std::string handle;
  guint response_subscription = 0;
  guint owner_subscription = 0;
  gulong closed_handler = 0;
  bool finished = false;
};

gpointer Retain(const PendingRequest& request) {
  return new PendingRequest(request);
}

PendingRequest Take(gpointer data) {
  std::unique_ptr<PendingRequest> retained(static_cast<PendingRequest*>(data));
  return *retained;
}

void DeleteRequest(gpointer data) { delete static_cast<PendingRequest*>(data); }

void ClearSubscriptions(const PendingRequest& request) {
  if (request->response_subscription != 0) {
    g_dbus_connection_signal_unsubscribe(request->connection,
                                         request->response_subscription);
    request->response_subscription = 0;
  }
  if (request->owner_subscription != 0) {
    g_dbus_connection_signal_unsubscribe(request->connection,
                                         request->owner_subscription);
    request->owner_subscription = 0;
  }
  if (request->closed_handler != 0) {
    g_signal_handler_disconnect(request->connection, request->closed_handler);
    request->closed_handler = 0;
  }
}

void Finish(const PendingRequest& request, const char* code = nullptr,
            const char* message = nullptr, bool close_portal = false) {
  if (request->finished) return;
  request->finished = true;
  if (close_portal && request->connection != nullptr &&
      !request->handle.empty() &&
      !g_dbus_connection_is_closed(request->connection)) {
    g_dbus_connection_call(request->connection, kPortalName,
                           request->handle.c_str(), kRequestInterface, "Close",
                           nullptr, nullptr, G_DBUS_CALL_FLAGS_NONE, 5000,
                           nullptr, nullptr, nullptr);
  }
  ClearSubscriptions(request);
  g_cancellable_cancel(request->cancellation);
  Respond(request->call, code, message);
  request->file.Reset();
}

bool PortalRequired() {
  const char* gtk_portal = g_getenv("GTK_USE_PORTAL");
  const char* gio_portal = g_getenv("GIO_USE_PORTALS");
  return g_file_test("/.flatpak-info", G_FILE_TEST_EXISTS) ||
         g_getenv("FLATPAK_ID") != nullptr || g_getenv("SNAP") != nullptr ||
         g_getenv("SNAP_NAME") != nullptr ||
         (gtk_portal != nullptr && strcmp(gtk_portal, "0") != 0) ||
         (gio_portal != nullptr && strcmp(gio_portal, "0") != 0);
}

bool PortalUnavailable(const GError* error) {
  return error != nullptr &&
         (g_error_matches(error, G_DBUS_ERROR, G_DBUS_ERROR_SERVICE_UNKNOWN) ||
          g_error_matches(error, G_DBUS_ERROR,
                          G_DBUS_ERROR_NAME_HAS_NO_OWNER) ||
          g_error_matches(error, G_DBUS_ERROR,
                          G_DBUS_ERROR_UNKNOWN_INTERFACE) ||
          g_error_matches(error, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_OBJECT) ||
          g_error_matches(error, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD));
}

void FallbackFinished(GObject*, GAsyncResult* result, gpointer data) {
  const auto request = Take(data);
  g_autoptr(GError) error = nullptr;
  const gboolean launched =
      g_app_info_launch_default_for_uri_finish(result, &error);
  if (request->finished) return;
  if (launched) {
    Finish(request);
  } else {
    Finish(request, "open_failed", "The local file action failed.");
  }
}

// Called only when the portal/capability is unavailable, never after a user's
// cancellation, refusal, or a portal launch failure. Sandboxes require a
// portal.
void LocalFallback(const PendingRequest& request) {
  if (request->finished) return;
  ClearSubscriptions(request);
  request->handle.clear();
  if (PortalRequired()) {
    Finish(request, "portal_unavailable", "A desktop portal is required.");
    return;
  }
  struct stat held;
  struct stat current;
  if (fstat(request->file.get(), &held) != 0 ||
      lstat(request->path.c_str(), &current) != 0 ||
      held.st_dev != current.st_dev || held.st_ino != current.st_ino ||
      S_ISLNK(current.st_mode)) {
    Finish(request, "invalid_path", "The local file changed.");
    return;
  }
  g_autofree gchar* parent =
      request->reveal ? g_path_get_dirname(request->path.c_str()) : nullptr;
  g_autoptr(GFile) file =
      g_file_new_for_path(request->reveal ? parent : request->path.c_str());
  g_autofree gchar* uri = g_file_get_uri(file);
  g_app_info_launch_default_for_uri_async(uri, nullptr, request->cancellation,
                                          FallbackFinished, Retain(request));
}

void PortalResponse(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                    const gchar*, GVariant* parameters, gpointer data) {
  const auto request = *static_cast<PendingRequest*>(data);
  if (request->finished) return;
  if (!g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ua{sv})"))) {
    Finish(request, "portal_failed", "Invalid desktop portal response.");
    return;
  }
  guint32 response;
  g_autoptr(GVariant) results = nullptr;
  g_variant_get(parameters, "(u@a{sv})", &response, &results);
  if (response == 0) {
    Finish(request);
  } else if (response == 1) {
    Finish(request, "cancelled", "The file action was cancelled.");
  } else {
    Finish(request, "portal_failed", "The desktop portal declined the action.");
  }
}

void SubscribeResponse(const PendingRequest& request) {
  if (request->response_subscription != 0) {
    g_dbus_connection_signal_unsubscribe(request->connection,
                                         request->response_subscription);
  }
  request->response_subscription = g_dbus_connection_signal_subscribe(
      request->connection, kPortalName, kRequestInterface, "Response",
      request->handle.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      PortalResponse, Retain(request), DeleteRequest);
}

void PortalOwnerChanged(GDBusConnection*, const gchar*, const gchar*,
                        const gchar*, const gchar*, GVariant* parameters,
                        gpointer data) {
  const auto request = *static_cast<PendingRequest*>(data);
  const gchar* name;
  const gchar* previous;
  const gchar* current;
  g_variant_get(parameters, "(&s&s&s)", &name, &previous, &current);
  if (current[0] == '\0') {
    Finish(request, "portal_failed", "The desktop portal disconnected.");
  }
}

void ConnectionClosed(GDBusConnection*, gboolean, GError*, gpointer data) {
  const auto request = *static_cast<PendingRequest*>(data);
  Finish(request, "portal_failed", "The desktop connection closed.");
}

void PortalCallFinished(GObject* object, GAsyncResult* result, gpointer data) {
  const auto request = Take(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_with_unix_fd_list_finish(
      G_DBUS_CONNECTION(object), nullptr, result, &error);
  if (request->finished) return;
  if (reply == nullptr) {
    if (PortalUnavailable(error)) {
      LocalFallback(request);
    } else {
      Finish(request, "portal_failed", "The desktop portal could not open it.");
    }
    return;
  }
  const gchar* handle;
  g_variant_get(reply, "(&o)", &handle);
  if (request->handle != handle) {
    request->handle = handle;
    SubscribeResponse(request);
  }
}

void InvokePortal(const PendingRequest& request) {
  g_autofree gchar* random = g_uuid_string_random();
  std::string token = "future_notes_";
  for (const char* character = random; *character != '\0'; character++) {
    if (*character != '-') token.push_back(*character);
  }
  const char* unique = g_dbus_connection_get_unique_name(request->connection);
  if (unique == nullptr || unique[0] != ':') {
    Finish(request, "portal_failed", "Invalid desktop connection.");
    return;
  }
  std::string sender = unique + 1;
  std::replace(sender.begin(), sender.end(), '.', '_');
  request->handle =
      std::string(kPortalPath) + "/request/" + sender + "/" + token;
  SubscribeResponse(request);  // Subscribe before the call to avoid a race.
  request->owner_subscription = g_dbus_connection_signal_subscribe(
      request->connection, "org.freedesktop.DBus", "org.freedesktop.DBus",
      "NameOwnerChanged", "/org/freedesktop/DBus", kPortalName,
      G_DBUS_SIGNAL_FLAGS_NONE, PortalOwnerChanged, Retain(request),
      DeleteRequest);
  request->closed_handler = g_signal_connect_data(
      request->connection, "closed", G_CALLBACK(ConnectionClosed),
      Retain(request), [](gpointer value, GClosure*) { DeleteRequest(value); },
      GConnectFlags(0));

  std::string parent;
#ifdef GDK_WINDOWING_X11
  g_autoptr(GObject) window =
      G_OBJECT(g_weak_ref_get(&request->actions->window));
  if (window != nullptr) {
    GdkWindow* native_window = gtk_widget_get_window(GTK_WIDGET(window));
    if (native_window != nullptr && GDK_IS_X11_WINDOW(native_window)) {
      g_autofree gchar* identifier = g_strdup_printf(
          "x11:%lx",
          static_cast<unsigned long>(gdk_x11_window_get_xid(native_window)));
      parent = identifier;
    }
  }
#endif
  // The empty parent identifier is valid on non-X11 backends.
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  if (!request->reveal) {
    g_variant_builder_add(&options, "{sv}", "writable",
                          g_variant_new_boolean(FALSE));
  }
  g_autoptr(GUnixFDList) descriptors = g_unix_fd_list_new();
  g_autoptr(GError) error = nullptr;
  const int index =
      g_unix_fd_list_append(descriptors, request->file.get(), &error);
  if (index < 0) {
    Finish(request, "open_failed", "The file descriptor could not be shared.");
    return;
  }
  g_dbus_connection_call_with_unix_fd_list(
      request->connection, kPortalName, kPortalPath, kOpenInterface,
      request->reveal ? "OpenDirectory" : "OpenFile",
      g_variant_new("(sh@a{sv})", parent.c_str(), index,
                    g_variant_builder_end(&options)),
      G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, 10000, descriptors,
      request->cancellation, PortalCallFinished, Retain(request));
}

void PortalVersion(GObject* object, GAsyncResult* result, gpointer data) {
  const auto request = Take(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply =
      g_dbus_connection_call_finish(G_DBUS_CONNECTION(object), result, &error);
  if (request->finished) return;
  if (reply == nullptr) {
    if (PortalUnavailable(error)) {
      LocalFallback(request);
    } else {
      Finish(request, "portal_failed", "The desktop portal is unavailable.");
    }
    return;
  }
  g_autoptr(GVariant) version = nullptr;
  g_variant_get(reply, "(v)", &version);
  if (!g_variant_is_of_type(version, G_VARIANT_TYPE_UINT32)) {
    Finish(request, "portal_failed", "Invalid desktop portal capability.");
    return;
  }
  if (g_variant_get_uint32(version) < (request->reveal ? 3u : 2u) ||
      !(g_dbus_connection_get_capabilities(request->connection) &
        G_DBUS_CAPABILITY_FLAGS_UNIX_FD_PASSING)) {
    LocalFallback(request);
    return;
  }
  InvokePortal(request);
}

void SessionBus(GObject*, GAsyncResult* result, gpointer data) {
  const auto request = Take(data);
  g_autoptr(GError) error = nullptr;
  GDBusConnection* connection = g_bus_get_finish(result, &error);
  if (request->finished) {
    g_clear_object(&connection);
    return;
  }
  request->connection = connection;
  if (connection == nullptr) {
    LocalFallback(request);
    return;
  }
  g_dbus_connection_call(connection, kPortalName, kPortalPath,
                         "org.freedesktop.DBus.Properties", "Get",
                         g_variant_new("(ss)", kOpenInterface, "version"),
                         G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 5000,
                         request->cancellation, PortalVersion, Retain(request));
}

void CancelRequests(const std::shared_ptr<Actions>& actions) {
  // Finish removes signal-held references. Retain a local copy while iterating.
  for (const auto& weak : actions->requests) {
    if (const auto request = weak.lock()) {
      Finish(request, "cancelled", "The file action was closed.", true);
    }
  }
  actions->requests.clear();
}

void MethodCall(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  const auto actions = *static_cast<std::shared_ptr<Actions>*>(data);
  const char* method = fl_method_call_get_name(call);
  if (strcmp(method, "dispose") == 0) {
    CancelRequests(actions);
    Respond(call);
    return;
  }
  if (actions->closed) {
    Respond(call, "cancelled", "The native window is closed.");
    return;
  }
  if (strcmp(method, "cacheRoot") == 0) {
    FlValue* arguments = fl_method_call_get_args(call);
    if (arguments != nullptr &&
        fl_value_get_type(arguments) != FL_VALUE_TYPE_NULL) {
      Respond(call, "invalid_path", "The private cache is native-owned.");
      return;
    }
    std::string path;
    FileDescriptor cache(CacheDirectory(&path));
    if (cache.get() < 0) {
      Respond(call, "cache_failed", "The private cache is unavailable.");
      return;
    }
    g_autoptr(FlValue) value = fl_value_new_string(path.c_str());
    Respond(call, nullptr, nullptr, value);
    return;
  }
  const bool reveal = strcmp(method, "revealFile") == 0;
  if (!reveal && strcmp(method, "openFile") != 0) {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(call, response, nullptr);
    return;
  }
  FlValue* arguments = fl_method_call_get_args(call);
  FlValue* path =
      arguments != nullptr && fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP
          ? fl_value_lookup_string(arguments, "path")
          : nullptr;
  if (path == nullptr || fl_value_get_type(path) != FL_VALUE_TYPE_STRING) {
    Respond(call, "invalid_path", "A local file is required.");
    return;
  }
  const std::string local_path = fl_value_get_string(path);
  const int descriptor = OpenLocalFile(local_path, reveal);
  if (descriptor < 0) {
    Respond(call, "invalid_path", "The local file is unavailable.");
    return;
  }
  actions->requests.erase(
      std::remove_if(
          actions->requests.begin(), actions->requests.end(),
          [](const std::weak_ptr<Request>& value) { return value.expired(); }),
      actions->requests.end());
  const auto request =
      std::make_shared<Request>(actions, call, local_path, reveal, descriptor);
  actions->requests.push_back(request);
  g_bus_get(G_BUS_TYPE_SESSION, request->cancellation, SessionBus,
            Retain(request));
}
}  // namespace

void future_notes_register_desktop_file_actions(FlBinaryMessenger* messenger,
                                                GtkWindow* window) {
  const auto actions = std::make_shared<Actions>(window);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      messenger, "future_notes/desktop_linux", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, MethodCall, new std::shared_ptr<Actions>(actions),
      [](gpointer data) {
        std::unique_ptr<std::shared_ptr<Actions>> owner(
            static_cast<std::shared_ptr<Actions>*>(data));
        (*owner)->closed = true;
        CancelRequests(*owner);
      });
  // Keep the channel alive for this window, cancel before its engine goes away.
  g_object_set_data_full(G_OBJECT(window), "future-notes-desktop-linux-channel",
                         g_object_ref(channel), g_object_unref);
  g_signal_connect_data(
      window, "destroy", G_CALLBACK(+[](GtkWidget*, gpointer data) {
        const auto owner = *static_cast<std::shared_ptr<Actions>*>(data);
        owner->closed = true;
        CancelRequests(owner);
      }),
      new std::shared_ptr<Actions>(actions),
      [](gpointer data, GClosure*) {
        delete static_cast<std::shared_ptr<Actions>*>(data);
      },
      GConnectFlags(0));
}
