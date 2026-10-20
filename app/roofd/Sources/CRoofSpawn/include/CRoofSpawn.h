// The one thing roofd cannot do in Swift: run code between fork() and execve() (T14 §6).
#ifndef CROOFSPAWN_H
#define CROOFSPAWN_H
#include <sys/types.h>

/// Start `argv` (argv[0] is a path) in `cwd` with exactly `envp`, as the leader of a new session whose
/// controlling terminal is a fresh PTY of `cols` x `rows`. Returns the child's pid and sets *master_fd
/// (non-blocking, close-on-exec), or -1 with errno set.
pid_t roof_spawn(const char *const argv[], const char *const envp[], const char *cwd,
                 unsigned short cols, unsigned short rows, int *master_fd);

/// Set the PTY size (the kernel sends SIGWINCH to the foreground process group).
int roof_set_winsize(int fd, unsigned short cols, unsigned short rows);
/// The foreground process group of the PTY, or -1.
pid_t roof_foreground_pgrp(int fd);
/// Raw mode on a terminal fd; returns 0 and saves the previous settings for roof_restore_tty.
int roof_make_raw(int fd);
void roof_restore_tty(int fd);
/// Current size of a terminal fd; returns 0 on success.
int roof_get_winsize(int fd, unsigned short *cols, unsigned short *rows);

#endif
