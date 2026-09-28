---
type: Decision
title: ActionScript 2 census of the vanilla menus
description: What the vanilla Interface movies execute - the closed 56-opcode set, the opcodes
  that never appear, the host API name distribution, class registration, and the GameDelegate
  bridge - measured to bound the AS2 runtime.
tags: [decision, swf, as2, ui, scaleform, census]
---

# ActionScript 2 census of the vanilla menus

This page holds the measurement behind the [AS2 runtime scope](/decisions/swf-as2-scope.md). The
numbers come from `openskycli swf action-sweep`, run over all 53 vanilla `Interface/*.swf` movies.
Its output is derived from game content, so it stays in `logs/`. Run it with
`make run-cli ARGS="swf action-sweep"`.

## Totals

- 53 movies, 0 failed.
- 3,414 action blocks: 2,163 `DoAction`, 1,127 `DoInitAction`, and 124 `CLIPACTIONS`.
- 533,562 `ACTIONRECORD`s.
- 56 distinct opcodes. None is outside the Adobe action table, every record has typed operands,
  and there are no parse warnings.
- `ActionDefineFunction2` has 10,575 records and `ActionDefineFunction` 1,323, so vanilla is mostly
  register-based SWF 7 function bodies. The highest register count is 23.
- `ActionConstantPool` has 936 records. The largest pool has 404 entries.
- `ActionWith` and `ActionTry` have 0 records.
- The largest action block is 32,240 bytes and 5,886 records.

## The opcode set

The table is the whole opcode set. There is no long tail in vanilla. `tools/probe.sh` fails if an
unknown opcode ever appears, so the claim is enforced.

| Opcode | Name | Records | Movies |
|---|---|---|---|
| `0x96` | `ActionPush` | 191,644 | 44 |
| `0x4e` | `ActionGetMember` | 83,487 | 44 |
| `0x17` | `ActionPop` | 37,127 | 44 |
| `0x4f` | `ActionSetMember` | 30,757 | 43 |
| `0x12` | `ActionNot` | 28,569 | 41 |
| `0x52` | `ActionCallMethod` | 28,074 | 44 |
| `0x9d` | `ActionIf` | 24,873 | 41 |
| `0x1c` | `ActionGetVariable` | 21,062 | 44 |
| `0x87` | `ActionStoreRegister` | 13,807 | 42 |
| `0x49` | `ActionEquals2` | 12,474 | 41 |
| `0x8e` | `ActionDefineFunction2` | 10,575 | 43 |
| `0x99` | `ActionJump` | 7,760 | 41 |
| `0x3e` | `ActionReturn` | 7,280 | 41 |
| `0x4c` | `ActionPushDuplicate` | 4,615 | 41 |
| `0x47` | `ActionAdd2` | 4,401 | 42 |
| `0x0b` | `ActionSubtract` | 2,686 | 42 |
| `0x43` | `ActionInitObject` | 2,442 | 41 |
| `0x66` | `ActionStrictEquals` | 1,876 | 35 |
| `0x67` | `ActionGreater` | 1,666 | 41 |
| `0x48` | `ActionLess2` | 1,592 | 39 |
| `0x40` | `ActionNewObject` | 1,499 | 42 |
| `0x42` | `ActionInitArray` | 1,413 | 41 |
| `0x07` | `ActionStop` | 1,379 | 41 |
| `0x3d` | `ActionCallFunction` | 1,373 | 41 |
| `0x9b` | `ActionDefineFunction` | 1,323 | 41 |
| `0x50` | `ActionIncrement` | 1,297 | 41 |
| `0x1d` | `ActionSetVariable` | 1,019 | 34 |
| `0x88` | `ActionConstantPool` | 936 | 44 |
| `0x0c` | `ActionMultiply` | 718 | 41 |
| `0x60` | `ActionBitAnd` | 693 | 34 |
| `0x0d` | `ActionDivide` | 676 | 41 |
| `0x26` | `ActionTrace` | 522 | 38 |
| `0x3a` | `ActionDelete` | 506 | 41 |
| `0x54` | `ActionInstanceOf` | 456 | 41 |
| `0x69` | `ActionExtends` | 455 | 41 |
| `0x3c` | `ActionDefineLocal` | 436 | 35 |
| `0x53` | `ActionNewMethod` | 372 | 35 |
| `0x45` | `ActionTargetPath` | 211 | 33 |
| `0x55` | `ActionEnumerate2` | 210 | 38 |
| `0x64` | `ActionBitRShift` | 203 | 33 |
| `0x61` | `ActionBitOr` | 197 | 34 |
| `0x51` | `ActionDecrement` | 192 | 41 |
| `0x2b` | `ActionCastOp` | 140 | 35 |
| `0x63` | `ActionBitLShift` | 132 | 33 |
| `0x06` | `ActionPlay` | 97 | 7 |
| `0x8c` | `ActionGoToLabel` | 80 | 4 |
| `0x44` | `ActionTypeOf` | 79 | 34 |
| `0x4b` | `ActionToString` | 69 | 30 |
| `0x65` | `ActionBitURShift` | 42 | 14 |
| `0x62` | `ActionBitXor` | 33 | 33 |
| `0x81` | `ActionGotoFrame` | 19 | 7 |
| `0x4a` | `ActionToNumber` | 9 | 9 |
| `0x3b` | `ActionDelete2` | 3 | 2 |
| `0x3f` | `ActionModulo` | 3 | 3 |
| `0x22` | `ActionGetProperty` | 2 | 1 |
| `0x23` | `ActionSetProperty` | 1 | 1 |

## What never appears

Each absence removes a whole subsystem from the interpreter:

- `ActionWith`: no `with` block, so the scope chain is plain (locals, `this`, the target timeline,
  then `_global`) with no dynamic scope stack.
- `ActionTry` and `ActionThrow`: no exception handling or unwinding. A runtime error is a logged
  diagnostic, not an AS2 exception.
- `ActionSetTarget` and `ActionSetTarget2`: no SWF 3 style retargeting of the current timeline.
- `ActionGetURL` and `ActionGetURL2`: nothing loads an external document or opens a browser, which
  also removes a class of security concern.
- `ActionWaitForFrame` and `ActionWaitForFrame2`: no frame gating for streamed downloads.
- `ActionEnumerate`: only the object form, `ActionEnumerate2`, appears.
- The wider SWF 3 and SWF 4 set, such as `ActionStringAdd`, `ActionStringEquals`,
  `ActionMBSubstring`, `ActionCloneSprite`, `ActionStartDrag`, `ActionGotoFrame2`, and `ActionCall`.
  Vanilla is compiled AS2, not hand-written AS1.
- `ActionGetProperty` (2) and `ActionSetProperty` (1) are so rare that properties are reached by name
  through `ActionGetMember` and `ActionSetMember` instead.

## Host API names

The sweep finds 3,382 distinct host API names, and that, not the opcode count, is the real cost. A
name is found by looking at the record before an `ActionGetMember`, `ActionSetMember`,
`ActionCallMethod`, `ActionCallFunction`, `ActionGetVariable`, `ActionSetVariable`,
`ActionNewMethod`, or `ActionDefineLocal`. If that record is an `ActionPush` whose top value is a
string or a constant-pool index, the name is resolved against the block's latest
`ActionConstantPool`. No operand stack is simulated. The head, as `name count movies`:

```text
gfx 8094 41, _global 3526 42, Shared 2316 41, prototype 1987 41, ui 1935 41,
NavigationCode 1669 34, io 1596 38, addProperty 1535 34, GameDelegate 1520 38,
length 1513 41, Selection 1104 35, _disabled 1088 34, PlayerInfoCard_mc 973 7,
utils 968 34, _parent 927 41, dispatchEvent 924 34, gotoAndStop 909 39,
ASSetPropFlags 894 41, events 891 34, textField 852 36, Math 847 39, managers 828 34,
EventDispatcher 789 34, GlobalFunc 747 39, controls 738 34, _name 713 41,
Constraints 712 34, setState 697 34, call 689 38, _focused 676 34,
addEventListener 661 34, EntriesA 652 15, MovieClip 630 41, focusIndicator 611 34,
SetText 595 31, _width 589 35, Stage 540 42, iSelectedIndex 539 15, text 538 29,
push 530 41, __width 520 34, thumb 516 18, __set__disabled 504 34, _height 494 36,
ButtonChange 467 29, LoginPage_mc 459 5, _x 452 36, toString 449 41,
InventoryDefines 445 8, setFocus 445 35, gotoAndPlay 422 41, FocusHandler 420 34,
__get__entryList 412 15, _CategoriesList 409 9, x 409 40, _instance 408 34,
initialized 408 39, dispatchEventAndSound 394 33, Components 393 30, __height 390 34,
TextField 382 41, navEquivalent 382 41, Proxy 366 28, track 361 18
```

- `gfx` leads every game-specific name. The menus are built on Scaleform's stock CLIK component
  library (`gfx.controls`, `gfx.managers`, `gfx.events`, `gfx.ui`, `gfx.io`), not on custom
  Bethesda code. Implementing that library once serves nearly every menu.
- The head is short and the tail is long. A few dozen names cover most uses. The rest are per-menu
  names such as `InventoryDefines` (8 movies) and `LoginPage_mc` (5 movies).
- The count is noisy both ways. It includes local variables and plain object properties, and it
  misses names computed at run time. It is a scale and a ranking, not an exact API list.

## Menus are class libraries

`inventorymenu.swf` has 45 `DoInitAction` tags and one 360-byte frame-1 `DoAction`. `hudmenu.swf`
has 42 `DoInitAction` tags. Even `book.swf` has 5 `DoInitAction` and one 149-byte `DoAction`. Each
`DoInitAction` defines classes and registers them against a sprite symbol, and the frame-1 block only
starts things. So the runtime order is:

1. Run each sprite's `DoInitAction` block, in tag order, before the main timeline advances.
2. Run the main timeline's frame `DoAction`.
3. Create the registered class when its symbol is placed, and dispatch `construct`.

Only three of the nineteen `CLIPEVENTFLAGS` events appear: `construct` (122 handlers in 24 movies),
`load` (1), and `enterFrame` (1). No mouse or key clip event appears. Input reaches a menu through
CLIK (`EventDispatcher`, `addEventListener`, `dispatchEvent`, `FocusHandler`, `NavigationCode`), so
input goes to the focused CLIK component through its focus path. Routed into clip events, it would
reach nothing.

## GameDelegate

`GameDelegate` (1,520 uses in 38 movies) lives in `gfx.io` (1,596 uses in 38 movies), and nearly
every menu that talks to the game uses it. OpenSky adopts its shape instead of inventing a bridge,
so the vanilla movies work unchanged. It works both ways:

- The movie registers named callbacks, and the engine calls them with arguments to push state, such
  as inventory contents or an activation prompt.
- The movie calls named host functions, and the engine handles them, such as a selection or a close
  request.

The delegate is only the data channel. Focus, navigation, and sound go through the CLIK managers.
