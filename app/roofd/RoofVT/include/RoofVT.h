// RoofVT: a headless terminal per roofd session, over Ghostty's own VT core (ghostty-vt, v1.3.1).
// roofd feeds it every byte a session prints; it answers "what is on screen" (read, status) and rebuilds the screen
// for a terminal that attaches later (redraw). Buffers returned through `out` are freed with rvt_bytes_free.
#ifndef ROOFVT_H
#define ROOFVT_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct rvt rvt_t;

rvt_t   *rvt_new(uint16_t cols, uint16_t rows, size_t max_scrollback_bytes);
void     rvt_free(rvt_t *t);
/// Apply output to the state. Queries are ignored (state only, no replies).
void     rvt_feed(rvt_t *t, const uint8_t *bytes, size_t len);
/// Ghostty's reflow.
bool     rvt_resize(rvt_t *t, uint16_t cols, uint16_t rows);
/// VT bytes that rebuild this state (history, both screens, modes, cursor) in a fresh terminal of the same size.
size_t   rvt_redraw(rvt_t *t, uint8_t **out);
/// Plain text of the last `last_lines` lines of history + screen (0 = all).
size_t   rvt_text(rvt_t *t, uint32_t last_lines, uint8_t **out);
/// A DEC private (`ansi` false, e.g. 2004, 1049, 1000) or ANSI mode.
bool     rvt_mode(rvt_t *t, uint16_t mode, bool ansi);
size_t   rvt_title(rvt_t *t, uint8_t **out);
size_t   rvt_pwd(rvt_t *t, uint8_t **out);
/// Cursor position (0-based) on the active screen; returns true on the alternate screen.
bool     rvt_cursor(rvt_t *t, uint16_t *x, uint16_t *y);
/// Device-attribute / cursor-position queries seen since the last call (bit 0: DA1, bit 1: DSR 6, bit 2: DSR 5).
uint32_t rvt_take_queries(rvt_t *t);
void     rvt_bytes_free(uint8_t *bytes, size_t len);

#endif
