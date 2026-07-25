// Umbrella header for the CFFmpeg module: the decode-only slice of the vendored ffmpeg
// build that opensky/Audio uses. Built by tools/vendor-ffmpeg.sh into .vendor/ffmpeg;
// SWIFT_INCLUDE_PATHS puts that prefix's include directory on the header search path.
// See docs/decisions/ffmpeg-audio.md.

#ifndef OPENSKY_CFFMPEG_SHIM_H
#define OPENSKY_CFFMPEG_SHIM_H

#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/channel_layout.h>
#include <libavutil/error.h>
#include <libavutil/mem.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>

#endif /* OPENSKY_CFFMPEG_SHIM_H */
