#include "CRoofSpawn.h"
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

pid_t roof_spawn(const char *const argv[], const char *const envp[], const char *cwd,
                 unsigned short cols, unsigned short rows, int *master_fd) {
    int m = posix_openpt(O_RDWR | O_NOCTTY);
    if (m < 0) return -1;
    if (grantpt(m) != 0 || unlockpt(m) != 0) { close(m); return -1; }
    char slave[128];
    if (ptsname_r(m, slave, sizeof slave) != 0) { close(m); return -1; }
    struct winsize ws = { .ws_row = rows, .ws_col = cols };
    ioctl(m, TIOCSWINSZ, &ws);

    pid_t pid = fork();
    if (pid < 0) { int e = errno; close(m); errno = e; return -1; }
    if (pid == 0) {
        // Child: only async-signal-safe calls from here to execve.
        setsid();
        int s = open(slave, O_RDWR);
        if (s < 0) _exit(126);
        ioctl(s, TIOCSCTTY, 0);
        // The size must be set on the slave side: set on the master before the slave was opened, macOS leaves 0x0
        // (full-screen programs then draw nothing until the first resize).
        ioctl(s, TIOCSWINSZ, &ws);
        dup2(s, 0); dup2(s, 1); dup2(s, 2);
        if (s > 2) close(s);
        close(m);
        sigset_t none; sigemptyset(&none); sigprocmask(SIG_SETMASK, &none, NULL);
        signal(SIGPIPE, SIG_DFL); signal(SIGINT, SIG_DFL); signal(SIGQUIT, SIG_DFL);
        signal(SIGCHLD, SIG_DFL); signal(SIGHUP, SIG_DFL); signal(SIGTERM, SIG_DFL);
        if (cwd && cwd[0]) chdir(cwd);
        execve(argv[0], (char *const *)argv, (char *const *)envp);
        _exit(127);
    }
    fcntl(m, F_SETFL, fcntl(m, F_GETFL) | O_NONBLOCK);
    fcntl(m, F_SETFD, FD_CLOEXEC);
    *master_fd = m;
    return pid;
}

int roof_set_winsize(int fd, unsigned short cols, unsigned short rows) {
    struct winsize ws = { .ws_row = rows, .ws_col = cols };
    return ioctl(fd, TIOCSWINSZ, &ws);
}

pid_t roof_foreground_pgrp(int fd) { return tcgetpgrp(fd); }

static struct termios saved;
static int have_saved = 0;

int roof_make_raw(int fd) {
    struct termios t;
    if (tcgetattr(fd, &t) != 0) return -1;
    saved = t; have_saved = 1;
    cfmakeraw(&t);
    return tcsetattr(fd, TCSANOW, &t);
}

void roof_restore_tty(int fd) { if (have_saved) tcsetattr(fd, TCSANOW, &saved); }

int roof_get_winsize(int fd, unsigned short *cols, unsigned short *rows) {
    struct winsize ws;
    if (ioctl(fd, TIOCGWINSZ, &ws) != 0) return -1;
    *cols = ws.ws_col; *rows = ws.ws_row;
    return 0;
}
