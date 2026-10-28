#include "Channel.h"

#include <algorithm>
#include <fstream>

namespace bridge {
namespace {
std::vector<std::string> ReadLines(const std::filesystem::path &file)
{
    std::ifstream stream(file, std::ios::binary);
    std::vector<std::string> lines;
    std::string line;
    while (std::getline(stream, line)) {
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        if (!line.empty()) {
            lines.push_back(line);
        }
    }
    return lines;
}
} // namespace

std::filesystem::path Folder()
{
    return std::filesystem::current_path() / "OpenSkyBridge";
}

std::vector<Batch> TakeBatches()
{
    std::error_code error;
    std::vector<std::filesystem::path> files;
    // OpenSky writes `<name>.tmp` and renames it, so a `.txt` file is complete.
    for (const auto &entry : std::filesystem::directory_iterator(Folder() / "commands", error)) {
        if (entry.path().extension() == ".txt") {
            files.push_back(entry.path());
        }
    }
    std::ranges::sort(files);
    std::vector<Batch> batches;
    for (const auto &file : files) {
        batches.push_back({file.stem().string(), ReadLines(file)});
        std::filesystem::remove(file, error);
    }
    return batches;
}

void WriteAtomically(const std::string &name, const std::string &text)
{
    std::error_code error;
    std::filesystem::create_directories(Folder(), error);
    const auto target = Folder() / name;
    auto temporary = target;
    temporary += ".tmp";
    {
        std::ofstream stream(temporary, std::ios::binary | std::ios::trunc);
        stream << text;
    }
    std::filesystem::rename(temporary, target, error);
}
} // namespace bridge
