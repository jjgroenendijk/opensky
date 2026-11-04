#pragma once

#include <string>
#include <string_view>

namespace bridge {
// `watch <seconds> <variable>...` records the picked reference's graph variables each frame,
// its position, and every animation event it sends, into `watch.jsonl`.
void StartWatch(std::string_view arguments, RE::TESObjectREFR *reference);
// Called once per frame on the main thread while a watch runs.
void SampleWatch();
bool IsWatching();
} // namespace bridge
