#include "Settings.h"

#include <charconv>
#include <cmath>
#include <format>
#include <map>

namespace bridge {
namespace {
// Each name an `ini` line asked about, so the state keeps reporting its current value.
std::map<std::string, bool, std::less<>> asked;

RE::Setting *Find(std::string_view name)
{
    if (auto *prefs = RE::INIPrefSettingCollection::GetSingleton()) {
        if (auto *setting = prefs->GetSetting(name)) {
            return setting;
        }
    }
    if (auto *inis = RE::INISettingCollection::GetSingleton()) {
        if (auto *setting = inis->GetSetting(name)) {
            return setting;
        }
    }
    auto *game = RE::GameSettingCollection::GetSingleton();
    return game ? game->GetSetting(std::string(name).c_str()) : nullptr;
}

std::string ValueText(const RE::Setting &setting)
{
    using Type = RE::Setting::Type;
    switch (setting.GetType()) {
    case Type::kBool:
        return setting.GetBool() ? "true" : "false";
    case Type::kFloat: {
        const float value = setting.GetFloat();
        return std::isfinite(value) ? std::format("{}", value) : "null";
    }
    case Type::kInteger:
        return std::format("{}", setting.GetInteger());
    case Type::kUnsignedInteger:
    case Type::kColorRGB:
    case Type::kColorRGBA:
        return std::format("{}", setting.GetUnsignedInteger());
    case Type::kCharacter:
        return std::format("{}", static_cast<int>(setting.GetCharacter()));
    case Type::kUnsignedCharacter:
        return std::format("{}", static_cast<int>(setting.GetUnsignedCharacter()));
    default:
        return "null";
    }
}

void Set(RE::Setting &setting, std::string_view text)
{
    using Type = RE::Setting::Type;
    double value = 0;
    const auto end = text.data() + text.size();
    if (std::from_chars(text.data(), end, value).ec != std::errc{}) {
        return;
    }
    switch (setting.GetType()) {
    case Type::kBool:
        setting.SetBool(value != 0);
        break;
    case Type::kFloat:
        setting.SetFloat(static_cast<float>(value));
        break;
    case Type::kInteger:
        setting.SetInteger(static_cast<std::int32_t>(value));
        break;
    case Type::kUnsignedInteger:
        setting.SetUnsignedInteger(static_cast<std::uint32_t>(value));
        break;
    default:
        break;
    }
}
} // namespace

void ReadOrSetSetting(std::string_view arguments)
{
    const auto space = arguments.find(' ');
    const auto name = arguments.substr(0, space);
    if (name.empty()) {
        return;
    }
    if (auto *setting = Find(name); setting && space != std::string_view::npos) {
        Set(*setting, arguments.substr(space + 1));
    }
    asked.insert_or_assign(std::string(name), true);
}

std::string SettingsState()
{
    if (asked.empty()) {
        return "";
    }
    std::string members;
    for (const auto &[name, unused] : asked) {
        const auto *setting = Find(name);
        members += std::format(
            "{}\"{}\":{}", members.empty() ? "" : ",", name,
            setting ? ValueText(*setting) : "null");
    }
    return std::format(",\"settings\":{{{}}}", members);
}
} // namespace bridge
