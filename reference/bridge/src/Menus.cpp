#include "Menus.h"

#include <charconv>
#include <format>
#include <map>
#include <mutex>
#include <vector>

namespace bridge {
namespace {
std::mutex menuLock;
std::map<std::string, std::string> values;
std::string lastClick;
std::string lastCall;

std::string Quoted(std::string_view text)
{
    std::string quoted = "\"";
    for (const char character : text) {
        if (character == '"' || character == '\\') {
            quoted += '\\';
        }
        quoted += static_cast<unsigned char>(character) >= 0x20 ? character : ' ';
    }
    return quoted + "\"";
}

std::vector<std::string> Fields(std::string_view arguments)
{
    std::vector<std::string> fields;
    std::size_t start = 0;
    while (true) {
        const auto end = arguments.find('|', start);
        fields.emplace_back(arguments.substr(start, end - start));
        if (end == std::string_view::npos) {
            return fields;
        }
        start = end + 1;
    }
}

float Parsed(const std::string &text)
{
    float value = 0;
    std::from_chars(text.data(), text.data() + text.size(), value);
    return value;
}

RE::GFxMovieView *Movie(const std::string &menu)
{
    auto *ui = RE::UI::GetSingleton();
    if (!ui) {
        return nullptr;
    }
    auto open = ui->GetMenu(menu);
    return open ? open->uiMovie.get() : nullptr;
}

std::string Text(const RE::GFxValue &value)
{
    if (value.IsString()) {
        return Quoted(value.GetString());
    }
    if (value.IsNumber()) {
        return std::format("{}", value.GetNumber());
    }
    if (value.IsBool()) {
        return value.GetBool() ? "true" : "false";
    }
    if (value.IsUndefined() || value.IsNull()) {
        return "null";
    }
    return Quoted(value.ToString().c_str());
}
} // namespace

// The stage point in the window's pixels, through the movie's viewport and the stage rectangle
// the viewport shows.
RE::GPointF ToScreen(RE::GFxMovieView *movie, RE::GPointF stage)
{
    RE::GViewport viewport;
    movie->GetViewport(&viewport);
    const auto visible = movie->GetVisibleFrameRect();
    const float width = visible.right - visible.left;
    const float height = visible.bottom - visible.top;
    if (width <= 0 || height <= 0) {
        return stage;
    }
    return {
        viewport.left + (stage.x - visible.left) * viewport.width / width,
        viewport.top + (stage.y - visible.top) * viewport.height / height};
}

void ClickMenu(std::string_view arguments, std::string_view action)
{
    const auto fields = Fields(arguments);
    if (fields.size() != 3) {
        return;
    }
    auto *movie = Movie(fields[0]);
    std::scoped_lock lock(menuLock);
    if (!movie) {
        lastClick = std::format("{{\"menu\":{},\"open\":false}}", Quoted(fields[0]));
        return;
    }
    const RE::GPointF stage{Parsed(fields[1]), Parsed(fields[2])};
    const auto screen = ToScreen(movie, stage);
    using Test = RE::GFxMovieView::HitTestType;
    const bool shape = movie->HitTest(screen.x, screen.y, Test::kShapes);
    const bool button = movie->HitTest(screen.x, screen.y, Test::kButtonEvents);
    using Type = RE::GFxEvent::EventType;
    if (action == "move" || action == "click") {
        movie->HandleEvent(RE::GFxMouseEvent(Type::kMouseMove, 0, screen.x, screen.y));
    }
    if (action == "down" || action == "click") {
        movie->HandleEvent(RE::GFxMouseEvent(Type::kMouseDown, 0, screen.x, screen.y));
    }
    if (action == "up" || action == "click") {
        movie->HandleEvent(RE::GFxMouseEvent(Type::kMouseUp, 0, screen.x, screen.y));
    }
    lastClick = std::format(
        "{{\"menu\":{},\"open\":true,\"action\":{},\"stage\":[{},{}],\"screen\":[{},{}],"
        "\"hitShape\":{},\"hitButton\":{}}}",
        Quoted(fields[0]), Quoted(action), stage.x, stage.y, screen.x, screen.y, shape, button);
}

void ReadMenuVariable(std::string_view arguments)
{
    const auto fields = Fields(arguments);
    if (fields.size() != 2) {
        return;
    }
    const auto key = fields[0] + "|" + fields[1];
    auto *movie = Movie(fields[0]);
    RE::GFxValue value;
    const bool found = movie && movie->GetVariable(&value, fields[1].c_str());
    std::scoped_lock lock(menuLock);
    values[key] = found ? Text(value) : "null";
}

void PlayBink(std::string_view arguments)
{
    auto *machine = RE::BSScript::Internal::VirtualMachine::GetSingleton();
    const auto fields = Fields(arguments);
    if (!machine || fields.empty()) {
        return;
    }
    // The script's own defaults: not interruptible, other sound and music muted, letterboxed.
    const auto flag = [&fields](std::size_t index, bool fallback) {
        return index < fields.size() ? fields[index] == "1" : fallback;
    };
    RE::BSFixedString name(fields[0].c_str());
    auto *callArguments = RE::MakeFunctionArguments(
        std::move(name), flag(1, false), flag(2, true), flag(3, true), flag(4, true));
    RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> result;
    machine->DispatchStaticCall("Game", "PlayBink", callArguments, result);
}

void OpenMenu(std::string_view menu, bool open)
{
    auto *queue = RE::UIMessageQueue::GetSingleton();
    if (!queue || menu.empty()) {
        return;
    }
    const auto type = open ? RE::UI_MESSAGE_TYPE::kShow : RE::UI_MESSAGE_TYPE::kHide;
    queue->AddMessage(RE::BSFixedString(std::string(menu).c_str()), type, nullptr);
}

// A field that reads as a whole number, `true`, or `false` passes as that type, any other as text.
RE::GFxValue Argument(const std::string &text)
{
    if (text == "true" || text == "false") {
        return RE::GFxValue(text == "true");
    }
    double number = 0;
    const auto *end = text.data() + text.size();
    const auto parsed = std::from_chars(text.data(), end, number);
    if (!text.empty() && parsed.ec == std::errc{} && parsed.ptr == end) {
        return RE::GFxValue(number);
    }
    return RE::GFxValue(text.c_str());
}

void CallMenu(std::string_view arguments)
{
    const auto fields = Fields(arguments);
    if (fields.size() < 2) {
        return;
    }
    auto *movie = Movie(fields[0]);
    std::vector<RE::GFxValue> callArguments;
    for (std::size_t index = 2; index < fields.size(); ++index) {
        callArguments.push_back(Argument(fields[index]));
    }
    RE::GFxValue result;
    const bool called = movie && movie->Invoke(
                                     fields[1].c_str(), &result, callArguments.data(),
                                     static_cast<std::uint32_t>(callArguments.size()));
    std::scoped_lock lock(menuLock);
    lastCall = std::format(
        "{{\"menu\":{},\"path\":{},\"open\":{},\"called\":{},\"result\":{}}}", Quoted(fields[0]),
        Quoted(fields[1]), movie != nullptr, called, called ? Text(result) : "null");
}

void SetAutoMove(bool on)
{
    if (auto *controls = RE::PlayerControls::GetSingleton()) {
        controls->data.autoMove = on;
    }
}

bool RunMenuLine(std::string_view line)
{
    constexpr auto openVerb = "menuopen "sv;
    constexpr auto closeVerb = "menuclose "sv;
    constexpr auto callVerb = "menucall "sv;
    constexpr auto autoMoveVerb = "automove "sv;
    if (line.starts_with(openVerb)) {
        OpenMenu(line.substr(openVerb.size()), true);
    } else if (line.starts_with(closeVerb)) {
        OpenMenu(line.substr(closeVerb.size()), false);
    } else if (line.starts_with(callVerb)) {
        CallMenu(line.substr(callVerb.size()));
    } else if (line.starts_with(autoMoveVerb)) {
        SetAutoMove(line.substr(autoMoveVerb.size()) == "on");
    } else {
        return false;
    }
    return true;
}

std::string MenuState()
{
    std::scoped_lock lock(menuLock);
    std::string json;
    for (const auto &[key, value] : values) {
        json += (json.empty() ? "" : ",") + Quoted(key) + ":" + value;
    }
    auto state = std::format(",\"menuValues\":{{{}}}", json);
    if (!lastClick.empty()) {
        state += ",\"menuClick\":" + lastClick;
    }
    if (!lastCall.empty()) {
        state += ",\"menuCall\":" + lastCall;
    }
    std::string open;
    if (auto *ui = RE::UI::GetSingleton()) {
        for (const auto &[name, entry] : ui->menuMap) {
            if (entry.menu && ui->IsMenuOpen(name)) {
                open += (open.empty() ? "" : ",") + Quoted(name.c_str());
            }
        }
    }
    const auto *controls = RE::PlayerControls::GetSingleton();
    state += std::format(
        ",\"openMenus\":[{}],\"autoMove\":{}", open, controls && controls->data.autoMove);
    return state;
}
} // namespace bridge
