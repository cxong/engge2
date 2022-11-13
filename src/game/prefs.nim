import std/os
import std/macros
import std/strutils
import std/strformat
import std/json

const
  PreferencesFileName = "Prefs.json"
  Lang* = "language"
  LangDefValue* = "en"
  UiBackingAlpha* = "uiBackingAlpha"
  UiBackingAlphaDefValue* = 0.33f
  InvertVerbHighlight* = "invertVerbHighlight"
  InvertVerbHighlightDefValue* = false
  RetroVerbs* = "retroVerbs"
  RetroVerbsDefValue* = false
  RetroFonts* = "retroFonts"
  RetroFontsDefValue* = false
  Language* = "language"
  ClassicSentence* = "hudSentence"
  ClassicSentenceDefValue* = false
  Controller* = "controller"
  ControllerDefValue* = false
  ScrollSyncCursor* = "controllerScollLockCursor"
  ScrollSyncCursorDefValue* = true
  DisplayText* = "talkiesShowText"
  DisplayTextDefValue* = true
  HearVoice* = "talkiesHearVoice"
  HearVoiceDefValue* = true
  SayLineSpeed* = "sayLineSpeed"
  SayLineSpeedDefValue* = 0.5f
  SayLineBaseTime* = "sayLineBaseTime"
  SayLineBaseTimeDefValue* = 1.5f
  SayLineCharTime* = "sayLineCharTime"
  SayLineCharTimeDefValue* = 0.025f
  SayLineMinTime* = "sayLineMinTime"
  SayLineMinTimeDefValue* = 0.2f
  ToiletPaperOver* = "toiletPaperOver"
  ToiletPaperOverDefValue* = false
  AnnoyingInJokes* = "annoyingInJokes"
  AnnoyingInJokesDefValue* = false
  RansomeUnbeeped* = "forceRansomeUnbeeped"
  RansomeUnbeepedDefValue* = false
  SafeArea = "safeScale"
  Fullscreen* = "windowFullscreen"
  FullscreenDefValue* = false
  RightClickSkipsDialog = "rightClickSkipsDialog"
  KeySkipText* = "keySkipText"
  KeySkipTextDefValue* = "."
  KeySelect1* = "keySelect1"
  KeySelect1DefValue* = "1"
  KeySelect2* = "keySelect2"
  KeySelect2DefValue* = "2"
  KeySelect3* = "keySelect3"
  KeySelect3DefValue* = "3"
  KeySelect4* = "keySelect4"
  KeySelect4DefValue* = "4"
  KeySelect5* = "keySelect5"
  KeySelect5DefValue* = "5"
  KeySelect6* = "keySelect6"
  KeySelect6DefValue* = "6"
  KeySelectPrev* = "keySelectPrev"
  KeySelectPrevDefValue* = "9"
  KeySelectNext* = "keySelectNext"
  KeySelectNextDefValue* = "0"
  KeyChoice1* = "keyChoice1"
  KeyChoice1DefValue* = "1"
  KeyChoice2* = "keyChoice2"
  KeyChoice2DefValue* = "2"
  KeyChoice3* = "keyChoice3"
  KeyChoice3DefValue* = "3"
  KeyChoice4* = "keyChoice4"
  KeyChoice4DefValue* = "4"
  KeyChoice5* = "keyChoice5"
  KeyChoice5DefValue* = "5"
  KeyChoice6* = "keyChoice6"
  KeyChoice6DefValue* = "6"
  VolumeMusic* = "volumeMusic"
  VolumeSound* = "volumeSound"
  VolumeTalkies* = "volumeTalkies"
  ParrotDialogChoices = "parrotDialogChoices"
  ScrollInventorySensitivity = "scrollInventorySensitivity"
  ShowUnknownActorIcons = "showUnknownActorIcons"
  DoubleClickDefaultVerb = "doubleClickDefaultVerb"
  AlwaysFastWalk = "alwaysFastWalk"
  SaveGameName = "saveGameName"
  SaveGamePath = "saveGamePath"
  HudRetroScale = "hudRetroScale"
  HudRetroScaleDefValue = 0.8f
  HudModernScale = "hudModernScale"
  HudModernScaleDefValue = 0.025f
  InventoryPopCount* = "inventoryPopCount"
  InventoryPopCountDefValue* = 5

type
  TempPref = object
    gameSpeedFactor*: float32
    forceTalkieText*: bool
  Preferences* = object
    node*: JsonNode
    tmp*: TempPref
var
  gPrefs = Preferences()

proc init(self: var Preferences) =
  self.tmp = TempPref(gameSpeedFactor: 1'f32)
  if fileExists(PreferencesFileName):
    self.node = parseFile(PreferencesFileName)
  else:
    self.node = newJObject()

proc initPrefs*() =
  gPrefs.init()

proc tmpPrefs*(): var TempPref =
  gPrefs.tmp

proc savePrefs*() =
  writeFile PreferencesFileName, pretty(gPrefs.node, 2)

proc prefs*(name, default: string): string =
  if gPrefs.node.hasKey(name): gPrefs.node[name].str else: default

proc prefs*(name: string, default: float32): float32 =
  if gPrefs.node.hasKey(name): gPrefs.node[name].getFloat().float32 else: default

proc prefs*(name: string, default: bool): bool =
  if gPrefs.node.hasKey(name): gPrefs.node[name].getInt() != 0 else: default

proc prefs*(name: string, default: int): int =
  if gPrefs.node.hasKey(name): gPrefs.node[name].getInt() else: default

macro prefs*(name: string): untyped =
  newCall(ident("prefs"), name, ident(name.strVal & "DefValue"))

proc setPrefs*(name, value: string) =
  gPrefs.node[name] = newJString(value)
  savePrefs()

proc setPrefs*(name: string, value: float32) =
  gPrefs.node[name] = newJFloat(value)
  savePrefs()

proc setPrefs*(name: string, value: int) =
  gPrefs.node[name] = newJInt(value)
  savePrefs()

proc setPrefs*(name: string, value: bool) =
  gPrefs.node[name] = newJInt(if value: 1 else: 0)
  savePrefs()

proc prefsAsJson*(name: string): JsonNode =
  gPrefs.node[name]

proc hasPrefs*(name: string): bool =
  gPrefs.node.hasKey(name)

proc getKey*(path: string): string =
  result = path
  let (_, name, ext) = splitFile(path)
  if name.endsWith("_en"):
    let lang = prefs(Lang)
    result = fmt"{name.substr(0, name.len - 4)}_{lang}{ext}"