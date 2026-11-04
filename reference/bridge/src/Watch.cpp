#include "Watch.h"

#include "Channel.h"

#include <charconv>
#include <chrono>
#include <cmath>
#include <format>
#include <mutex>
#include <vector>

namespace bridge {
namespace {
using Clock = std::chrono::steady_clock;

std::string Number(float value)
{
    return std::isfinite(value) ? std::format("{}", value) : "null";
}

std::string Escaped(std::string_view text)
{
    std::string escaped;
    for (const char character : text) {
        if (character == '"' || character == '\\') {
            escaped += '\\';
        }
        escaped += static_cast<unsigned char>(character) >= 0x20 ? character : ' ';
    }
    return escaped;
}

struct Recording
{
    RE::ObjectRefHandle target;
    std::vector<std::string> variables;
    Clock::time_point start;
    Clock::time_point end;
    std::string lines;
};

std::mutex recordingLock;
Recording recording;
bool watching = false;

double Seconds()
{
    return std::chrono::duration<double>(Clock::now() - recording.start).count();
}

// Animation events can arrive from the animation worker threads, so the buffer is locked.
class EventLog final : public RE::BSTEventSink<RE::BSAnimationGraphEvent> {
  public:
    RE::BSEventNotifyControl ProcessEvent(
        const RE::BSAnimationGraphEvent *event,
        RE::BSTEventSource<RE::BSAnimationGraphEvent> *) override
    {
        if (!event) {
            return RE::BSEventNotifyControl::kContinue;
        }
        std::scoped_lock lock(recordingLock);
        if (watching) {
            recording.lines += std::format(
                "{{\"t\":{:.4f},\"event\":\"{}\",\"payload\":\"{}\"}}\n", Seconds(),
                Escaped(event->tag.c_str()), Escaped(event->payload.c_str()));
        }
        return RE::BSEventNotifyControl::kContinue;
    }
};

EventLog eventLog;

std::string Sample(RE::TESObjectREFR *reference)
{
    const auto position = reference->GetPosition();
    auto line = std::format(
        "{{\"t\":{:.4f},\"dt\":{},\"position\":[{},{},{}],\"heading\":{},\"variables\":{{",
        Seconds(), Number(RE::GetSecondsSinceLastFrame()), Number(position.x), Number(position.y),
        Number(position.z), Number(reference->GetAngleZ()));
    bool first = true;
    for (const auto &name : recording.variables) {
        const RE::BSFixedString key(name);
        float real = 0;
        std::int32_t integer = 0;
        bool flag = false;
        const bool found = reference->GetGraphVariableFloat(key, real);
        reference->GetGraphVariableInt(key, integer);
        reference->GetGraphVariableBool(key, flag);
        if (!found) {
            continue;
        }
        line += std::format(
            "{}\"{}\":[{},{},{}]", first ? "" : ",", Escaped(name), Number(real), integer, flag);
        first = false;
    }
    return line + "}}\n";
}

void Finish()
{
    if (auto *actor = recording.target.get().get();
        actor && actor->Is(RE::FormType::ActorCharacter)) {
        static_cast<RE::Actor *>(actor)->RemoveAnimationGraphEventSink(&eventLog);
    }
    std::string lines;
    {
        std::scoped_lock lock(recordingLock);
        watching = false;
        lines = std::move(recording.lines);
    }
    WriteAtomically("watch.jsonl", lines);
}
} // namespace

bool IsWatching()
{
    std::scoped_lock lock(recordingLock);
    return watching;
}

void StartWatch(std::string_view arguments, RE::TESObjectREFR *reference)
{
    if (!reference || IsWatching()) {
        return;
    }
    std::vector<std::string> words;
    for (auto rest = arguments; !rest.empty();) {
        const auto space = rest.find(' ');
        if (space != 0) {
            words.emplace_back(rest.substr(0, space));
        }
        rest = space == std::string_view::npos ? std::string_view{} : rest.substr(space + 1);
    }
    double seconds = 0;
    if (words.empty() ||
        std::from_chars(words[0].data(), words[0].data() + words[0].size(), seconds).ec !=
            std::errc{}) {
        return;
    }
    {
        std::scoped_lock lock(recordingLock);
        recording = {
            reference->CreateRefHandle(), {words.begin() + 1, words.end()}, Clock::now(), {}, {}};
        recording.end = recording.start + std::chrono::duration_cast<Clock::duration>(
                                              std::chrono::duration<double>(seconds));
        watching = true;
    }
    if (reference->Is(RE::FormType::ActorCharacter)) {
        static_cast<RE::Actor *>(reference)->AddAnimationGraphEventSink(&eventLog);
    }
}

void SampleWatch()
{
    if (!IsWatching()) {
        return;
    }
    auto reference = recording.target.get();
    if (!reference || Clock::now() >= recording.end) {
        Finish();
        return;
    }
    auto line = Sample(reference.get());
    std::scoped_lock lock(recordingLock);
    recording.lines += line;
}
} // namespace bridge
