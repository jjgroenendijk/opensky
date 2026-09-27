// Voice-file naming rule. Every case below is a real vanilla file name, taken
// from the archive listing `openskycli audio voice-sweep` walks, paired with
// the editor IDs its records carry. The rule was derived from that listing
// rather than from a community description, so these are the pins that keep it
// derived — see docs/formats/fuz.md for the evidence and the measured coverage.

import Foundation
@testable import opensky
import Testing

@Suite("Voice file paths")
struct VoiceFilePathTests {
    /// One shape of the shared 25-character budget: the two editor IDs and the
    /// `<quest>_<topic>` stem they must produce.
    struct StemCase {
        let quest: String?
        let topic: String?
        let stem: String

        init(_ quest: String?, _ topic: String?, _ stem: String) {
            self.quest = quest
            self.topic = topic
            self.stem = stem
        }
    }

    static let stems: [StemCase] = [
        // Both names fit the budget: both are spelled out in full.
        StemCase("CWMission04", "CWPrisonerWait", "cwmission04_cwprisonerwait"),
        StemCase("TG07", "TG07BreakInBranchTopic", "tg07_tg07breakinbranchtopi"),
        StemCase("BQ01", "BQ01MainTopic", "bq01_bq01maintopic"),
        // Over budget: the quest drops to ten flat, the topic to fifteen.
        StemCase("DarkBrotherhood", "DB05AstridEmperorTopic", "darkbrothe_db05astridemper"),
        StemCase("DialogueGeneric", "OfferServicesTopic", "dialoguege_offerservicesto"),
        // Over budget with a short quest: the quest keeps its own length and
        // the topic takes the whole remainder, past its own fifteen.
        StemCase("BardSongs", "BardSongsBallad01RequestBranchTopic", "bardsongs_bardsongsballad0"),
        StemCase("C00", "C00AelaCanYaTakeHimTopic", "c00_c00aelacanyatakehimtop"),
        StemCase("DLC1LD", "DLC1LD_DeepFolkPostShardTopic", "dlc1ld_dlc1ld_deepfolkpost"),
        // No topic editor ID at all, which is the common vanilla case: the
        // quest is spelled out while it fits the whole budget on its own.
        StemCase("BYOHHouseBuilding", nil, "byohhousebuilding_"),
        StemCase("DialogueWinterholdCollege", nil, "dialoguewinterholdcollege_"),
        // No topic and a quest past the budget: still ten, not twenty-five.
        StemCase("BYOHHouseDialogueHousecarl", nil, "byohhoused_"),
        StemCase("DLC1DialogueHunterBaseScene10", nil, "dlc1dialog_"),
        // Neither name, which the archive spells as a doubled underscore.
        StemCase(nil, nil, "_")
    ]

    @Test("the quest and topic editor IDs share one budget", arguments: stems)
    func stemBudget(row: StemCase) {
        #expect(VoiceFilePath.stem(quest: row.quest, topic: row.topic) == row.stem)
    }

    @Test("a file name carries the FormID in eight lowercase hex plus the response")
    func fileName() {
        #expect(
            VoiceFilePath.fileName(
                VoiceFilePath.Name(
                    quest: "WIGreeting", topic: nil, objectID: 0x000C_7917, responseNumber: 1
                )
            ) == "wigreeting__000c7917_1.fuz"
        )
        #expect(
            VoiceFilePath.fileName(
                VoiceFilePath.Name(
                    quest: "C03", topic: "C03EorlundBranchTopic",
                    objectID: 0x0004_B706, responseNumber: 2
                )
            ) == "c03_c03eorlundbranchtopic_0004b706_2.fuz"
        )
    }

    @Test("a full path is a canonical VFS key under sound\\voice")
    func fullPath() {
        let path = VoiceFilePath.path(
            plugin: "Skyrim.esm",
            voiceType: "FemaleEvenToned",
            name: VoiceFilePath.Name(
                quest: "WIGreeting", topic: nil, objectID: 0x000C_7917, responseNumber: 1
            )
        )
        #expect(
            path == "sound\\voice\\skyrim.esm\\femaleeventoned\\wigreeting__000c7917_1.fuz"
        )
        #expect(
            VoiceFilePath.directory(plugin: "Dawnguard.esm", voiceType: "CRDragonVoice")
                == "sound\\voice\\dawnguard.esm\\crdragonvoice"
        )
    }

    @Test("the exporting plugin's own index is cleared and a master's is kept")
    func exportedFormID() {
        // Skyrim.esm has no masters, so its own records are already index 0.
        #expect(VoiceFilePath.exportedFormID(FormID(0x0004_B706), masterCount: 0) == 0x0004_B706)
        // Dawnguard.esm has two masters, so its own records are index 2 and
        // export as index 0 — every vanilla Dawnguard line is `00xxxxxx`.
        #expect(VoiceFilePath.exportedFormID(FormID(0x0201_156B), masterCount: 2) == 0x0001_156B)
        // A record from the second master keeps its index, which is why a
        // handful of Dawnguard lines are spelled `01xxxxxx`.
        #expect(VoiceFilePath.exportedFormID(FormID(0x0100_3E60), masterCount: 2) == 0x0100_3E60)
    }
}
