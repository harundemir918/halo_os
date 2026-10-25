// halo-fbdev-embedder: runs one Flutter app full screen on the Linux
// framebuffer, with the engine's software renderer, and feeds it touch or
// pointer input from evdev.
//
// Interim (ROADMAP Phase 1, D-016): it lets the shell run on the device before
// the compositor and the Wayland embedder exist (Phase 3), and needs no GPU
// stack. Usage:
//
//   halo-fbdev-embedder <flutter_assets dir> <icudtl.dat>

#include <dirent.h>
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
};

std::string ReadFile(const std::string& path) {
  std::ifstream in(path);
  std::stringstream ss;
  ss << in.rdbuf();
  return ss.str();
}

bool OpenFramebuffer(Framebuffer* fb) {
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
  for (size_t y = 0; y < rows; ++y) {
    std::memcpy(g.fb.pixels + y * g.fb.stride, src + y * row_bytes, bytes);
  }
  if (++g.frames == 1) {
    std::printf("halo-fbdev: first frame\n");
    std::fflush(stdout);
  }
  return true;
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

  std::printf("halo-fbdev: running\n");
  std::fflush(stdout);
  g.tasks.Loop();

  g.quit = true;
  if (input.joinable()) input.join();
  watcher.join();
  FlutterEngineShutdown(g.engine);
  return 0;
}
