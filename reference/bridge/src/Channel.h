// The folder OpenSky and the plugin share, beside SkyrimSE.exe. OpenSky drops command
// batches into `commands/`; the plugin answers through `state.json`.
#pragma once

#include <filesystem>
#include <string>
#include <vector>

namespace bridge {
struct Batch
{
    std::string name;
    std::vector<std::string> lines;
};

std::filesystem::path Folder();

/// Reads and removes each finished batch file, in name order.
std::vector<Batch> TakeBatches();

/// Replaces the file through a rename, so OpenSky never reads half of it.
void WriteAtomically(const std::string &name, const std::string &text);
} // namespace bridge
