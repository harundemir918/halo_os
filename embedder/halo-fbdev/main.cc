// halo-fbdev-embedder: runs one Flutter app full screen with the engine's
// software renderer and feeds it touch or pointer input from evdev.
//
// It shows frames through DRM/KMS (a dumb buffer, flushed on every frame) and
// falls back to the fbdev framebuffer. The fbdev emulation only flushes every
// 50 ms (drm_fb_helper sets HZ / 20), which caps what is visible at 20 Hz.
//
// Interim (ROADMAP Phase 1, D-016): it lets the shell run on the device before
// the compositor and the Wayland embedder exist (Phase 3), and needs no GPU
// stack. Usage:
//
//   halo-fbdev-embedder <flutter_assets dir> <icudtl.dat>

#include <dirent.h>
#include <drm/drm.h>
#include <drm/drm_fourcc.h>
#include <drm/drm_mode.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <functional>
#include <mutex>
#include <queue>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "flutter_embedder.h"

namespace {

// carbon, #0C0C0B, as B, G, R, X.
constexpr uint8_t kGround[4] = {0x0B, 0x0C, 0x0C, 0xFF};

// ---------------------------------------------------------------------------
// Tasks on the platform thread (the main thread).

class TaskQueue {
 public:
  void Post(uint64_t when_nanos, std::function<void()> fn) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      queue_.push(Task{when_nanos, next_seq_++, std::move(fn)});
    }
    cv_.notify_one();
  }

  void Stop() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      stop_ = true;
    }
    cv_.notify_all();
  }

  // Runs due tasks until Stop().
  void Loop() {
    std::unique_lock<std::mutex> lock(mutex_);
    while (!stop_) {
      if (queue_.empty()) {
        cv_.wait(lock);
        continue;
      }
      const uint64_t now = FlutterEngineGetCurrentTime();
      const uint64_t due = queue_.top().when;
      if (due > now) {
        cv_.wait_for(lock, std::chrono::nanoseconds(due - now));
        continue;
      }
      auto fn = queue_.top().fn;
      queue_.pop();
      lock.unlock();
      fn();
      lock.lock();
    }
  }

 private:
  struct Task {
    uint64_t when;
    uint64_t seq;  // breaks ties so tasks due together run in posting order
    std::function<void()> fn;
    // std::priority_queue is a max-heap: the earliest task must compare last.
    // It is not stable, so without `seq` pointer events due at the same time
    // could be reordered (an Up before the last Move).
    bool operator<(const Task& other) const {
      if (when != other.when) return when > other.when;
      return seq > other.seq;
    }
  };

  std::mutex mutex_;
  std::condition_variable cv_;
  std::priority_queue<Task> queue_;
  bool stop_ = false;
  uint64_t next_seq_ = 0;
};

// ---------------------------------------------------------------------------
// Framebuffer. Geometry comes from sysfs, so no ioctl is needed.

struct Framebuffer {
  uint8_t* pixels = nullptr;
  size_t width = 0;
  size_t height = 0;
  size_t stride = 0;
  int drm_fd = -1;       // >= 0 when frames go out through DRM
  uint32_t drm_fb = 0;   // the DRM framebuffer to flush
};

template <typename T>
uint64_t Ptr(std::vector<T>& v) {
  return reinterpret_cast<uintptr_t>(v.data());
}

// drm_mode_get_connector::connection for a connected output (libdrm's
// DRM_MODE_CONNECTED; the kernel UAPI headers do not name it).
constexpr uint32_t kConnected = 1;

// Sets up a KMS dumb buffer on the first connected connector and scans it out.
// Raw ioctls from the kernel's UAPI headers: no libdrm.
bool OpenDrm(Framebuffer* fb) {
  const int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
  if (fd < 0) return false;

  drm_mode_card_res res = {};
  if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res) != 0) { close(fd); return false; }
  std::vector<uint32_t> crtcs(res.count_crtcs), conns(res.count_connectors),
      encs(res.count_encoders), fbs(res.count_fbs);
  res.crtc_id_ptr = Ptr(crtcs);
  res.connector_id_ptr = Ptr(conns);
  res.encoder_id_ptr = Ptr(encs);
  res.fb_id_ptr = Ptr(fbs);
  if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res) != 0) { close(fd); return false; }

  for (uint32_t conn_id : conns) {
    drm_mode_get_connector c = {};
    c.connector_id = conn_id;
    if (ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) != 0) continue;
    std::vector<drm_mode_modeinfo> modes(c.count_modes);
    std::vector<uint32_t> encoders(c.count_encoders), props(c.count_props);
    std::vector<uint64_t> prop_values(c.count_props);
    c.modes_ptr = Ptr(modes);
    c.encoders_ptr = Ptr(encoders);
    c.props_ptr = Ptr(props);
    c.prop_values_ptr = Ptr(prop_values);
    if (ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) != 0) continue;
    if (c.connection != kConnected || modes.empty()) continue;

    // The CRTC: the one already driving this connector, else the first the
    // encoder can use.
    uint32_t crtc_id = 0;
    drm_mode_get_encoder e = {};
    e.encoder_id = c.encoder_id != 0 ? c.encoder_id
                                     : (encoders.empty() ? 0 : encoders[0]);
    if (e.encoder_id != 0 && ioctl(fd, DRM_IOCTL_MODE_GETENCODER, &e) == 0) {
      crtc_id = e.crtc_id;
      for (size_t i = 0; crtc_id == 0 && i < crtcs.size(); ++i) {
        if (e.possible_crtcs & (1u << i)) crtc_id = crtcs[i];
      }
    }
    if (crtc_id == 0) continue;

    const drm_mode_modeinfo mode = modes[0];  // the preferred mode is first
    drm_mode_create_dumb cd = {};
    cd.width = mode.hdisplay;
    cd.height = mode.vdisplay;
    cd.bpp = 32;
    if (ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &cd) != 0) continue;

    drm_mode_fb_cmd2 f = {};
    f.width = cd.width;
    f.height = cd.height;
    f.pixel_format = DRM_FORMAT_XRGB8888;
    f.handles[0] = cd.handle;
    f.pitches[0] = cd.pitch;
    if (ioctl(fd, DRM_IOCTL_MODE_ADDFB2, &f) != 0) continue;

    drm_mode_map_dumb md = {};
    md.handle = cd.handle;
    if (ioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &md) != 0) continue;
    void* map = mmap(nullptr, cd.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd,
                     static_cast<off_t>(md.offset));
    if (map == MAP_FAILED) continue;

    drm_mode_crtc set = {};
    set.crtc_id = crtc_id;
    set.fb_id = f.fb_id;
    set.set_connectors_ptr = reinterpret_cast<uintptr_t>(&conn_id);
    set.count_connectors = 1;
    set.mode_valid = 1;
    set.mode = mode;
    if (ioctl(fd, DRM_IOCTL_MODE_SETCRTC, &set) != 0) {
      std::perror("halo-fbdev: DRM SETCRTC");
      munmap(map, cd.size);
      continue;
    }

    fb->pixels = static_cast<uint8_t*>(map);
    fb->width = cd.width;
    fb->height = cd.height;
    fb->stride = cd.pitch;
    fb->drm_fd = fd;
    fb->drm_fb = f.fb_id;
    std::printf("halo-fbdev: DRM card0, connector %u, mode %ux%u\n", conn_id,
                cd.width, cd.height);
    return true;
  }
  close(fd);
  return false;
}

// Pushes the dumb buffer to the display now, not on the fbdev timer.
void Flush(const Framebuffer& fb) {
  if (fb.drm_fd < 0) return;
  drm_mode_fb_dirty_cmd dirty = {};
  dirty.fb_id = fb.drm_fb;
  ioctl(fb.drm_fd, DRM_IOCTL_MODE_DIRTYFB, &dirty);
}

std::string ReadFile(const std::string& path) {
  std::ifstream in(path);
  std::stringstream ss;
  ss << in.rdbuf();
  return ss.str();
}

bool OpenFbdev(Framebuffer* fb) {
  const std::string sysfs = "/sys/class/graphics/fb0/";
  size_t w = 0, h = 0;
  if (std::sscanf(ReadFile(sysfs + "virtual_size").c_str(), "%zu,%zu", &w,
                  &h) != 2 ||
      w == 0 || h == 0) {
    std::fprintf(stderr, "halo-fbdev: cannot read %svirtual_size\n",
                 sysfs.c_str());
    return false;
  }
  const int bpp = std::atoi(ReadFile(sysfs + "bits_per_pixel").c_str());
  const size_t stride =
      std::strtoul(ReadFile(sysfs + "stride").c_str(), nullptr, 10);
  if (bpp != 32 || stride < w * 4) {
    std::fprintf(stderr, "halo-fbdev: need a 32-bit framebuffer (bpp=%d)\n",
                 bpp);
    return false;
  }
  const int fd = open("/dev/fb0", O_RDWR);
  if (fd < 0) {
    std::perror("halo-fbdev: open /dev/fb0");
    return false;
  }
  void* map =
      mmap(nullptr, stride * h, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  close(fd);
  if (map == MAP_FAILED) {
    std::perror("halo-fbdev: mmap");
    return false;
  }
  fb->pixels = static_cast<uint8_t*>(map);
  fb->width = w;
  fb->height = h;
  fb->stride = stride;
  return true;
}

bool OpenFramebuffer(Framebuffer* fb) {
  if (std::getenv("HALO_FORCE_FBDEV") == nullptr && OpenDrm(fb)) return true;
  std::printf("halo-fbdev: using the fbdev framebuffer\n");
  return OpenFbdev(fb);
}

void Clear(const Framebuffer& fb) {
  for (size_t y = 0; y < fb.height; ++y) {
    uint8_t* row = fb.pixels + y * fb.stride;
    for (size_t x = 0; x < fb.width; ++x) std::memcpy(row + x * 4, kGround, 4);
  }
}

// ---------------------------------------------------------------------------
// State shared with the engine callbacks.

struct State {
  FlutterEngine engine = nullptr;
  Framebuffer fb;
  TaskQueue tasks;
  std::thread::id main_thread = std::this_thread::get_id();
  std::atomic<bool> quit{false};
  std::atomic<uint64_t> frames{0};
  std::atomic<uint64_t> present_micros{0};  // time spent copying and flushing
  uint64_t vsync_period_nanos = 16666666;  // 60 Hz; HALO_HZ overrides
};

State g;

bool RunsOnCurrentThread(void*) {
  return std::this_thread::get_id() == g.main_thread;
}

void PostTask(FlutterTask task, uint64_t target_nanos, void*) {
  g.tasks.Post(target_nanos, [task] { FlutterEngineRunTask(g.engine, &task); });
}

// Native32 is BGRA on little-endian Linux, which is the framebuffer's
// XRGB8888 byte order, so rows copy straight across.
bool Present(void*, const void* allocation, size_t row_bytes, size_t height) {
  const auto* src = static_cast<const uint8_t*>(allocation);
  const size_t rows = height < g.fb.height ? height : g.fb.height;
  const size_t bytes = row_bytes < g.fb.width * 4 ? row_bytes : g.fb.width * 4;
  const auto t0 = std::chrono::steady_clock::now();
  for (size_t y = 0; y < rows; ++y) {
    std::memcpy(g.fb.pixels + y * g.fb.stride, src + y * row_bytes, bytes);
  }
  Flush(g.fb);
  const auto us = std::chrono::duration_cast<std::chrono::microseconds>(
                      std::chrono::steady_clock::now() - t0)
                      .count();
  g.present_micros += static_cast<uint64_t>(us);
  if (++g.frames == 1) {
    std::printf("halo-fbdev: first frame\n");
    std::fflush(stdout);
  }
  return true;
}

// The engine asks for a vsync and waits for FlutterEngineOnVsync(baton). We
// answer on a fixed grid of g.vsync_period_nanos, so frames are paced at the
// configured refresh rate (the engine's own fallback timer is 60 Hz).
void OnVsync(void*, intptr_t baton) {
  const uint64_t period = g.vsync_period_nanos;
  const uint64_t now = FlutterEngineGetCurrentTime();
  const uint64_t next = (now / period + 1) * period;
  g.tasks.Post(next, [baton, next, period] {
    FlutterEngineOnVsync(g.engine, baton, next, next + period);
  });
}

void Log(const char* tag, const char* message, void*) {
  std::printf("[%s] %s\n", tag, message);
  std::fflush(stdout);
}

// ---------------------------------------------------------------------------
// Input: absolute pointers (the virtio tablet, touchscreens) from evdev.

struct Device {
  int fd = -1;
  input_absinfo x{};
  input_absinfo y{};
  int cur_x = 0;
  int cur_y = 0;
  bool want_down = false;  // button state reported by the device
  bool down = false;       // what the engine has been told
  bool added = false;      // kAdd sent
  bool moved = false;
};

bool HasBit(const uint8_t* bits, int bit) {
  return bits[bit / 8] & (1 << (bit % 8));
}

std::vector<Device> OpenInputDevices() {
  std::vector<Device> found;
  DIR* dir = opendir("/dev/input");
  if (!dir) return found;
  while (const dirent* e = readdir(dir)) {
    if (std::strncmp(e->d_name, "event", 5) != 0) continue;
    const std::string path = std::string("/dev/input/") + e->d_name;
    const int fd = open(path.c_str(), O_RDONLY | O_NONBLOCK);
    if (fd < 0) continue;
    uint8_t types[(EV_MAX + 8) / 8] = {};
    uint8_t abs[(ABS_MAX + 8) / 8] = {};
    ioctl(fd, EVIOCGBIT(0, sizeof(types)), types);
    ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(abs)), abs);
    Device d;
    if (HasBit(types, EV_ABS) && HasBit(abs, ABS_X) && HasBit(abs, ABS_Y) &&
        ioctl(fd, EVIOCGABS(ABS_X), &d.x) == 0 &&
        ioctl(fd, EVIOCGABS(ABS_Y), &d.y) == 0 && d.x.maximum > d.x.minimum &&
        d.y.maximum > d.y.minimum) {
      d.fd = fd;
      char name[128] = "?";
      ioctl(fd, EVIOCGNAME(sizeof(name)), name);
      std::printf("halo-fbdev: input %s (%s)\n", path.c_str(), name);
      found.push_back(d);
    } else {
      close(fd);
    }
  }
  closedir(dir);
  std::fflush(stdout);
  return found;
}

void SendPointer(FlutterPointerPhase phase, double x, double y) {
  FlutterPointerEvent ev = {};
  ev.struct_size = sizeof(ev);
  ev.phase = phase;
  ev.timestamp = FlutterEngineGetCurrentTime() / 1000;  // microseconds
  ev.x = x;
  ev.y = y;
  ev.device = 1;
  ev.device_kind = kFlutterPointerDeviceKindTouch;
  ev.view_id = 0;
  const char* trace = std::getenv("HALO_TRACE");
  if (trace != nullptr && *trace != '\0') {
    std::printf("halo-fbdev: pointer phase=%d x=%.0f y=%.0f\n",
                static_cast<int>(phase), x, y);
    std::fflush(stdout);
  }
  g.tasks.Post(0, [ev] { FlutterEngineSendPointerEvent(g.engine, &ev, 1); });
}

// Turns one evdev report (SYN_REPORT) into engine pointer events.
void Report(Device& d) {
  const double px = static_cast<double>(d.cur_x - d.x.minimum) *
                    static_cast<double>(g.fb.width - 1) /
                    static_cast<double>(d.x.maximum - d.x.minimum);
  const double py = static_cast<double>(d.cur_y - d.y.minimum) *
                    static_cast<double>(g.fb.height - 1) /
                    static_cast<double>(d.y.maximum - d.y.minimum);
  if (!d.added) {
    SendPointer(kAdd, px, py);
    d.added = true;
  }
  if (d.want_down && !d.down) {
    SendPointer(kDown, px, py);
    d.down = true;
  } else if (!d.want_down && d.down) {
    SendPointer(kUp, px, py);
    d.down = false;
  } else if (d.down && d.moved) {
    SendPointer(kMove, px, py);
  }
  d.moved = false;
}

void InputLoop(std::vector<Device> devices) {
  std::vector<pollfd> fds;
  for (const Device& d : devices) fds.push_back({d.fd, POLLIN, 0});
  while (!g.quit) {
    if (poll(fds.data(), fds.size(), 200) <= 0) continue;
    for (size_t i = 0; i < devices.size(); ++i) {
      if (!(fds[i].revents & POLLIN)) continue;
      Device& d = devices[i];
      input_event ev;
      while (read(d.fd, &ev, sizeof(ev)) == static_cast<ssize_t>(sizeof(ev))) {
        if (ev.type == EV_ABS && ev.code == ABS_X) {
          d.cur_x = ev.value;
          d.moved = true;
        } else if (ev.type == EV_ABS && ev.code == ABS_Y) {
          d.cur_y = ev.value;
          d.moved = true;
        } else if (ev.type == EV_KEY &&
                   (ev.code == BTN_TOUCH || ev.code == BTN_LEFT)) {
          d.want_down = ev.value != 0;
        } else if (ev.type == EV_SYN && ev.code == SYN_REPORT) {
          Report(d);
        }
      }
    }
  }
  for (const Device& d : devices) close(d.fd);
}

void OnSignal(int) { g.quit = true; }

}  // namespace

int main(int argc, char** argv) {
  if (argc != 3) {
    std::fprintf(stderr, "usage: %s <flutter_assets dir> <icudtl.dat>\n",
                 argv[0]);
    return 2;
  }
  if (const char* hz = std::getenv("HALO_HZ")) {
    const int rate = std::atoi(hz);
    if (rate >= 1 && rate <= 360) {
      g.vsync_period_nanos = 1000000000ull / static_cast<uint64_t>(rate);
    }
  }
  std::printf("halo-fbdev: pacing frames at %llu Hz\n",
              static_cast<unsigned long long>(1000000000ull / g.vsync_period_nanos));
  std::signal(SIGTERM, OnSignal);
  std::signal(SIGINT, OnSignal);

  if (!OpenFramebuffer(&g.fb)) return 1;
  Clear(g.fb);
  std::printf("halo-fbdev: display %zux%zu\n", g.fb.width, g.fb.height);

  FlutterRendererConfig config = {};
  config.type = kSoftware;
  config.software.struct_size = sizeof(config.software);
  config.software.surface_present_callback = Present;

  FlutterTaskRunnerDescription platform = {};
  platform.struct_size = sizeof(platform);
  platform.runs_task_on_current_thread_callback = RunsOnCurrentThread;
  platform.post_task_callback = PostTask;
  platform.identifier = 1;

  FlutterCustomTaskRunners runners = {};
  runners.struct_size = sizeof(runners);
  runners.platform_task_runner = &platform;

  const char* engine_argv[] = {"halo-fbdev-embedder"};
  FlutterProjectArgs args = {};
  args.struct_size = sizeof(args);
  args.assets_path = argv[1];
  args.icu_data_path = argv[2];
  args.custom_task_runners = &runners;
  args.command_line_argc = 1;
  args.command_line_argv = engine_argv;
  args.log_message_callback = Log;
  args.vsync_callback = OnVsync;
  args.log_tag = "halo";

  const FlutterEngineResult result =
      FlutterEngineRun(FLUTTER_ENGINE_VERSION, &config, &args, nullptr,
                       &g.engine);
  if (result != kSuccess || g.engine == nullptr) {
    std::fprintf(stderr, "halo-fbdev: FlutterEngineRun failed (%d)\n",
                 static_cast<int>(result));
    return 1;
  }

  FlutterWindowMetricsEvent metrics = {};
  metrics.struct_size = sizeof(metrics);
  metrics.width = g.fb.width;
  metrics.height = g.fb.height;
  // The design frame is 390 logical px wide; a 780 px display is ratio 2.
  metrics.pixel_ratio = static_cast<double>(g.fb.width) / 390.0;
  metrics.view_id = 0;
  FlutterEngineSendWindowMetricsEvent(g.engine, &metrics);

  std::vector<Device> devices = OpenInputDevices();
  std::thread input;
  if (devices.empty()) {
    std::printf("halo-fbdev: no pointer device, running without input\n");
  } else {
    input = std::thread(InputLoop, std::move(devices));
  }

  // A signal handler cannot take the queue's mutex, so a watcher stops it.
  std::thread watcher([] {
    while (!g.quit) std::this_thread::sleep_for(std::chrono::milliseconds(100));
    g.tasks.Stop();
  });

  // With HALO_TRACE set, report presented frames per second while animating.
  std::thread fps([] {
    const char* trace = std::getenv("HALO_TRACE");
    if (trace == nullptr || *trace == '\0') return;
    uint64_t last = 0, last_micros = 0;
    while (!g.quit) {
      std::this_thread::sleep_for(std::chrono::seconds(1));
      const uint64_t now = g.frames;
      const uint64_t micros = g.present_micros;
      if (now != last) {
        std::printf("halo-fbdev: %llu fps, present %llu us/frame\n",
                    static_cast<unsigned long long>(now - last),
                    static_cast<unsigned long long>((micros - last_micros) /
                                                    (now - last)));
        std::fflush(stdout);
      }
      last = now;
      last_micros = micros;
    }
  });

  std::printf("halo-fbdev: running\n");
  std::fflush(stdout);
  g.tasks.Loop();

  g.quit = true;
  if (input.joinable()) input.join();
  watcher.join();
  fps.join();
  FlutterEngineShutdown(g.engine);
  return 0;
}
