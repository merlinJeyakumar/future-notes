#ifndef FUTURE_NOTES_DESKTOP_FILE_ACTIONS_H_
#define FUTURE_NOTES_DESKTOP_FILE_ACTIONS_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// File/cache integration only; does not replace the platform's window frame.
void future_notes_register_desktop_file_actions(FlBinaryMessenger* messenger,
                                                GtkWindow* window);

#endif  // FUTURE_NOTES_DESKTOP_FILE_ACTIONS_H_
