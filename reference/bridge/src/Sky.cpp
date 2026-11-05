#include "Sky.h"

#include <cmath>
#include <cstring>
#include <format>

namespace bridge {
namespace {
std::string Num(float value)
{
    return std::isfinite(value) ? std::format("{}", value) : "null";
}

std::string Escaped(const char *text)
{
    std::string quoted = "\"";
    for (const char *character = text ? text : ""; *character; ++character) {
        if (*character == '"' || *character == '\\') {
            quoted += '\\';
        }
        quoted += static_cast<unsigned char>(*character) >= 0x20 ? *character : ' ';
    }
    return quoted + "\"";
}

std::string Vector(const RE::NiPoint3 &point)
{
    return std::format("[{},{},{}]", Num(point.x), Num(point.y), Num(point.z));
}

// The unit direction from the sky's centre to a node, as the viewer sees it.
std::string Direction(const RE::NiAVObject *node, const RE::NiAVObject *centre)
{
    if (!node || !centre) {
        return "null";
    }
    auto offset = node->world.translate - centre->world.translate;
    const float length = offset.Length();
    return length > 0 ? Vector(offset / length) : "null";
}

// The first node that stands away from the centre: a moon's offset sits on its mesh.
std::string
FirstDirection(std::initializer_list<const RE::NiAVObject *> nodes, const RE::NiAVObject *centre)
{
    for (const auto *node : nodes) {
        if (node && centre && node->world.translate != centre->world.translate) {
            return Direction(node, centre);
        }
    }
    return "null";
}

bool Hidden(const RE::NiAVObject *node)
{
    return !node || node->GetFlags().any(RE::NiAVObject::Flag::kHidden);
}

const RE::BSSkyShaderProperty *SkyShader(RE::BSGeometry *geometry)
{
    if (!geometry) {
        return nullptr;
    }
    auto *property = geometry->GetGeometryRuntimeData().shaderProperty.get();
    return netimmerse_cast<RE::BSSkyShaderProperty *>(property);
}

// The colour, alpha, and texture a sky shape draws with.
std::string Look(RE::BSGeometry *geometry)
{
    const auto *shader = SkyShader(geometry);
    if (!shader) {
        return "\"look\":null";
    }
    const auto &blend = shader->kBlendColor;
    const auto *texture = shader->pBaseTexture;
    return std::format(
        "\"look\":{{\"colour\":[{},{},{},{}],\"texture\":{},\"blend\":{}}}", Num(blend.red),
        Num(blend.green), Num(blend.blue), Num(blend.alpha),
        Escaped(texture ? texture->name.c_str() : ""), Num(shader->fBlendValue));
}

std::string Moon(const RE::Moon *moon, const RE::NiAVObject *centre)
{
    if (!moon) {
        return "null";
    }
    return std::format(
        "{{\"direction\":{},\"hidden\":{},\"meshHidden\":{},\"shadowHidden\":{},{}}}",
        FirstDirection({moon->moonMesh.get(), moon->moonNode.get(), moon->root.get()}, centre),
        Hidden(moon->root.get()), Hidden(moon->moonMesh.get()), Hidden(moon->shadowMesh.get()),
        Look(moon->moonMesh.get()));
}

// Values that may hold a layer's texture scroll: the layer's own pair of words in the cloud
// object, and the shader material's texture offset. Watched over time to find the scroll.
std::string Scroll(const RE::Clouds *clouds, std::uint16_t index, RE::BSGeometry *geometry)
{
    float pair[2];
    std::memcpy(pair, &clouds->unk110[index], sizeof(pair));
    const auto *shader = SkyShader(geometry);
    const auto *material = shader ? shader->material : nullptr;
    const auto offset = material ? material->texCoordOffset[0] : RE::NiPoint2{};
    const auto scale = material ? material->texCoordScale[0] : RE::NiPoint2{};
    return std::format(
        "\"layerWords\":[{},{}],\"materialOffset\":[{},{}],\"materialScale\":[{},{}]", Num(pair[0]),
        Num(pair[1]), Num(offset.x), Num(offset.y), Num(scale.x), Num(scale.y));
}

std::string Clouds(const RE::Clouds *clouds)
{
    if (!clouds) {
        return "[]";
    }
    std::string layers;
    for (std::uint16_t index = 0; index < clouds->numLayers && index < RE::Clouds::kTotalLayers;
         ++index) {
        auto *geometry = clouds->clouds[index].get();
        if (!geometry) {
            continue;
        }
        layers += std::format(
            "{}{{\"layer\":{},\"hidden\":{},\"alpha\":{},{},{}}}", layers.empty() ? "" : ",", index,
            Hidden(geometry), Num(clouds->alphas[index]), Scroll(clouds, index, geometry),
            Look(geometry));
    }
    return "[" + layers + "]";
}

std::string Sun(const RE::Sun *sun, const RE::NiAVObject *centre)
{
    if (!sun) {
        return "null";
    }
    const auto *light = sun->light.get();
    return std::format(
        "{{\"direction\":{},\"lightDirection\":{},\"hidden\":{},\"glareScale\":{},{}}}",
        FirstDirection({sun->sunBase.get(), sun->sunBaseNode.get(), sun->root.get()}, centre),
        light ? Vector(light->GetWorldDirection()) : "null", Hidden(sun->root.get()),
        Num(sun->glareScale), Look(sun->sunBase.get()));
}

const char *TypeName(RE::BSIMusicType *type)
{
    auto *form = skyrim_cast<RE::BGSMusicType *>(type);
    return form ? form->GetFormEditorID() : "";
}

std::string MusicType(RE::BSIMusicType *type)
{
    auto *form = skyrim_cast<RE::BGSMusicType *>(type);
    return std::format(
        "{{\"editorID\":{},\"formID\":{},\"status\":{},\"track\":{},\"priority\":{}}}",
        Escaped(TypeName(type)), form ? form->GetFormID() : 0,
        static_cast<int>(type->typeStatus.get()), type->currentTrackIndex,
        static_cast<int>(type->priority));
}
} // namespace

std::string SkyState()
{
    auto *sky = RE::Sky::GetSingleton();
    if (!sky || !sky->root) {
        return "";
    }
    const RE::NiAVObject *centre = sky->root.get();
    return std::format(
        ",\"sky\":{{\"mode\":{},\"weatherPercent\":{},\"windSpeed\":{},\"windAngle\":{},"
        "\"sun\":{},\"masser\":{},\"secunda\":{},\"clouds\":{}}}",
        static_cast<int>(sky->mode.get()), Num(sky->currentWeatherPct), Num(sky->windSpeed),
        Num(sky->windAngle), Sun(sky->sun, centre), Moon(sky->masser, centre),
        Moon(sky->secunda, centre), Clouds(sky->clouds));
}

std::string MusicState()
{
    auto *music = RE::BSMusicManager::GetSingleton();
    if (!music) {
        return "";
    }
    std::string queue;
    for (auto *type : music->musicQueue) {
        if (type) {
            queue += (queue.empty() ? "" : ",") + MusicType(type);
        }
    }
    return std::format(
        ",\"music\":{{\"current\":{},\"queue\":[{}]}}",
        music->current ? MusicType(music->current) : "null", queue);
}
} // namespace bridge
