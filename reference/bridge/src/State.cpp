#include "State.h"

#include "Places.h"
#include "Sky.h"
#include "Watch.h"

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

// The player's location, its keywords, its parent, and whether it is cleared, for rules that
// read location types and clearing.
std::string Location(RE::PlayerCharacter *player)
{
    auto *location = player->GetCurrentLocation();
    if (!location) {
        return "";
    }
    std::string keywords;
    for (std::uint32_t index = 0; index < location->numKeywords; ++index) {
        const auto *keyword = location->keywords[index];
        keywords += (keywords.empty() ? "" : ",") + EditorID(keyword);
    }
    return std::format(
        ",\"location\":{{\"editorID\":{},\"formID\":{},\"keywords\":[{}],\"parent\":{},"
        "\"cleared\":{}}}",
        EditorID(location), location->GetFormID(), keywords, EditorID(location->parentLoc),
        location->IsCleared() ? "true" : "false");
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
    json += Location(player);
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
        json += std::format(
            ",\"hour\":{},\"daysPassed\":{}", Number(calendar->GetHour()),
            Number(calendar->GetDaysPassed()));
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
// The actor's AI process level, high 0 to low 3, or -1 for no actor or no process.
int ProcessLevel(RE::TESObjectREFR *reference)
{
    if (!reference || !reference->Is(RE::FormType::ActorCharacter)) {
        return -1;
    }
    const auto *process = static_cast<RE::Actor *>(reference)->GetActorRuntimeData().currentProcess;
    return process ? static_cast<int>(process->processLevel.get()) : -1;
}

// Playing scenes, each with its phase and whether each actor is loaded, disabled, or dead, to
// compare scene rules with OpenSky (docs/engine/scenes.md).
std::string Scenes()
{
    auto *data = RE::TESDataHandler::GetSingleton();
    if (!data) {
        return "";
    }
    std::string scenes;
    for (auto *scene : data->GetFormArray<RE::BGSScene>()) {
        if (!scene || !scene->isPlaying) {
            continue;
        }
        std::string actors;
        for (const auto alias : scene->actors) {
            auto reference = scene->parentQuest ? scene->parentQuest->GetAliasedRef(alias).get()
                                                : RE::NiPointer<RE::TESObjectREFR>{};
            actors += std::format(
                "{}{{\"alias\":{},\"referenceFormID\":{},\"loaded\":{},\"disabled\":{},"
                "\"dead\":{},\"processLevel\":{}}}",
                actors.empty() ? "" : ",", alias, reference ? reference->GetFormID() : 0,
                reference && reference->Is3DLoaded(), reference && reference->IsDisabled(),
                reference && reference->IsDead(false), ProcessLevel(reference.get()));
        }
        scenes += std::format(
            "{}{{\"formID\":{},\"phase\":{},\"actors\":[{}]}}", scenes.empty() ? "" : ",",
            scene->GetFormID(), static_cast<std::int32_t>(scene->currentPhaseIndex), actors);
    }
    return std::format(",\"scenes\":[{}]", scenes);
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

// The reference the last `prid` line picked. The game's own `prid` sets the console menu's
// selection, which a line run from here never reads.
RE::ObjectRefHandle selection;

std::string Selection()
{
    const auto selected = selection.get();
    if (!selected) {
        return "";
    }
    // The running package of an actor, to match `GetCurrentAIProcedure` with its procedure.
    RE::FormID package = 0;
    if (selected->Is(RE::FormType::ActorCharacter)) {
        const auto *current = static_cast<RE::Actor *>(selected.get())->GetCurrentPackage();
        package = current ? current->GetFormID() : 0;
    }
    return std::format(
        ",\"selected\":{{\"formID\":{},\"loaded\":{},\"disabled\":{},\"package\":{},"
        "\"processLevel\":{}}}",
        selected->GetFormID(), selected->Is3DLoaded(), selected->IsDisabled(), package,
        ProcessLevel(selected.get()));
}

// `prid <hex FormID>` picks the reference that later lines without a target act on.
void Pick(std::string_view hex)
{
    RE::FormID id = 0;
    const auto end = hex.data() + hex.size();
    auto *reference = std::from_chars(hex.data(), end, id, 16).ec == std::errc{}
                          ? RE::TESForm::LookupByID<RE::TESObjectREFR>(id)
                          : nullptr;
    selection = reference ? reference->CreateRefHandle() : RE::ObjectRefHandle{};
}

// The answer of the last `condition` line, as a JSON member.
std::string lastCondition;

// `condition <name>` asks a condition function with no parameters about the picked
// reference, so a number the console prints reaches OpenSky.
void AskCondition(std::string_view name)
{
    const auto *command = RE::SCRIPT_FUNCTION::LocateScriptCommand(name);
    auto picked = selection.get();
    double result = 0;
    const bool answered = command && command->conditionFunction && picked &&
                          command->conditionFunction(picked.get(), nullptr, nullptr, result);
    lastCondition = std::format(
        ",\"condition\":{{\"name\":{},\"answered\":{},\"value\":{}}}",
        Quoted(std::string(name).c_str()), answered, Number(static_cast<float>(result)));
}

// `spawn <hex FormID>` places that base object at the player and picks the new reference.
void Spawn(std::string_view hex)
{
    RE::FormID id = 0;
    const auto end = hex.data() + hex.size();
    auto *base = std::from_chars(hex.data(), end, id, 16).ec == std::errc{}
                     ? RE::TESForm::LookupByID<RE::TESBoundObject>(id)
                     : nullptr;
    auto *player = RE::PlayerCharacter::GetSingleton();
    const auto placed = base && player ? player->PlaceObjectAtMe(base, false) : nullptr;
    selection = placed ? placed->CreateRefHandle() : RE::ObjectRefHandle{};
}

// A line runs against the picked reference, as typed in the console after `prid`.
void RunAgainstSelection(const std::string &line)
{
    auto *factory = RE::IFormFactory::GetConcreteFormFactoryByType<RE::Script>();
    auto *script = factory ? factory->Create() : nullptr;
    if (!script) {
        return;
    }
    script->SetCommand(line);
    script->CompileAndRun(selection.get().get());
    delete script;
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
        json += Selection();
        json += Scenes();
        json += lastCondition;
        json += SkyState();
        json += MusicState();
        json += MarkerState();
    }
    return json + "}\n";
}

void RunLine(const std::string &line)
{
    constexpr auto loadVerb = "load "sv;
    constexpr auto answerVerb = "answer "sv;
    constexpr auto saveVerb = "save "sv;
    constexpr auto pickVerb = "prid "sv;
    constexpr auto spawnVerb = "spawn "sv;
    constexpr auto watchVerb = "watch "sv;
    constexpr auto conditionVerb = "condition "sv;
    constexpr auto markerVerb = "marker "sv;
    if (line.starts_with(markerVerb)) {
        GoToMarker(std::string_view(line).substr(markerVerb.size()));
        return;
    }
    if (line.starts_with(conditionVerb)) {
        AskCondition(std::string_view(line).substr(conditionVerb.size()));
        return;
    }
    if (line.starts_with(spawnVerb)) {
        Spawn(std::string_view(line).substr(spawnVerb.size()));
        return;
    }
    // Without a picked reference, the watch records the player.
    if (line.starts_with(watchVerb)) {
        auto picked = selection.get();
        RE::TESObjectREFR *target = picked ? picked.get() : RE::PlayerCharacter::GetSingleton();
        StartWatch(std::string_view(line).substr(watchVerb.size()), target);
        return;
    }
    if (line.starts_with(pickVerb)) {
        Pick(std::string_view(line).substr(pickVerb.size()));
        return;
    }
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
    RunAgainstSelection(line);
}
} // namespace bridge
