---
type: Game Behaviour
title: General stats
description: What raises each stat on the journal's General Stats page.
tags: [journal, stats, ui]
---

# General stats

The journal's General Stats page shows misc stats, one counter each. Scripts read and change them
with `Game.QueryStat` and `Game.IncrementStat`. The page layout is on [journal](/engine/journal.md#stats-page).

Source for the rules below: the UESP page <https://en.uesp.net/wiki/Skyrim:Statistics>
(revision 3569833). A stat rises by one for each event unless the table says otherwise.

## General

| Stat | Rises when |
| --- | --- |
| Mauls | The player kills a target with a melee attack in werewolf or Vampire Lord form; finishing moves count |
| Werewolf Transformations | The player uses the Beast Form power |
| Days as a Werewolf | A day passes after the player gets lycanthropy |
| Necks Bitten | The player feeds on a person as a vampire |
| Days as a Vampire | A day passes after the player catches Sanguinare Vampiris |
| Locations Discovered | A location with a map marker is discovered |
| Dungeons Cleared | A dungeon is cleared, usually when its boss dies; a respawned dungeon can count again |
| Days Passed | A day passes from the start date |
| Hours Slept | An hour passes while the player sleeps |
| Hours Waiting | An hour passes while the player waits |
| Standing Stones Found | The player activates a standing stone; a stone found before counts again. All-Maker stones do not count |
| Gold Found | The player picks up gold: the stat rises by the amount |
| Most Gold Carried | The player's gold is higher than the stat: the stat takes the new amount |
| Chests Looted | The player opens a chest |
| Skill Increases | A skill rises one level |
| Skill Books Read | The player reads a skill book that raises a skill |
| Food Eaten | The player eats food |
| Training Sessions | A trainer trains the player |
| Books Read | The player reads a book that is not a skill book; spell tomes count, even for a known spell |
| Horses Owned | The player gets a horse. Arvak and Frost do not count |
| Houses Owned | The player buys one of the five city houses |
| Stores Invested In | The player invests in a merchant |
| Barters | One buy or one sell with a merchant |
| Persuasions | A persuade check succeeds |
| Bribes | A bribe succeeds |
| Intimidations | An intimidate check succeeds |
| Diseases Contracted | The player catches a disease |

## Quest

| Stat | Rises when |
| --- | --- |
| Quests Completed | Any quest is completed |
| Misc Objectives Completed | A misc objective is completed |
| Main Quests Completed | A main quest is completed |
| Side Quests Completed | A side quest is completed |
| The Companions Quests Completed | A Companions main quest, or one of two radiant ones, is completed |
| College of Winterhold Quests Completed | A College main or side quest is completed |
| Thieves' Guild Quests Completed | A Thieves Guild main quest or special job is completed; each radiant kind counts once |
| The Dark Brotherhood Quests Completed | A Dark Brotherhood main quest or contract is completed; repeatable radiant quests do not count |
| Civil War Quests Completed | A civil war quest of either side is completed |
| Daedric Quests Completed | A Daedric quest is completed |
| Dawnguard Quests Completed | A Dawnguard or Castle Volkihar quest is completed; each radiant kind counts once |
| Dragonborn Quests Completed | A Dragonborn main quest is completed |
| Questlines Completed | A faction questline, or the main questline, is completed |

Quitting a Thieves Guild special job lowers its stat by one.

## Combat

| Stat | Rises when |
| --- | --- |
| People Killed | The player kills a person, hostile or not |
| Animals Killed | The player kills an animal; conjured familiars count |
| Creatures Killed | The player kills a creature that is not an animal and not undead |
| Undead Killed | The player kills an undead actor; conjured undead count |
| Daedra Killed | The player kills a Daedra; summoned Daedra count |
| Automatons Killed | The player destroys a Dwarven automaton |
| Critical Strikes | A melee or bow hit by the player is a critical hit; every sneak attack is one |
| Sneak Attacks | The player hits a target that has not detected them |
| Backstabs | The player sneak attacks with a one-handed weapon on a target facing away |
| Weapons Disarmed | The player disarms a target, by the Disarm shout or a disarming bash |
| Brawls Won | The player wins a brawl |
| Bunnies Slaughtered | The player kills a rabbit |

"Favorite Weapon" shows the melee weapon or bow the player uses most. It is text, not a count.

## Magic

| Stat | Rises when |
| --- | --- |
| Spells Learned | The player learns a spell |
| Dragon Souls Collected | The player absorbs a dragon soul; souls from Miraak do not count |
| Words of Power Learned | The player learns a word, from a word wall or a person |
| Words of Power Unlocked | The player spends a dragon soul on a word |
| Shouts Learned | The player has learned all three words of a shout |
| Shouts Mastered | The player has unlocked all three words of a shout |
| Times Shouted | The player shouts, at any length |

"Favorite Spell", "Favorite School", and "Favorite Shout" show what the player uses most.

## Crafting

| Stat | Rises when |
| --- | --- |
| Soul Gems Used | A soul gem recharges a weapon; enchanting does not count |
| Souls Trapped | A soul trap fills a soul gem |
| Magic Items Made | The player enchants an item |
| Weapons Improved | The player tempers a weapon |
| Weapons Made | The player makes a weapon at a forge |
| Armor Improved | The player tempers armour |
| Armor Made | The player makes armour at a forge |
| Potions Mixed | The player makes a potion; cooked food counts too |
| Potions Used | The player drinks a potion |
| Poisons Mixed | The player makes a poison |
| Poisons Used | The player applies a poison to a weapon; reverse pickpocketing does not count |
| Ingredients Harvested | The player harvests an ingredient from a plant or a passive creature |
| Ingredients Eaten | The player eats an ingredient |
| Nirnroots Found | The player harvests a nirnroot; crimson nirnroot does not count |
| Wings Plucked | The player plucks a wing from an insect; a pluck gives two, so the count is even |

## Crime

| Stat | Rises when |
| --- | --- |
| Total Lifetime Bounty | A bounty is placed on the player: the stat rises by the amount |
| Largest Bounty | The player's total bounty is higher than the stat: the stat takes the new total |
| Locks Picked | The player picks a lock |
| Pockets Picked | The player pickpockets a person |
| Items Pickpocketed | The player takes an item by pickpocketing: one per item |
| Times Jailed | The player goes to jail |
| Days Jailed | A day passes while the player serves a sentence |
| Fines Paid | The player pays a bounty: the stat rises by the gold paid |
| Jail Escapes | The player escapes from jail |
| Items Stolen | The player takes an owned item |
| Assaults | The player attacks a person who is not hostile |
| Murders | A person who is not hostile dies by the player, a follower, or a summon |
| Horses Stolen | The player mounts an owned horse |
| Trespasses | The player trespasses, such as entering a locked shop after it closes |

The page also shows the bounty in each hold where the player has one, and one shared bounty for the
Orc strongholds.

## How OpenSky counts

Which stats OpenSky counts so far is on [journal](/engine/journal.md#stats-page). Some rules
above leave a choice, and OpenSky reads them like this:

- A kill counts only when the player is the killer. The victim's `ActorType*` keywords, on its
  race or its base, pick the stats: `ActorTypeNPC` is People, `ActorTypeAnimal` Animals,
  `ActorTypeUndead` Undead, `ActorTypeDaedra` Daedra, and `ActorTypeDwarven` Automatons.
  `ActorTypeCreature` counts as Creatures only without the animal and undead keywords. So a
  victim with both the Daedra and the creature keywords raises both stats.
- A location counts on Dungeons Cleared the first time it clears, whether its last boss dies or a
  script calls `Location.SetCleared`.
- Skill Increases rises once for each level a skill gains, training included.
- A forge craft raises Weapons Made or Armor Made by the made item's type; jewellery is armour.
  A cooking craft raises Potions Mixed. A temper raises Weapons Improved or Armor Improved.
- A brew at an alchemy lab raises Potions Mixed or Poisons Mixed once, whatever number of potions
  it makes.
