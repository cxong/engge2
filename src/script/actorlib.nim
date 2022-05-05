import std/logging
import std/strformat
import std/options
import glm
import sqnim
import squtils
import vm
import ../game/engine
import ../game/actor
import ../util/utils
import ../game/room
import ../gfx/color
import ../gfx/graphics
import ../gfx/recti
import ../scenegraph/node

proc getOppositeFacing(facing: Facing): Facing =
  case facing:
  of FACE_FRONT: return FACE_BACK
  of FACE_BACK:return FACE_FRONT
  of FACE_LEFT:return FACE_RIGHT
  of FACE_RIGHT:return FACE_LEFT

proc getFacing(dir: SQInteger, facing: Facing): Facing =
  if dir == 0x10: getOppositeFacing(facing) else: dir.Facing

proc getFacingToFaceTo(actor: Object, obj: Object): Facing =
  let d = obj.node.pos - actor.node.pos
  if d.x == 0:
    result = if d.y > 0: FACE_FRONT else: FACE_BACK
  else:
    result = if d.x > 0: FACE_RIGHT else: FACE_LEFT

proc actorAlpha(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Sets the transparency for an actor's image in [0.0..1.0]
  var actor = obj(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var alpha: float
  if SQ_FAILED(get(v, 3, alpha)):
    return sq_throwerror(v, "failed to get alpha")
  actor.node.alpha = alpha
  0

proc actorAt(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Moves the specified actor to the room and x, y coordinates specified.
  ## Also makes the actor face to given direction (options are: FACE_FRONT, FACE_BACK, FACE_LEFT, FACE_RIGHT).
  ## If using a spot, moves the player to the spot as specified in a Wimpy file.
  let numArgs = sq_gettop(v)
  case numArgs:
  of 3:
    var actor = actor(v, 2)
    if actor.isNil:
      return sq_throwerror(v, "failed to get actor")
    info fmt"actorAt {actor.name}"
    var spot = obj(v, 3)
    if not spot.isNil:
      let pos = spot.node.pos + spot.usePos
      actor.room = spot.room
      actor.node.pos = pos
      actor.setFacing(getFacing(spot.useDir.SQInteger, actor.getFacing))
    else:
      var room = room(v, 3)
      if room.isNil:
        return sq_throwerror(v, "failed to get spot or room")
      actor.room = room
    0
  of 4:
    var actor = actor(v, 2)
    if actor.isNil:
      return sq_throwerror(v, "failed to get actor")
    var x, y: SQInteger
    if SQ_FAILED(sq_getinteger(v, 3, x)):
      return sq_throwerror(v, "failed to get x")
    if SQ_FAILED(sq_getinteger(v, 4, y)):
      return sq_throwerror(v, "failed to get y")
    actor.node.pos = vec2f(x.float32, y.float32)
    0
  of 5, 6:
    var actor = actor(v, 2)
    if actor.isNil:
      return sq_throwerror(v, "failed to get actor")
    var room = room(v, 3)
    if room.isNil:
      return sq_throwerror(v, "failed to get room")
    var x, y: SQInteger
    if SQ_FAILED(sq_getinteger(v, 4, x)):
      return sq_throwerror(v, "failed to get x")
    if SQ_FAILED(sq_getinteger(v, 5, y)):
      return sq_throwerror(v, "failed to get y")
    var dir = 0.SQInteger
    if numArgs == 6 and SQ_FAILED(sq_getinteger(v, 6, dir)):
      return sq_throwerror(v, "failed to get direction")
    actor.node.pos = vec2f(x.float32, y.float32)
    actor.setFacing(getFacing(dir, actor.getFacing))
    actor.room = room
    0
  else:
    sq_throwerror(v, "invalid number of arguments")

proc actorColor(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Adjusts the colour of the actor. 
  ## 
  ## . code-block:: Squirrel
  ## actorColor(coroner, 0xc0c0c0)
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var c: SQInteger
  if SQ_FAILED(sq_getinteger(v, 3, c)):
    return sq_throwerror(v, "failed to get color")
  actor.node.color = rgba(c)
  0

proc actorCostume(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Sets the actor's costume to the (JSON) filename animation file.
  ## If the actor is expected to preform the standard walk, talk, stand, reach animations, they need to exist in the file.
  ## If a sheet is given, this is a sprite sheet containing all the images needed for the animation. 
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  
  var name: string
  if SQ_FAILED(get(v, 3, name)):
    return sq_throwerror(v, "failed to get name")
  
  var sheet: string
  if sq_gettop(v) == 4:
    discard get(v, 4, sheet)
  info fmt"Actor costume {name} {sheet}"
  actor.setCostume(name, sheet)

proc actorFace(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Makes the actor face a given direction.
  ## Directions are: FACE_FRONT, FACE_BACK, FACE_LEFT, FACE_RIGHT.
  ## Similar to actorTurnTo, but will not animate the change, it will instantly be in the specified direction. 
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  let nArgs = sq_gettop(v)
  if nArgs == 2:
    var dir = actor.getFacing
    push(v, dir.int)
    result = 1
  else:
    if sq_gettype(v, 3) == OT_INTEGER:
      var dir = 0
      if SQ_FAILED(get(v, 3, dir)):
        return sq_throwerror(v, "failed to get direction")
      # FACE_FLIP ?
      if dir == 0x10:
        let facing = actor.getFacing.flip()
        actor.setFacing facing
      else:
        actor.setFacing dir.Facing
    else:
      let actor2 = actor(v, 3)
      if actor2.isNil:
        return sq_throwerror(v, "failed to get actor to face to")
      let facing = getFacingToFaceTo(actor, actor2)
      actor.setFacing facing
    result = 0

proc actorHidden(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var hidden = 0
  if SQ_FAILED(get(v, 3, hidden)):
    return sq_throwerror(v, "failed to get hidden")
  actor.node.visible = hidden == 0

proc actorRoom(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  let room = actor.room
  if room.isNil:
    sq_pushnull(v)
  else:
    push(v, room.table)
  1

proc actorShowHideLayer(v: HSQUIRRELVM, visible: bool): SQInteger =
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var layer: string
  if SQ_FAILED(get(v, 3, layer)):
    return sq_throwerror(v, "failed to get layer")
  actor.showLayer(layer, visible)
  0

proc actorHideLayer(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  actorShowHideLayer(v, false)

proc actorShowLayer(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  actorShowHideLayer(v, true)

proc actorLockFacing(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## If a direction is specified: makes the actor face a given direction, which cannot be changed no matter what the player does.
  ## Directions are: FACE_FRONT, FACE_BACK, FACE_LEFT, FACE_RIGHT. 
  ## If "NO" is specified, it removes all locking and allows the actor to change its facing direction based on player input or otherwise. 
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  case sq_gettype(v, 3):
  of OT_INTEGER:
    var facing = 0
    if SQ_FAILED(get(v, 3, facing)):
      return sq_throwerror(v, "failed to get facing")
    if facing == 0:
      actor.unlockFacing()
    else:
      let allFacing = facing.Facing
      actor.lockFacing(allFacing, allFacing, allFacing, allFacing)
  of OT_TABLE:
    var obj: HSQOBJECT
    var back = FACE_BACK.int
    var front = FACE_FRONT.int
    var left = FACE_LEFT.int
    var right = FACE_RIGHT.int
    var reset = 0
    discard sq_getstackobj(v, 3, obj)
    getf(v, obj, "back", back)
    getf(v, obj, "front", front)
    getf(v, obj, "left", left)
    getf(v, obj, "right", right)
    getf(v, obj, "reset", reset)
    if reset != 0:
      actor.resetLockFacing()
    else:
      actor.lockFacing(left.Facing, right.Facing, front.Facing, back.Facing)
  else:
    return sq_throwerror(v, "unknown facing type")
  0

proc actorPosX(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  push(v, actor.node.pos.x.int)
  1

proc actorPosY(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  push(v, actor.node.pos.y.int)
  1

proc actorPlayAnimation(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Plays the specified animation from the player's costume JSON filename.
  ## If YES loop the animation. Default is NO.
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var animation = ""
  if SQ_FAILED(get(v, 3, animation)):
    return sq_throwerror(v, "failed to get animation")
  var loop = 0
  if sq_gettop(v) >= 4 and SQ_FAILED(get(v, 4, loop)):
    return sq_throwerror(v, "failed to get loop")
  info fmt"Play anim {actor.name} {animation} loop={loop}"
  # TODO: actor.stopWalking()
  actor.play(animation, loop != 0)
  0

proc actorRenderOffset(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Sets the rendering offset of the actor to x and y.
  ## 
  ## A rendering offset of 0,0 would cause them to be rendered from the middle of their image.
  ## Actor's are typically adjusted so they are rendered from the middle of the bottom of their feet.
  ## To maintain sanity, it is best if all actors have the same image size and are all adjust the same, but this is not a requirement. 
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var x, y: SQInteger
  if SQ_FAILED(sq_getinteger(v, 3, x)):
    return sq_throwerror(v, "failed to get x")
  if SQ_FAILED(sq_getinteger(v, 4, y)):
    return sq_throwerror(v, "failed to get y")
  actor.node.offset = vec2f(x.float32, y.float32)
  0

proc actorTalkColors(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Set the text color of the specified actor's text that appears when they speak. 
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var color: int
  if SQ_FAILED(get(v, 3, color)):
    return sq_throwerror(v, "failed to get talk color")
  actor.talkColor = rgb(color)

proc actorTalking(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## If an actor is specified, returns true if that actor is currently talking.
  ## If no actor is specified, returns true if the player's current actor is currently talking.
  ## 
  ## . code-block:: Squirrel
  ## actorTalking()
  ## actorTalking(vo)
  var actor: Object
  if sq_gettop(v) == 2:
    actor = actor(v, 2)
    if actor.isNil:
      return sq_throwerror(v, "failed to get actor")
  else:
    actor = gEngine.currentActor
  let isTalking = not actor.isNil and not actor.talking.isNil and actor.talking.enabled
  sq_pushbool(v, isTalking)
  1

proc actorTalkOffset(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Specifies the offset that will be applied to the actor's speech text that appears on screen.
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var x, y: SQInteger
  if SQ_FAILED(sq_getinteger(v, 3, x)):
    return sq_throwerror(v, "failed to get x")
  if SQ_FAILED(sq_getinteger(v, 4, y)):
    return sq_throwerror(v, "failed to get y")
  actor.talkOffset = vec2(x.int32, y.int32)

proc actorUseWalkboxes(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Specifies whether the actor needs to abide by walkboxes or not.
  ## 
  ## . code-block:: Squirrel
  ## actorUseWalkboxes(coroner, NO)
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var useWalkboxes = 1
  if SQ_FAILED(get(v, 3, useWalkboxes)):
    return sq_throwerror(v, "failed to get useWalkboxes")
  actor.useWalkboxes = useWalkboxes != 0

proc actorVolume(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var volume = 0.0
  if SQ_FAILED(get(v, 3, volume)):
    return sq_throwerror(v, "failed to get volume")
  actor.volume = volume

proc actorWalkSpeed(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Sets the walk speed of an actor.
  ## 
  ## The numbers are in pixel's per second.
  ## The vertical movement is typically half (or more) than the horizontal movement to simulate depth in the 2D world.
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var x, y: SQInteger
  if SQ_FAILED(sq_getinteger(v, 3, x)):
    return sq_throwerror(v, "failed to get x")
  if SQ_FAILED(sq_getinteger(v, 4, y)):
    return sq_throwerror(v, "failed to get y")
  actor.walkSpeed = vec2f(x.float32, y.float32)
  0

proc actorWalkTo(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Tells the specified actor to walk to an x/y position or to an actor position or to an object position.
  let nArgs = sq_gettop(v)
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  if nArgs == 3:
    var obj = obj(v, 3)
    if obj.isNil:
      return sq_throwerror(v, "failed to get actor or object")
    else:
      actor.walk(obj)
  elif nArgs == 4:
    var x, y: int
    if SQ_FAILED(get(v, 3, x)):
      return sq_throwerror(v, "failed to get x")
    if SQ_FAILED(get(v, 4, y)):
      return sq_throwerror(v, "failed to get y")
    actor.walk(vec2(x.float32, y.float32))
  else:
    return sq_throwerror(v, "invalid number of arguments in actorWalkTo")
  0

proc createActor(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Creates a new actor from a table.
  ## 
  ## An actor is defined in the DefineActors.nut file.
  if sq_gettype(v, 2) != OT_TABLE:
    return sq_throwerror(v, "failed to get a table")
  
  var actor = newActor()
  sq_resetobject(actor.table)
  discard sq_getstackobj(v, 2, actor.table)
  sq_addref(v, actor.table)

  info "Create actor " &  actor.getName()
  actor.node = newNode(actor.name)
  actor.node.zOrderFunc = proc (): int = actor.node.pos.y.int
  actor.node.scaleFunc = proc (): float32 = actor.room.getScaling(actor.node.pos.y)
  gEngine.actors.add(actor)

  sq_pushobject(v, actor.table)
  1

proc sayLine(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Causes an actor to say a line of dialog and play the appropriate talking animations.
  ## In the first example, the actor ray will say the line.
  ## In the second, the selected actor will say the line.
  ## In the third example, the first line is displayed, then the second one.
  ## See also:
  ## - `mumbleLine method`
  var obj: Object
  var index: int
  if sq_gettype(v, 2) == OT_TABLE:
    obj = obj(v, 2)
    index = 3
  else:
    index = 2
    obj = gEngine.currentActor
  
  var numIds = sq_gettop(v) - index + 1
  var texts: seq[string]
  for i in 0..<numIds:
    var text: string
    if SQ_FAILED(get(v, index + i, text)):
      return sq_throwerror(v, "failed to get text")
    texts.add text
  info fmt"sayline: {texts}"
  obj.say(texts, obj.talkColor)
  0

proc sayLineAt(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Say a line of dialog and play the appropriate talking animations.
  ## In the first example, the actor ray will say the line.
  ## In the second, the selected actor will say the line.
  ## In the third example, the first line is displayed, then the second one.
  ## See also:
  ## - `mumbleLine method`
  var x, y: int
  var text: string
  var duration = -1.0
  if SQ_FAILED(get(v, 2, x)):
    return sq_throwerror(v, "failed to get x")
  if SQ_FAILED(get(v, 3, y)):
    return sq_throwerror(v, "failed to get y")
  var color: Color
  if sq_gettype(v, 4) == OT_INTEGER:
    var c: int
    if SQ_FAILED(get(v, 4, c)):
      return sq_throwerror(v, "failed to get color")
    color = rgb(c)
    if SQ_FAILED(get(v, 5, duration)):
      return sq_throwerror(v, "failed to get duration")
    if SQ_FAILED(get(v, 6, text)):
      return sq_throwerror(v, "failed to get text")
  else:
    var actor = actor(v, 4)
    if actor.isNil:
      return sq_throwerror(v, "failed to get actor")
    var pos = gEngine.room.roomToScreen(actor.node.pos)
    x = pos.x.int
    y = pos.y.int
    color = actor.talkColor
    if SQ_FAILED(get(v, 6, text)):
      return sq_throwerror(v, "failed to get text")

  info fmt"TODO: sayline: ({x},{y}) text={text} color={color} duration={duration}"
  0

proc isActorOnScreen(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## returns true if the specified actor is currently in the screen.
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")

  if actor.room != gEngine.room:
    push(v, false)
  else:
    let pos = actor.node.pos - cameraPos()
    let size = camera()
    var isOnScreen = rect(0.0f, 0.0f, size.x, size.y).contains(pos)
    push(v, isOnScreen)
  1

proc is_actor(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## If an actor is specified, returns true otherwise returns false.
  var actor = actor(v, 2)
  push(v, not actor.isNil)
  1

proc masterActorArray(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Returns an array with every single actor that has been defined in the game so far, including non-player characters.
  ## See also masterRoomArray. 
  var actors = gEngine.actors
  sq_newarray(v, 0)
  for actor in actors:
    sq_pushobject(v, actor.table)
    discard sq_arrayappend(v, -2)
  1

proc mumbleLine(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Makes actor say a line or multiple lines.
  ## Unlike sayLine this line will not interrupt any other talking on the screen.
  ## Cannot be interrupted by normal sayLines.
  ## See also:
  ## - `sayLine method`. 
  # TODO: gEngine.stopTalking()
  sayLine(v)

proc selectActor(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Causes the actor to become the selected actor.
  ## If they are in the same room as the last selected actor the camera will pan over to them.
  ## If they are in a different room, the camera will cut to the new room.
  ## The UI will change to reflect the new actor and their inventory. 
  gEngine.setCurrentActor obj(v, 2)
  0

proc register_actorlib*(v: HSQUIRRELVM) =
  ## Registers the game actor library
  ## 
  ## It adds all the actor functions in the given Squirrel virtual machine.
  v.regGblFun(actorAlpha, "actorAlpha")
  v.regGblFun(actorAt, "actorAt")
  v.regGblFun(actorColor, "actorColor")
  v.regGblFun(actorCostume, "actorCostume")
  v.regGblFun(actorFace, "actorFace")
  v.regGblFun(actorHidden, "actorHidden")
  v.regGblFun(actorHideLayer, "actorHideLayer")
  v.regGblFun(actorLockFacing, "actorLockFacing")
  v.regGblFun(actorPlayAnimation, "actorPlayAnimation")
  v.regGblFun(actorPosX, "actorPosX")
  v.regGblFun(actorPosY, "actorPosY")
  v.regGblFun(actorRenderOffset, "actorRenderOffset")
  v.regGblFun(actorRoom, "actorRoom")
  v.regGblFun(actorShowLayer, "actorShowLayer")
  v.regGblFun(actorTalkColors, "actorTalkColors")
  v.regGblFun(actorTalking, "actorTalking")
  v.regGblFun(actorTalkOffset, "actorTalkOffset")
  v.regGblFun(actorUseWalkboxes, "actorUseWalkboxes")
  v.regGblFun(actorVolume, "actorVolume")
  v.regGblFun(actorWalkSpeed, "actorWalkSpeed")
  v.regGblFun(actorWalkTo, "actorWalkTo")
  v.regGblFun(createActor, "createActor")
  v.regGblFun(is_actor, "is_actor")
  v.regGblFun(isActorOnScreen, "isActorOnScreen")
  v.regGblFun(mumbleLine, "mumbleLine")
  v.regGblFun(masterActorArray, "masterActorArray")
  v.regGblFun(sayLine, "sayLine")
  v.regGblFun(sayLineAt, "sayLineAt")
  v.regGblFun(selectActor, "selectActor")