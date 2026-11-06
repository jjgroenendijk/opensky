#include "Places.h"

#include <algorithm>
#include <cctype>
#include <format>

namespace bridge {
namespace {
RE::ObjectRefHandle lastMarker;
std::string lastMarkerName;

bool SameName(std::string_view lhs, std::string_view rhs)
{
    return lhs.size() == rhs.size() &&
           std::equal(lhs.begin(), lhs.end(), rhs.begin(), [](char left, char right) {
               return std::tolower(static_cast<unsigned char>(left)) ==
                      std::tolower(static_cast<unsigned char>(right));
           });
}

RE::MapMarkerData *MarkerData(RE::TESObjectREFR *reference)
{
    auto *extra = reference ? reference->extraList.GetByType<RE::ExtraMapMarker>() : nullptr;
    return extra ? extra->mapData : nullptr;
}

RE::TESObjectREFR *FindMarker(std::string_view name)
{
    const auto &[forms, lock] = RE::TESForm::GetAllForms();
    const RE::BSReadLockGuard guard{lock};
    if (!forms) {
        return nullptr;
    }
    for (const auto &[id, form] : *forms) {
        auto *reference = form ? form->AsReference() : nullptr;
        const auto *data = MarkerData(reference);
        const char *markerName = data ? data->locationName.fullName.c_str() : nullptr;
        if (markerName && SameName(markerName, name)) {
            return reference;
        }
    }
    return nullptr;
}
} // namespace

void GoToMarker(std::string_view name)
{
    lastMarkerName = std::string(name);
    auto *marker = FindMarker(name);
    lastMarker = marker ? marker->CreateRefHandle() : RE::ObjectRefHandle{};
    auto *player = RE::PlayerCharacter::GetSingleton();
    if (marker && player) {
        player->MoveTo(marker);
    }
}

std::string MarkerState()
{
    if (lastMarkerName.empty()) {
        return "";
    }
    auto marker = lastMarker.get();
    const auto *data = MarkerData(marker.get());
    if (!data) {
        return std::format(",\"marker\":{{\"found\":false,\"formID\":0,\"type\":0,\"flags\":0}}");
    }
    return std::format(
        ",\"marker\":{{\"found\":true,\"formID\":{},\"type\":{},\"flags\":{}}}",
        marker->GetFormID(), static_cast<int>(data->type.get()),
        static_cast<int>(data->flags.underlying()));
}
} // namespace bridge
