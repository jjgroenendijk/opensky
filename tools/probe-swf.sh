#!/bin/sh
# The SWF gates of tools/probe.sh, sourced by it. `run` and `fail` come from
# probe.sh; the probe log is the one argument.

probe_swf_gates() {
  swf_log="$1"
  # M8.2.1 SWF container gate: every vanilla Interface/*.swf movie parses (or,
  # for ZWS/LZMA bodies, is accounted as unsupported) with zero unexpected
  # failures. Vanilla install: 53 files, 0 unsupported, 0 failed, 0 unknown tags.
  run "swf sweep (vanilla Interface movies)" swf sweep
  grep 'swf sweep:' "$swf_log" | tail -1 | grep -q ' 0 failed' \
    || fail "swf sweep reported unexpected parse failures"

  # M8.2.2 SWF shape/bitmap gate: every DefineShape-DefineShape4 body decodes
  # and tessellates, and every bitmap tag decodes to RGBA. Vanilla install:
  # 2677 shapes, 453 bitmaps, 0 failed each.
  grep 'swf sweep shapes:' "$swf_log" | tail -1 | grep -q ' 0 failed' \
    || fail "swf sweep reported shape decode/tessellation failures"
  grep 'swf sweep bitmaps:' "$swf_log" | tail -1 | grep -q ' 0 failed' \
    || fail "swf sweep reported bitmap decode failures"

  # M8.2.3 SWF font/text gate: every DefineFont2/3 and DefineText/2/EditText body
  # decodes. Vanilla install: 97 fonts, 665 DefineEditText, 0 failed each; the
  # fontconfig report resolves all 20 aliases against the fontlib movies.
  grep 'swf sweep fonts:' "$swf_log" | tail -1 | grep -q ' 0 failed' \
    || fail "swf sweep reported font decode failures"
  grep 'swf sweep text:' "$swf_log" | tail -1 | grep -q ' 0 failed' \
    || fail "swf sweep reported text decode failures"

  # M8.2.4 SWF display-list gate: every movie's frame-1 display list assembles
  # and flattens into draw commands, and every edit text with content resolves a
  # font. Vanilla install: 53 movies, 130 frame-1 placements, 0 failed.
  grep 'swf sweep display:' "$swf_log" | tail -1 | grep -q ' 0 failed' \
    || fail "swf sweep reported display-list decode failures"
  grep 'swf sweep display text:' "$swf_log" | tail -1 | grep -q '0 edit texts without a font' \
    || fail "swf sweep found edit texts with content but no resolvable font"

  # M8.2.4 SWF render gate: every movie's frame-1 display list renders through
  # the production Metal layer over an offscreen frame. Vanilla install: 53
  # rendered, 0 failed (frames stay in memory — no --out, they embed game art).
  run "swf render-sweep (vanilla frame-1 display lists)" swf render-sweep --size 480x320
  grep 'swf render-sweep:' "$swf_log" | tail -1 | grep -q ' 0 failed' \
    || fail "swf render-sweep reported movies that did not render"

  # M12.2.3 container + barter menu gate: both vanilla movies come up through
  # ContainerMenuMovieBridge, take a published two-pane inventory, and answer
  # every engine call they make. Vanilla install: 0 faults and 0 unhandled
  # invokes each, and the barter movie's own vendor-gold field carries the
  # merchant purse.
  run "swf container-menu (containermenu.swf)" swf container-menu --mode container --down 1
  grep 'swf container-menu diagnostics:' "$swf_log" | tail -1 | grep -q ' 0 faults' \
    || fail "containermenu.swf faulted during bring-up"
  run "swf container-menu (bartermenu.swf)" swf container-menu --mode barter --transfer 1
  grep 'swf container-menu diagnostics:' "$swf_log" | tail -1 | grep -q ' 0 unhandled of ' \
    || fail "bartermenu.swf made unanswered engine calls"

  # M28 menu probes: the System page of quest_journal.swf comes up, and the race
  # menu movie starts and makes host calls.
  run "swf system-menu (quest_journal.swf System page)" swf system-menu
  grep -q 'swf probe ' "$swf_log" || fail "swf system-menu printed no host calls"
  run "swf movie-probe (racesex_menu.swf)" swf movie-probe --movie 'interface\racesex_menu.swf'
  grep -q 'swf probe ' "$swf_log" || fail "swf movie-probe printed no host calls"

  # M17.3 dialogue menu gate: the vanilla movie comes up through
  # DialogueMenuMovieBridge, publishes every entry point the bridge drives, takes
  # a published topic list and says a line. Vanilla install: 0 faults, 0 unhandled
  # invokes, 0 missing entry points.
  run "swf dialogue-menu (dialoguemenu.swf)" swf dialogue-menu --rows 4 --down 1 --speak
  grep 'swf dialogue-menu entry points:' "$swf_log" | tail -1 | grep -q ' 0 missing' \
    || fail "dialoguemenu.swf is missing an entry point the bridge drives"
  grep 'swf dialogue-menu diagnostics:' "$swf_log" | tail -1 | grep -q ' 0 faults' \
    || fail "dialoguemenu.swf faulted during bring-up"
  grep 'swf dialogue-menu diagnostics:' "$swf_log" | tail -1 | grep -q ' 0 unhandled of ' \
    || fail "dialoguemenu.swf made unanswered engine calls"

  # M8.3.1 SWF action-inventory gate: every movie's action side (DoAction,
  # DoInitAction, CLIPACTIONS) decodes with zero unexpected failures and zero
  # opcodes outside the Adobe action table. Vanilla install: 53 movies, ~3,414
  # action blocks, ~533,562 action records, ~56 distinct opcodes, 0 unknown.
  run "swf action-sweep (vanilla AS2 inventory)" swf action-sweep
  grep 'swf action-sweep:' "$swf_log" | tail -1 | grep -q ' 0 failed' \
    || fail "swf action-sweep reported movies that did not decode"
  grep 'swf action-sweep unknown:' "$swf_log" | tail -1 | grep -q '^\[INFO\] swf action-sweep unknown: 0 ' \
    || fail "swf action-sweep reported unknown AS2 opcodes"
}
