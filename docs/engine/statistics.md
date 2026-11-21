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

## How the game counts

The game keeps one whole-number counter per stat name. A rule can add one, add an amount, or set
the value. Some changes also send the stat-changed notice that drives the milestone messages; the
others are silent.

### Stats only scripts raise

Persuasions, Bribes, and Intimidations rise only through `Game.IncrementStat`. A speech check in
dialogue does not count on its own; the vanilla dialogue scripts raise the stat. Horses Owned,
Houses Owned, Stores Invested In, Standing Stones Found, Necks Bitten, Werewolf Transformations,
Brawls Won, Questlines Completed, Vampirism Cures, and Wings Plucked are raised by vanilla
scripts too.

### Days

The clock adds the frame's real seconds times the timescale, over 3600, to the hour. When the
hour passes 24, it takes 24 off, repeating while the hour is still over 24, and moves the date on.
Then one day-passed event with a count of 1 fires, even when one update jumped more than a day.
On that event:

- Days Passed rises by 1.
- Days as a Vampire rises by 1 when the global that the `PIVV` default object names is not 0.
- Days as a Werewolf rises by 1 when the global that the `PIWV` default object names is not 0.

No race or keyword check is made. All three are silent.

### Kills

A kill counts when the player is the killer and there is a victim:

- Mauls rises by 1 while the player's beast form flag is on. `Game.SetBeastForm` sets and clears
  the flag, and a transformation effect on the player turns it on. The same flag stops a shout
  from the favourites menu.
- Bunnies Slaughtered rises by 1 when the victim is in the faction that the `Bunny Faction`
  default object names. No race, keyword, or form is checked.

### Critical hits

A weapon hit by the player on another actor sends up to two critical-hit events: one when the hit
is critical, and one when it is a sneak attack. Each event:

- raises Critical Strikes by 1;
- raises Sneak Attacks by 1 when it is the sneak attack event;
- raises Backstabs by 1 when the player has any perk with a `Mod Sneak Attack Mult` entry, whatever
  its conditions, and the weapon's animation type is hand to hand, one-handed sword, dagger,
  one-handed axe, one-handed mace, or staff (`WEAP` animation types 0 to 4, and 8).

Example: a critical sneak attack with a dagger, by a player with the Backstab perk, raises
Critical Strikes by 2, Sneak Attacks by 1, and Backstabs by 2. A bow sneak attack raises
Critical Strikes and Sneak Attacks, and never Backstabs. All three are silent.

### Other engine counts

- Weapons Disarmed rises by 1 when the player disarms an actor, by any perk or shout effect.
- Dragon Souls Collected rises by 1 each time the Dragon Souls actor value rises, by any amount.
  So 3 souls given at once count once. It sends the notice.
- `Game.TeachWord` on a word the player did not know raises Words Of Power Learned by 1. When the
  word gives the player a shout they did not have, Shouts Learned also rises by 1. Both send the
  notice.
- `Game.UnlockWord` raises Words Of Power Unlocked by 1. For each shout with that word, Shouts
  Unlocked rises by 1 when it is the shout's first word, and Shouts Mastered by 1 when it is the
  shout's last word, the highest slot with both a word and a spell. Whether the earlier words are
  unlocked is not checked.
- In the magic menu, a dragon soul spent on a word that leaves the whole shout unlocked plays
  `UIShoutLearnAll` and raises Shouts Mastered by 1. Any other unlock plays `UIShoutLearnSingle`.

### Favourites

The four "Favorite" stats are names in the counter table, but the game never writes them, so
`Game.QueryStat` reads 0. The save keeps three lists instead, of the last 100 weapons, spells, and
shouts the player used. A full list drops its oldest entry.

- A weapon enters the list on each attack: a melee weapon on the swing, a bow, crossbow, or staff
  when it fires. A hit is not needed.
- A spell enters on each cast, when it is a spell, a power, a lesser power, an ability, a levelled
  spell, or a scroll. Diseases, poisons, enchantments, potions, ingredients, addictions, voice
  powers, and staff enchantments do not enter.
- A shout enters each time the player shouts.

The Stats page counts how often each form is in its list and shows the name of the most frequent
one. A tie has no fixed winner. An empty list, or a form with no name, shows "None".

Favorite School uses the spell list, without powers, lesser powers, addictions, and scrolls. Each
spell counts for the skill of its main effect, and the page shows the name of the most frequent
skill.

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
- Eating food raises Food Eaten, and drinking a potion Potions Used. The food flag on the `ALCH`
  record tells them apart. Drinking a poison raises nothing. Eating an ingredient raises
  Ingredients Eaten. Putting a poison on a weapon raises Poisons Used.
- Gold the player takes from the world, a container, or a body raises Gold Found by the amount.
  Gold from a sale, a reward, or a script does not. Most Gold Carried takes the player's gold after
  each such take and each trade, when it is higher.
- Each buy and each sell with a merchant raises Barters, whatever the number of items.
- Opening a container that is not a body raises Chests Looted, each time.
- Each hour the player sleeps or waits in the rest menu raises Hours Slept or Hours Waiting.
- A word of power counts on Words Of Power Learned the first time the player knows it, and on Words
  Of Power Unlocked the first time it is unlocked, by a dragon soul or by `Game.UnlockWord`.
- Each shout raises Times Shouted, at any length. A soul a soul trap puts in a gem raises Souls
  Trapped. A soul gem that recharges a weapon raises Soul Gems Used. Each enchanted item raises
  Magic Items Made.
- A harvest raises Ingredients Harvested by the number of ingredients it gives, so the Green Thumb
  perk counts twice. A harvested `Nirnroot` also raises Nirnroots Found.
- A book counts the first time the player reads it. A skill book raises Skill Books Read, and any
  other book, a note or a spell tome too, raises Books Read. A tome that teaches a new spell also
  raises Spells Learned. A spell from a script does not count.
