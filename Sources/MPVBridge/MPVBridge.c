#include "MPVBridge.h"
#include "vendor/client.h"
#include "vendor/render.h"
#include "vendor/render_gl.h"
#include <stdlib.h>
#include <stdio.h>
#include <dlfcn.h>

// Runtime loading keeps the Swift core build independent of a local libmpv.
// App bundles prepared by scripts/package-macos.sh contain the media frameworks.
static void *library;
static mpv_handle *(*p_create)(void);
static int (*p_initialize)(mpv_handle *);
static int (*p_option)(mpv_handle *, const char *, const char *);
static int (*p_property_string)(mpv_handle *, const char *, const char *);
static int (*p_property)(mpv_handle *, const char *, mpv_format, void *);
static int (*p_get)(mpv_handle *, const char *, mpv_format, void *);
static int (*p_command)(mpv_handle *, const char **);
static mpv_event *(*p_event)(mpv_handle *, double);
static void (*p_destroy)(mpv_handle *);
static const char *(*p_error)(int);
static int (*p_render_create)(mpv_render_context **, mpv_handle *, mpv_render_param *);
static uint64_t (*p_render_update)(mpv_render_context *);
static int (*p_render)(mpv_render_context *, mpv_render_param *);
static void (*p_swap)(mpv_render_context *);
static void (*p_render_free)(mpv_render_context *);
int kn_open_library(const char *path) {
    if (library) return 1;
    void *candidate = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!candidate) return 0;
#define LOAD(field, name) do { *(void **)(&field) = dlsym(candidate, name); if (!field) { dlclose(candidate); return 0; } } while (0)
    LOAD(p_create, "mpv_create"); LOAD(p_initialize, "mpv_initialize");
    LOAD(p_option, "mpv_set_option_string"); LOAD(p_property_string, "mpv_set_property_string");
    LOAD(p_property, "mpv_set_property"); LOAD(p_get, "mpv_get_property");
    LOAD(p_command, "mpv_command"); LOAD(p_event, "mpv_wait_event");
    LOAD(p_destroy, "mpv_terminate_destroy"); LOAD(p_error, "mpv_error_string");
    LOAD(p_render_create, "mpv_render_context_create"); LOAD(p_render_update, "mpv_render_context_update");
    LOAD(p_render, "mpv_render_context_render"); LOAD(p_swap, "mpv_render_context_report_swap");
    LOAD(p_render_free, "mpv_render_context_free");
#undef LOAD
    library = candidate;
    return 1;
}
#define mpv_create p_create
#define mpv_initialize p_initialize
#define mpv_set_option_string p_option
#define mpv_set_property_string p_property_string
#define mpv_set_property p_property
#define mpv_get_property p_get
#define mpv_command p_command
#define mpv_wait_event p_event
#define mpv_terminate_destroy p_destroy
#define mpv_error_string p_error
#define mpv_render_context_create p_render_create
#define mpv_render_context_update p_render_update
#define mpv_render_context_render p_render
#define mpv_render_context_report_swap p_swap
#define mpv_render_context_free p_render_free

struct KNPlayer { mpv_handle *handle; mpv_render_context *render; int loaded; int error; int completed; };
static void *get_proc(void *context, const char *name) { return dlsym(RTLD_DEFAULT, name); }
KNPlayer *kn_create(void) {
    if (!library) return NULL;
    KNPlayer *p = calloc(1, sizeof(KNPlayer));
    if (!p) return NULL;
    p->handle = mpv_create();
    if (!p->handle) { free(p); return NULL; }
    mpv_set_option_string(p->handle, "vo", "libmpv");
    mpv_set_option_string(p->handle, "hwdec", "auto-safe");
    mpv_set_option_string(p->handle, "keep-open", "yes");
    mpv_set_option_string(p->handle, "terminal", "no");
    mpv_set_option_string(p->handle, "input-default-bindings", "no");
    mpv_set_option_string(p->handle, "idle", "yes");
    mpv_set_option_string(p->handle, "network-timeout", "25");
    if (mpv_initialize(p->handle) < 0) { mpv_terminate_destroy(p->handle); free(p); return NULL; }
    return p;
}
int kn_render_create(KNPlayer *p) {
    if (!p) return -1;
    if (p->render) return 0;
    mpv_opengl_init_params gl = {.get_proc_address = get_proc};
    mpv_render_param params[] = {{MPV_RENDER_PARAM_API_TYPE, MPV_RENDER_API_TYPE_OPENGL},
        {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl}, {0}};
    return mpv_render_context_create(&p->render, p->handle, params);
}
void kn_render(KNPlayer *p, int width, int height) {
    if (!p || !p->render || width <= 0 || height <= 0) return;
    mpv_opengl_fbo fbo = {.fbo = 0, .w = width, .h = height, .internal_format = 0};
    int flip = 1;
    mpv_render_param params[] = {{MPV_RENDER_PARAM_OPENGL_FBO, &fbo}, {MPV_RENDER_PARAM_FLIP_Y, &flip}, {0}};
    mpv_render_context_update(p->render);
    mpv_render_context_render(p->render, params);
    mpv_render_context_report_swap(p->render);
}
void kn_render_destroy(KNPlayer *p) {
    if (p && p->render) { mpv_render_context_free(p->render); p->render = NULL; }
}
void kn_destroy(KNPlayer *p) {
    if (!p) return;
    kn_render_destroy(p);
    mpv_terminate_destroy(p->handle);
    free(p);
}
int kn_load(KNPlayer *p, const char *url, const char *referer, const char *ua, const char *cookies, double start) {
    if (!p) return -1;
    // Drain old events before changing identity so old FILE_LOADED cannot mark
    // a newly requested episode ready or overwrite its resume position.
    while (mpv_wait_event(p->handle, 0)->event_id != MPV_EVENT_NONE) {}
    p->loaded = 0; p->error = 0; p->completed = 0;
    mpv_set_property_string(p->handle, "user-agent", ua);
    mpv_set_property_string(p->handle, "referrer", referer);
    mpv_set_property_string(p->handle, "http-header-fields", cookies);
    char options[96]; snprintf(options, sizeof(options), "start=%.3f", start);
    const char *args[] = {"loadfile", url, "replace", options, NULL};
    int result = mpv_command(p->handle, args);
    if (result < 0) p->error = result;
    int pause = 0; mpv_set_property(p->handle, "pause", MPV_FORMAT_FLAG, &pause);
    return result;
}
KNSnapshot kn_snapshot(KNPlayer *p) {
    KNSnapshot result = {0};
    if (!p) { result.error = -1; return result; }
    mpv_event *event;
    while ((event = mpv_wait_event(p->handle, 0))->event_id != MPV_EVENT_NONE) {
        if (event->event_id == MPV_EVENT_START_FILE) p->loaded = 0;
        if (event->event_id == MPV_EVENT_FILE_LOADED) p->loaded = 1;
        if (event->event_id == MPV_EVENT_END_FILE) {
            mpv_event_end_file *end = event->data;
            if (end->reason == MPV_END_FILE_REASON_ERROR) { p->error = end->error; p->loaded = 0; }
        }
    }
    mpv_get_property(p->handle, "eof-reached", MPV_FORMAT_FLAG, &p->completed);
    result.completed = p->completed;
    result.loaded = p->loaded; result.error = p->error;
    mpv_get_property(p->handle, "time-pos", MPV_FORMAT_DOUBLE, &result.position);
    mpv_get_property(p->handle, "duration", MPV_FORMAT_DOUBLE, &result.duration);
    mpv_get_property(p->handle, "pause", MPV_FORMAT_FLAG, &result.paused);
    mpv_get_property(p->handle, "paused-for-cache", MPV_FORMAT_FLAG, &result.buffering);
    int64_t audio = 0, video = 0;
    mpv_get_property(p->handle, "aid", MPV_FORMAT_INT64, &audio);
    mpv_get_property(p->handle, "vid", MPV_FORMAT_INT64, &video);
    result.audio = audio > 0; result.video = video > 0;
    return result;
}
void kn_pause(KNPlayer *p, int value) { if (p) mpv_set_property(p->handle, "pause", MPV_FORMAT_FLAG, &value); }
void kn_seek(KNPlayer *p, double value) {
    if (!p) return;
    char position[64]; snprintf(position, sizeof(position), "%.3f", value);
    const char *args[] = {"seek", position, "absolute+exact", NULL}; mpv_command(p->handle, args);
}
void kn_stop(KNPlayer *p) { if (p) { const char *args[] = {"stop", NULL}; mpv_command(p->handle, args); p->loaded = 0; } }
void kn_volume(KNPlayer *p, double value) { if (p) mpv_set_property(p->handle, "volume", MPV_FORMAT_DOUBLE, &value); }
void kn_speed(KNPlayer *p, double value) { if (p) mpv_set_property(p->handle, "speed", MPV_FORMAT_DOUBLE, &value); }
const char *kn_error_string(int error) { return library ? mpv_error_string(error) : "libmpv unavailable"; }
