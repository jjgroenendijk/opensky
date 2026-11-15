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
    return state;
}
} // namespace bridge
