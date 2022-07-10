import std/strformat
import glm
import sqnim
import ../debugtool
import ../../gfx/recti
import ../../game/engine
import ../../game/prefs
import ../../game/room
import ../../game/motors/motor
import ../../game/shaders
import ../../scenegraph/walkboxnode
import ../../libs/imgui
import ../../sys/app
import ../../script/vm

const
  RoomEffects = "None\0Sepia\0EGA\0VHS\0Ghost\0Black & White\0\0"
  WalkboxModes = "None\0Merged\0All\0\0"

type 
  GeneralTool = ref object of DebugTool

var 
  gGeneralVisible = true

proc newGeneralTool*(): GeneralTool =
  result = GeneralTool()

proc getRoom(data: pointer, idx: int32, out_text: ptr constChar): bool {.cdecl.} =
  if idx in 0..<gEngine.rooms.len:
    out_text[] = cast[constChar](gEngine.rooms[idx].name[0].addr)
    result = true
  else:
    result = false

method render*(self: GeneralTool) =
  if gEngine.isNil or not gGeneralVisible:
    return

  igBegin("General".cstring, addr gGeneralVisible)

  let inCutscene = not gEngine.cutscene.isNil
  let scrPos = gEngine.winToScreen(mousePos())
  let roomPos = if gEngine.room.isNil: vec2f(0f, 0f) else: gEngine.room.screenToRoom(scrPos)
  igText("In cutscene: %s", if inCutscene: "yes".cstring else: "no".cstring)
  igText("Pos (screen): (%.0f, %0.f)", scrPos.x, scrPos.y)
  igText("Pos (room): (%.0f, %0.f)", roomPos.x, roomPos.y)
  
  # camera
  igText("Camera follow: %s", if gEngine.follow.isNil: "(none)".cstring else: gEngine.follow.name.cstring)
  igText("Camera isMoving: %s", if not gEngine.cameraPanTo.isNil and gEngine.cameraPanTo.enabled: "yes".cstring else: "no")
  var camPos = gEngine.cameraPos()
  if igDragFloat2("Camera pos", camPos.arr):
    gEngine.follow = nil
    let halfScreenSize = vec2f(gEngine.room.getScreenSize()) / 2.0f
    gEngine.cameraAt(camPos - halfScreenSize)
  igText("Bounds: (%d, %d, %d, %d)", gEngine.bounds.x, gEngine.bounds.y, gEngine.bounds.w, gEngine.bounds.h)

  igText("VM stack top: %d", sq_gettop(gVm.v))
  igSeparator()
  igDragFloat("Game speed factor", gEngine.prefs.tmp.gameSpeedFactor.addr, 1'f32, 0'f32, 100'f32)
  igSeparator()

  let room = gEngine.room
  var index = gEngine.rooms.find(room).int32
  if igCombo("Room", index.addr, getRoom, nil, gEngine.rooms.len.int32, -1'i32):
    gEngine.setRoom(gEngine.rooms[index])
  
  if not room.isNil:
    igText("Sheet: %s", room.sheet[0].addr)
    igText("Size: %d x %d", room.roomSize.x, room.roomSize.y)
    igText("Fullscreen: %d", room.fullScreen)
    igText("Height: %d", room.height)
    var overlay = room.overlay
    if igColorEdit4("Overlay", overlay.arr):
      room.overlay = overlay
    var mode = gEngine.walkboxNode.mode.int32
    if igCombo("Walkbox", mode.addr, WalkboxModes):
      gEngine.walkboxNode.mode = mode.WalkboxMode

    var effect = room.effect.int32
    if igCombo("Shader", effect.addr, RoomEffects):
      room.effect = effect.RoomEffect
    igDragFloat("iFade", gShaderParams.iFade.addr, 0.01f, 0f, 1f);
    igDragFloat("wobbleIntensity", gShaderParams.wobbleIntensity.addr, 0.01f, 0f, 1f)
    igDragFloat3("shadows", gShaderParams.shadows.arr, 0.01f, -1f, 1f)
    igDragFloat3("midtones", gShaderParams.midtones.arr, 0.01f, -1f, 1f)
    igDragFloat3("highlights", gShaderParams.highlights.arr, 0.01f, -1f, 1f)

    igSeparator()
    for layer in room.layers:
      if layer.objects.len == 0:
        igText(fmt"Layer {$layer.zsort}".cstring)
      elif igTreeNode(fmt"Layer {$layer.zsort}".cstring):
        for obj in layer.objects:
          igText(fmt"{obj.name} ({obj.key})".cstring)
        igTreePop()


  # if I remove this it does not compile, why ???
  if igBeginTable("???", 1, (Borders.int or SizingFixedFit.int or Resizable.int or RowBg.int).ImGuiTableFlags):
    igEndTable()

  igEnd()
