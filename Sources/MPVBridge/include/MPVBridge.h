#ifndef KAZUMI_MPV_BRIDGE_H
#define KAZUMI_MPV_BRIDGE_H
typedef struct KNPlayer KNPlayer;
typedef struct {
    double position;
    double duration;
    int paused;
    int loaded;
    int buffering;
    int audio;
    int video;
    int error;
    int completed;
} KNSnapshot;
int kn_open_library(const char *path);
KNPlayer *kn_create(void);
int kn_render_create(KNPlayer *player);
void kn_render(KNPlayer *player, int width, int height);
void kn_render_destroy(KNPlayer *player);
void kn_destroy(KNPlayer *player);
int kn_load(KNPlayer *player, const char *url, const char *referer, const char *ua, const char *cookies, double start);
KNSnapshot kn_snapshot(KNPlayer *player);
void kn_pause(KNPlayer *player, int pause);
void kn_seek(KNPlayer *player, double position);
void kn_stop(KNPlayer *player);
void kn_volume(KNPlayer *player, double volume);
void kn_speed(KNPlayer *player, double speed);
const char *kn_error_string(int error);
#endif
