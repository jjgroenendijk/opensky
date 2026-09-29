// SwiftPM builds a C target only when it has a source file. CFFmpeg has no code of its
// own: it wraps the headers of the vendored ffmpeg and carries its link settings.

#include "CFFmpeg.h"
