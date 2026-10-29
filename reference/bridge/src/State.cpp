#include "State.h"

#include <charconv>
#include <cmath>
#include <format>

namespace bridge {
namespace {
constexpr float degreesPerRadian = 57.29577951f;

std::string Quoted(std::string_view text)
{
    std::string quoted = "\"";
    for (const char character : text) {
        if (character == '"' || character == '\\') {
            quoted += '\\';
        }
        // A message box breaks its lines with control characters; JSON needs them escaped.
        quoted += static_cast<unsigned char>(character) >= 0x20 ? character : ' ';
    }
    return quoted + "\"";
}

std::string Number(float value)
{
    return std::isfinite(value) ? std::format("{}", value) : "null";
}

std::string EditorID(const RE::TESForm *form)
{
    const char *name = form ? form->GetFormEditorID() : nullptr;
    return Quoted(name ? name : "");
}

std::string Place(RE::PlayerCharacter *player)
{
    auto *cell = player->GetParentCell();
    if (!cell) {
        return "";
    }
    const auto feet = player->GetPosition();
    auto json = std::format(
        ",\"position\":[{},{},{}],\"pitchDegrees\":{},\"headingDegrees\":{}", Number(feet.x),
        Number(feet.y), Number(feet.z), Number(player->GetAngleX() * degreesPerRadian),
        Number(player->GetAngleZ() * degreesPerRadian));
    json += std::format(
        ",\"cellFormID\":{},\"cell\":{},\"interior\":{}", cell->GetFormID(), EditorID(cell),
        cell->IsInteriorCell());
    if (cell->IsInteriorCell()) {
        return json;
    }
    if (auto *grid = cell->GetCoordinates()) {
        json += std::format(",\"grid\":[{},{}]", grid->cellX, grid->cellY);
    }
    if (auto *world = player->GetWorldspace()) {
        json += std::format(
            ",\"worldspace\":{},\"worldspaceFormID\":{}", EditorID(world), world->GetFormID());
    }
    return json;
}

std::string View()
{
    std::string json;
    if (auto *calendar = RE::Calendar::GetSingleton()) {
        json += std::format(",\"hour\":{}", Number(calendar->GetHour()));
    }
    auto *sky = RE::Sky::GetSingleton();
    if (sky && sky->currentWeather) {
        json += std::format(",\"weatherFormID\":{}", sky->currentWeather->GetFormID());
    }
    if (auto *camera = RE::PlayerCamera::GetSingleton()) {
        const auto &fov = camera->GetRuntimeData2();
        json += std::format(
            ",\"worldFOV\":{},\"firstPersonFOV\":{},\"firstPerson\":{}", Number(fov.worldFOV),
            Number(fov.firstPersonFOV), camera->IsInFirstPerson());
    }
    return json;
}
// The open message box, which waits for a button before the game goes on.
std::string Dialog()
{
    const auto *data = RE::MessageBoxMenu::GetCurrentMessageBoxData();
    if (!data) {
        return "";
    }
    std::string buttons;
    for (const auto &button : data->buttonText) {
        buttons += (buttons.empty() ? "" : ",") + Quoted(button.c_str());
    }
    return std::format(
        ",\"dialog\":{{\"text\":{},\"buttons\":[{}]}}", Quoted(data->bodyText.c_str()), buttons);
}

// `answer <index>` presses that button of the open message box.
void Answer(std::string_view digits)
{
    std::uint32_t index = 0;
    const auto end = digits.data() + digits.size();
    const auto *data = RE::MessageBoxMenu::GetCurrentMessageBoxData();
    if (std::from_chars(digits.data(), end, index).ec == std::errc{} && data &&
        index < data->buttonText.size()) {
        RE::MessageBoxMenu::SelectOption(static_cast<std::int32_t>(index));
    }
}
} // namespace

std::string Snapshot(const std::string &lastBatch)
{
    auto *ui = RE::UI::GetSingleton();
    const bool mainMenu = ui && ui->IsMenuOpen(RE::MainMenu::MENU_NAME);
    const bool loading = ui && ui->IsMenuOpen(RE::LoadingMenu::MENU_NAME);
    auto json = std::format(
        "{{\"version\":1,\"batch\":{},\"mainMenu\":{},\"loading\":{}", Quoted(lastBatch), mainMenu,
        loading);
    json += Dialog();
    auto *player = RE::PlayerCharacter::GetSingleton();
    if (player && !mainMenu && !loading) {
        json += Place(player);
        json += View();
    }
    return json + "}\n";
}

void RunLine(const std::string &line)
{
    constexpr auto loadVerb = "load "sv;
    constexpr auto answerVerb = "answer "sv;
    constexpr auto saveVerb = "save "sv;
    // A save started inside the UI task queue never finishes, so it waits for the main one.
    if (line.starts_with(saveVerb)) {
        SKSE::GetTaskInterface()->AddTask([name = line.substr(saveVerb.size())] {
            if (auto *saves = RE::BGSSaveLoadManager::GetSingleton()) {
                saves->Save(name.c_str());
            }
        });
        return;
    }
    if (line.starts_with(answerVerb)) {
        Answer(std::string_view(line).substr(answerVerb.size()));
        return;
    }
    if (line.starts_with(loadVerb)) {
        if (auto *saves = RE::BGSSaveLoadManager::GetSingleton()) {
            saves->Load(line.substr(loadVerb.size()).c_str());
        }
        return;
    }
    RE::Console::ExecuteCommand(line.c_str());
}
} // namespace bridge
