// OpenSkyBridge: runs the console commands OpenSky sends and reports the player's state,
// so the reference game follows OpenSky without typed keys. It changes no game rule and
// draws nothing (docs/tools/reference-game.md).
#include "Channel.h"
#include "State.h"

#include <atomic>
#include <chrono>
#include <mutex>
#include <thread>

namespace {
constexpr auto pollInterval = std::chrono::milliseconds(250);

std::mutex lastBatchLock;
std::string lastBatch;
std::atomic_bool snapshotQueued = false;

void RunBatch(const bridge::Batch &batch)
{
    for (const auto &line : batch.lines) {
        bridge::RunLine(line);
    }
    std::scoped_lock lock(lastBatchLock);
    lastBatch = batch.name;
}

void WriteSnapshot()
{
    std::string batch;
    {
        std::scoped_lock lock(lastBatchLock);
        batch = lastBatch;
    }
    bridge::WriteAtomically("state.json", bridge::Snapshot(batch));
    snapshotQueued = false;
}

// Game objects are touched only on the main thread. SKSE's UI task queue also drains
// while a menu pauses the game, such as a message box waiting for an answer.
[[noreturn]] void Poll()
{
    const auto *tasks = SKSE::GetTaskInterface();
    while (true) {
        for (auto &batch : bridge::TakeBatches()) {
            tasks->AddUITask([batch = std::move(batch)] { RunBatch(batch); });
        }
        if (!snapshotQueued.exchange(true)) {
            tasks->AddUITask(WriteSnapshot);
        }
        std::this_thread::sleep_for(pollInterval);
    }
}

void OnMessage(SKSE::MessagingInterface::Message *message)
{
    if (message->type == SKSE::MessagingInterface::kDataLoaded) {
        std::thread(Poll).detach();
    }
}
} // namespace

SKSEPluginInfo(.Version = {1, 0, 0, 0}, .Name = "OpenSkyBridge"sv, .Author = "OpenSky"sv)

    SKSEPluginLoad(const SKSE::LoadInterface *skse)
{
    SKSE::Init(skse, {.log = false});
    return SKSE::GetMessagingInterface()->RegisterListener(OnMessage);
}
