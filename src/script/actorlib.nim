import std/logging
import std/strformat
import std/options
import glm
import sqnim
import squtils
import vm
import ../game/engine
import ../game/actor
import ../game/actoranim
import ../game/ids
import ../scenegraph/hud
import ../game/walkbox
import ../util/utils
import ../util/vecutils
import ../game/room
import ../gfx/color
import ../gfx/graphics
import ../gfx/recti
import ../scenegraph/node
import ../scenegraph/actorswitcher
import ../game/motors/motor

proc getFacing(dir: int, facing: Facing): Facing =
  if dir == 0:
    return facing
  if dir == 0x10: getOppositeFacing(facing) else: dir.Facing

proc actorAlpha(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Sets the transparency for an actor's image in [0.0..1.0]
  let actor = obj(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var alpha: float
  if SQ_FAILED(get(v, 3, alpha)):
    return sq_throwerror(v, "failed to get alpha")
  info fmt"actorAlpha({actor.key}, {alpha})"
  actor.node.alpha = alpha
  0

proc actorAnimationFlags(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var actor = obj(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  push(v, actor.animFlags)
  1

proc actorAnimationNames(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")

  var table: HSQOBJECT
  if SQ_FAILED(get(v, 3, table)):
    return sq_throwerror(v, "failed to get table")
  if not sq_istable(table):
    return sq_throwerror(v, "failed to get animation table")

  var
    head: string
    stand: string
    walk: string
    reach: string
  table.getf("head", head)
  table.getf("stand", stand)
  table.getf("walk", walk)
  table.getf("reach", reach)
  actor.setAnimationNames(head, stand, walk, reach)

proc actorAt(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Moves the specified actor to the room and x, y coordinates specified.
  ## Also makes the actor face to given direction (options are: FACE_FRONT, FACE_BACK, FACE_LEFT, FACE_RIGHT).
  ## If using a spot, moves the player to the spot as specified in a Wimpy file.
  let numArgs = sq_gettop(v)
  case numArgs:
  of 3:
    let actor = actor(v, 2)
    if actor.isNil:
      return sq_throwerror(v, "failed to get actor")
    let spot = obj(v, 3)
    if not spot.isNil:
      let pos = spot.node.pos + spot.usePos
      actor.setRoom spot.room
      actor.stopWalking()
      info fmt"actorAt {actor.key} at {spot.key}, room '{spot.room.name}'"
      actor.node.pos = pos
      actor.setFacing(getFacing(spot.useDir.SQInteger, actor.getFacing))
    else:
      let room = room(v, 3)
      if room.isNil:
        return sq_throwerror(v, "failed to get spot or room")
      info fmt"actorAt {actor.key} room '{room.name}'"
      actor.stopWalking()
      actor.setRoom room
    0
  of 4:
    let actor = actor(v, 2)
    if actor.isNil:
      return sq_throwerror(v, "failed to get actor")
    var x, y: int
    if SQ_FAILED(get(v, 3, x)):
      return sq_throwerror(v, "failed to get x")
    if SQ_FAILED(get(v, 4, y)):
      return sq_throwerror(v, "failed to get y")
    info fmt"actorAt {actor.key} room {x}, {y}"
    actor.stopWalking()
    actor.node.pos = vec2f(x.float32, y.float32)
    0
  of 5, 6:
    let actor = actor(v, 2)
    if actor.isNil:
      return sq_throwerror(v, "failed to get actor")
    let room = room(v, 3)
    if room.isNil:
      return sq_throwerror(v, "failed to get room")
    var x, y: int
    if SQ_FAILED(get(v, 4, x)):
      return sq_throwerror(v, "failed to get x")
    if SQ_FAILED(get(v, 5, y)):
      return sq_throwerror(v, "failed to get y")
    var dir = 0
    if numArgs == 6 and SQ_FAILED(get(v, 6, dir)):
      return sq_throwerror(v, "failed to get direction")
    info fmt"actorAt {actor.key}, pos = ({x},{y}), dir = {dir}"
    actor.stopWalking()
    actor.node.pos = vec2f(x.float32, y.float32)
    actor.setFacing(getFacing(dir, actor.getFacing))
    actor.setRoom room
    0
  else:
    sq_throwerror(v, "invalid number of arguments")

proc actorBlinkRate(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var min: float
  if SQ_FAILED(get(v, 3, min)):
    return sq_throwerror(v, "failed to get min")
  var max: float
  if SQ_FAILED(get(v, 4, max)):
    return sq_throwerror(v, "failed to get max")
  actor.blinkRate(min..max)
  0

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
  let actor = actor(v, 2)
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

proc actorDistanceTo(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  let actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var obj: Object
  if sq_gettop(v) == 3:
    obj = obj(v, 3)
    if obj.isNil:
      return sq_throwerror(v, "failed to get object")
  else:
    obj = gEngine.actor
  push(v, distance(actor.node.pos, obj.getUsePos()).int)
  1

proc actorDistanceWithin(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  let nArgs = sq_gettop(v)
  if nArgs == 3:
    let actor1 = gEngine.actor
    let actor2 = actor(v, 2)
    if actor2.isNil:
      return sq_throwerror(v, "failed to get actor")
    let obj = obj(v, 3)
    if obj.isNil:
      return sq_throwerror(v, "failed to get spot")
    # not sure about this, needs to be check one day ;)
    push(v, distance(actor1.node.pos, obj.getUsePos()) < distance(actor2.node.pos, obj.getUsePos()))
    return 1
  elif nArgs == 4:
    let actor = actor(v, 2)
    if actor.isNil:
      return sq_throwerror(v, "failed to get actor")
    let obj = obj(v, 3)
    if obj.isNil:
      return sq_throwerror(v, "failed to get object")
    var dist: int
    if SQ_FAILED(get(v, 4, dist)):
      return sq_throwerror(v, "failed to get distance")
    push(v, distance(actor.node.pos, obj.getUsePos()) < dist.float)
    return 1
  else:
    return sq_throwerror(v, "actorDistanceWithin not implemented")

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
  if hidden == 1 and gEngine.actor == actor:
    gEngine.follow(nil)
  actor.node.visible = hidden == 0

proc actorInTrigger(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Returns an array of all the actors that are currently within a specified trigger box.
  ##
  ## . code-block:: Squirrel
  ## local stepsArray = triggerActors(AStreet.bookStoreLampTrigger)
  ## if (stepsArray.len()) {    // someone's on the steps
  ## }
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var obj = obj(v, 3)
  if obj.isNil:
    return sq_throwerror(v, "failed to get object")
  let inside = obj.contains(actor.node.pos)
  push(v, inside)
  1

proc actorInWalkbox(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Returns true if the specified actor is inside the specified walkbox from the wimpy file.
  ##
  ## . code-block:: Squirrel
  ## sheriffsOfficeJailDoor =
  ## {
  ##     name = "jail door"
  ##     actorInWalkbox(currentActor, "jail")
  ##     verbOpen = function()
  ##     {
  ##         if (jail_door_state == OPEN) {
  ##             sayLine("The door is already open.")
  ##         } else {
  ##             if (actorInWalkbox(currentActor, "jail")) {
  ##                 sayLine("I can't open it from in here.")
  ##                 return
  ##             } else {
  ##                startthread(openJailDoor)
  ##             }
  ##         }
  ##     }
  ## }
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var name: string
  if SQ_FAILED(get(v, 3, name)):
    return sq_throwerror(v, "failed to get name")
  for walkbox in gEngine.room.walkboxes:
    if walkbox.name == name:
      if walkbox.contains(actor.node.pos):
        push(v, true)
        return 1
  push(v, false)
  1

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

proc actorSlotSelectable(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  let nArgs = sq_gettop(v)
  case nArgs:
  of 2:
    var selectable: int
    if SQ_FAILED(get(v, 2, selectable)):
      return sq_throwerror(v, "failed to get selectable")
    case selectable:
    of 0:
      gEngine.actorSwitcher.mode.excl asOn
    of 1:
      gEngine.actorSwitcher.mode.incl asOn
    of 2:
      gEngine.actorSwitcher.mode.incl asTemporaryUnselectable
    of 3:
      gEngine.actorSwitcher.mode.excl asTemporaryUnselectable
    else:
      return sq_throwerror(v, "invalid selectable value")
    return 0
  of 3:
    var selectable: bool
    if SQ_FAILED(get(v, 3, selectable)):
      return sq_throwerror(v, "failed to get selectable")
    if sq_gettype(v, 2) == OT_INTEGER:
      var slot: int
      if SQ_FAILED(get(v, 2, slot)):
        return sq_throwerror(v, "failed to get slot")
      gEngine.hud.actorSlots[slot - 1].selectable = selectable
    else:
      var actor = actor(v, 2)
      if actor.isNil:
        return sq_throwerror(v, "failed to get actor")
      var key: string
      actor.table.getf("_key", key)
      info fmt"actorSlotSelectable({key}, {selectable})"
      var slot = gEngine.hud.actorSlot(actor)
      if slot.isNil:
        warn fmt"slot for actor {key} not found"
      else:
        slot.selectable = selectable
    return 0
  else:
    return sq_throwerror(v, "invalid number of arguments")

proc actorLockFacing(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## If a direction is specified: makes the actor face a given direction, which cannot be changed no matter what the player does.
  ## Directions are: FACE_FRONT, FACE_BACK, FACE_LEFT, FACE_RIGHT.
  ## If "NO" is specified, it removes all locking and allows the actor to change its facing direction based on player input or otherwise.
  let actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  case sq_gettype(v, 3):
  of OT_INTEGER:
    var facing = 0
    if SQ_FAILED(get(v, 3, facing)):
      return sq_throwerror(v, "failed to get facing")
    actor.lockFacing(facing)
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
  let actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var animation = ""
  if SQ_FAILED(get(v, 3, animation)):
    return sq_throwerror(v, "failed to get animation")
  var loop = 0
  if sq_gettop(v) >= 4 and SQ_FAILED(get(v, 4, loop)):
    return sq_throwerror(v, "failed to get loop")
  info fmt"Play anim {actor.key} {animation} loop={loop}"
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
  actor.node.renderOffset = vec2f(x.float32, y.float32)
  0

proc actorStand(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  actor.stand()

proc actorStopWalking(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Makes the specified actor stop moving immediately.
  ##
  ## . code-block:: Squirrel
  ## actorStopWalking(currentActor)
  ## actorStopWalking(postalworker)
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  actor.stopWalking()
  actor.stand()

proc actorTalkColors(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Set the text color of the specified actor's text that appears when they speak.
  let actor = obj(v, 2)
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
    actor = obj(v, 2)
    if actor.isNil:
      push(v, false)
      return 1
  else:
    actor = gEngine.currentActor
  let isTalking = not actor.isNil and not actor.talking.isNil and actor.talking.enabled
  push(v, isTalking)
  1

proc actorTurnTo(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Turn to the pos, dir, object or actor over 2 frames.
  let actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  if sq_gettype(v, 3) == OT_INTEGER:
    var facing = 0
    if SQ_FAILED(get(v, 3, facing)):
      return sq_throwerror(v, "failed to get facing")
    actor.turn(facing.Facing)
  else:
    let obj = obj(v, 3)
    if obj.isNil:
      return sq_throwerror(v, "failed to get object to face to")
    actor.turn(obj)
  return 0

proc actorTalkOffset(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Specifies the offset that will be applied to the actor's speech text that appears on screen.
  let actor = obj(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var x, y: int32
  if SQ_FAILED(get(v, 3, x)):
    return sq_throwerror(v, "failed to get x")
  if SQ_FAILED(get(v, 4, y)):
    return sq_throwerror(v, "failed to get y")
  actor.talkOffset = vec2(x, y)

proc actorUsePos(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var usePos: Vec2f
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var obj = obj(v, 3)
  if obj.isNil:
    usePos = vec2(0f, 0f)
  else:
    usePos = obj.usePos
  if sq_gettop(v) == 4:
    var dir: int
    if SQ_FAILED(get(v, 4, dir)):
      return sq_throwerror(v, "failed to get direction")
    else:
      actor.useDir = dir.Direction
  actor.usePos = usePos
  0

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

proc actorWalkForward(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Gets the specified actor to walk forward the distance specified.
  ##
  ## . code-block:: Squirrel
  ## script sheriffOpening2() {
  ##     cutscene(@() {
  ##         actorAt(sheriff, CityHall.spot1)
  ##         actorWalkForward(currentActor, 50)
  ##         ...
  ##     }
  ## }
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  var dist: int
  if SQ_FAILED(get(v, 3, dist)):
    return sq_throwerror(v, "failed to get dist")
  var dir: Vec2i
  case actor.getFacing():
  of FACE_FRONT:
    dir = vec2(0'i32, -dist.int32)
  of FACE_BACK:
    dir = vec2(0'i32, dist.int32)
  of FACE_LEFT:
    dir = vec2(-dist.int32, 0'i32)
  of FACE_RIGHT:
    dir = vec2(dist.int32, 0'i32)
  actor.walk(actor.node.pos + vec2f(dir))
  0

proc actorWalking(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Returns true if the specified actor is currently walking.
  ## If no actor is specified, then returns true if the current player character is walking.
  ##
  ## . code-block:: Squirrel
  ## script _startWriting() {
  ##    if (!actorWalking(this)) {
  ##        if (notebookOpen == NO) {
  ##            actorPlayAnimation(reyes, "start_writing", NO)
  ##            breaktime(0.30)
  ##        }
  ##        ...
  ##    }
  ##}
  let nArgs = sq_gettop(v)
  var actor: Object
  if nArgs == 1:
    actor = gEngine.actor
  elif nArgs == 2:
    actor = actor(v, 2)
  push(v, not actor.isNil and actor.isWalking())
  1

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
  elif nArgs == 4 or nArgs == 5:
    var x, y: int
    if SQ_FAILED(get(v, 3, x)):
      return sq_throwerror(v, "failed to get x")
    if SQ_FAILED(get(v, 4, y)):
      return sq_throwerror(v, "failed to get y")
    var facing: Option[Facing]
    if nArgs == 5:
      var dir: int
      if SQ_FAILED(get(v, 5, dir)):
        return sq_throwerror(v, "failed to get dir")
      facing = some(dir.Facing)
    actor.walk(vec2(x.float32, y.float32), facing)
  else:
    return sq_throwerror(v, "invalid number of arguments in actorWalkTo")
  0

proc addSelectableActor(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var slot: int
  if SQ_FAILED(get(v, 2, slot)):
    return sq_throwerror(v, "failed to get slot")
  var actor = actor(v, 3)
  gEngine.hud.actorSlots[slot - 1].actor = actor

proc createActor(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Creates a new actor from a table.
  ##
  ## An actor is defined in the DefineActors.nut file.
  if sq_gettype(v, 2) != OT_TABLE:
    return sq_throwerror(v, "failed to get a table")

  let actor = newActor()
  sq_resetobject(actor.table)
  discard sq_getstackobj(v, 2, actor.table)
  sq_addref(gVm.v, actor.table)
  actor.table.setId newActorId()

  var key: string
  actor.table.getf("_key", key)
  actor.key = key

  info fmt"Create actor {key} {actor.table.getId()}"
  actor.node = newNode(actor.key)
  actor.nodeAnim = newAnim(actor)
  actor.node.addChild actor.nodeAnim
  actor.node.zOrderFunc = proc (): int32 = actor.node.pos.y.int32
  actor.node.scaleFunc = proc (): float32 = actor.room.getScaling(actor.node.pos.y)
  gEngine.actors.add(actor)

  sq_pushobject(v, actor.table)
  1

proc flashSelectableActor(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var time: int
  if SQ_FAILED(get(v, 2, time)):
    return sq_throwerror(v, "failed to get time")
  gEngine.flashSelectableActor(time)
  0

proc sayOrMumbleLine(v: HSQUIRRELVM): SQInteger =
  var obj: Object
  var index: int
  var texts: seq[string]
  if sq_gettype(v, 2) == OT_TABLE:
    obj = obj(v, 2)
    index = 3
  else:
    index = 2
    obj = gEngine.currentActor

  if sq_gettype(v, index) == OT_ARRAY:
    var arr: HSQOBJECT
    discard sq_getstackobj(v, index, arr)
    for item in arr.mitems:
      texts.add $sq_objtostring(item)
  else:
    let numIds = sq_gettop(v) - index + 1
    for i in 0..<numIds:
      if sq_gettype(v, index + i) != OT_NULL:
        var text: string
        if SQ_FAILED(get(v, index + i, text)):
          return sq_throwerror(v, "failed to get text")
        texts.add text
  info fmt"sayline: {obj.key}, {texts}"
  obj.say(texts, obj.talkColor)
  0

proc sayLine(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Causes an actor to say a line of dialog and play the appropriate talking animations.
  ## In the first example, the actor ray will say the line.
  ## In the second, the selected actor will say the line.
  ## In the third example, the first line is displayed, then the second one.
  ## See also:
  ## - `mumbleLine method`
  stopTalking()
  sayOrMumbleLine(v)

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

  warn fmt"TODO: sayline: ({x},{y}) text={text} color={color} duration={duration}"
  0

proc isActorOnScreen(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## returns true if the specified actor is currently in the screen.
  let obj = obj(v, 2)
  if obj.isNil:
    return sq_throwerror(v, "failed to get actor/object")

  if obj.room != gEngine.room:
    push(v, false)
  else:
    let pos = obj.node.pos - cameraPos()
    let size = camera()
    var isOnScreen = rect(0.0f, 0.0f, size.x, size.y).contains(pos)
    push(v, isOnScreen)
  1

proc isActorSelectable(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var actor = actor(v, 2)
  if actor.isNil:
    return sq_throwerror(v, "failed to get actor")
  let slot = gEngine.hud.actorSlot(actor)
  let selectable = if slot.isNil: false else: slot.selectable
  push(v, selectable)
  1

proc is_actor(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## If an actor is specified, returns true otherwise returns false.
  let actor = actor(v, 2)
  push(v, not actor.isNil)
  1

proc masterActorArray(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Returns an array with every single actor that has been defined in the game so far, including non-player characters.
  ## See also masterRoomArray.
  let actors = gEngine.actors
  sq_newarray(v, 0)
  for actor in actors:
    push(v, actor.table)
    discard sq_arrayappend(v, -2)
  1

proc mumbleLine(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Makes actor say a line or multiple lines.
  ## Unlike sayLine this line will not interrupt any other talking on the screen.
  ## Cannot be interrupted by normal sayLines.
  ## See also:
  ## - `sayLine method`.
  sayOrMumbleLine(v)

proc stopTalking(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Stops all the current sayLines or mumbleLines that the actor is currently saying or are queued to be said.
  ## Passing ALL will stop anyone who is talking to stop.
  ## If no parameter is passed, it will stop the currentActor talking.
  let nArgs = sq_gettop(v)
  if nArgs == 2:
    if sq_gettype(v, 2) == OT_INTEGER:
        stopTalking()
    else:
      let actor = obj(v, 2);
      if actor.isNil:
        return sq_throwerror(v, "failed to get actor/object")
      actor.stopTalking()
  elif nArgs == 1:
    gEngine.actor.stopTalking()
  return 0

proc selectActor(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Causes the actor to become the selected actor.
  ## If they are in the same room as the last selected actor the camera will pan over to them.
  ## If they are in a different room, the camera will cut to the new room.
  ## The UI will change to reflect the new actor and their inventory.
  gEngine.setCurrentActor obj(v, 2)
  0

proc triggerActors(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Returns an array of all the actors that are currently within a specified trigger box.
  ##
  ## . code-block:: Squirrel
  ## local stepsArray = triggerActors(AStreet.bookStoreLampTrigger)
  ## if (stepsArray.len()) {    // someone's on the steps
  ## }
  let obj = obj(v, 2)
  if obj.isNil:
    return sq_throwerror(v, "failed to get object")
  sq_newarray(v, 0)
  for actor in gEngine.actors:
    if obj.contains(actor.node.pos):
      sq_pushobject(v, actor.table)
      discard sq_arrayappend(v, -2)
  1

proc verbUIColors(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var actorSlot: int
  if SQ_FAILED(get(v, 2, actorSlot)):
    return sq_throwerror(v, "failed to get actorSlot")
  var table: HSQOBJECT
  if SQ_FAILED(get(v, 3, table)):
    return sq_throwerror(v, "failed to get table")
  if not sq_istable(table):
    return sq_throwerror(v, "failed to get verb definitionTable")

  # get mandatory colors
  var
    sentence = 0
    verbNormal = 0
    verbNormalTint = 0
    verbHighlight = 0
    verbHighlightTint = 0
    inventoryFrame = 0
    inventoryBackground = 0
  table.getf("sentence", sentence)
  table.getf("verbNormal", verbNormal)
  table.getf("verbNormalTint", verbNormalTint)
  table.getf("verbHighlight", verbHighlight)
  table.getf("verbHighlightTint", verbHighlightTint)
  table.getf("inventoryFrame", inventoryFrame)
  table.getf("inventoryBackground", inventoryBackground)

  # get optional colors
  var
    retroNormal = verbNormal
    retroHighlight = verbNormalTint
    dialogNormal = verbNormal
    dialogHighlight = verbHighlight
  table.getf("retroNormal", retroNormal)
  table.getf("retroHighlight", retroHighlight)
  table.getf("dialogNormal", dialogNormal)
  table.getf("dialogHighlight", dialogHighlight)

  gEngine.hud.actorSlots[actorSlot - 1].verbUiColors =
    VerbUiColors(sentence: rgb(sentence), verbNormal: rgb(verbNormal),
    verbNormalTint: rgb(verbNormalTint), verbHighlight: rgb(verbHighlight), verbHighlightTint: rgb(verbHighlightTint),
    inventoryFrame: rgb(inventoryFrame), inventoryBackground: rgb(inventoryBackground),
    retroNormal: rgb(retroNormal), retroHighlight: rgb(retroHighlight),
    dialogNormal: rgb(dialogNormal), dialogHighlight: rgb(dialogHighlight))

proc register_actorlib*(v: HSQUIRRELVM) =
  ## Registers the game actor library
  ##
  ## It adds all the actor functions in the given Squirrel virtual machine.
  v.regGblFun(actorAnimationFlags, "actorAnimationFlags")
  v.regGblFun(actorAnimationNames, "actorAnimationNames")
  v.regGblFun(actorAlpha, "actorAlpha")
  v.regGblFun(actorAt, "actorAt")
  v.regGblFun(actorBlinkRate, "actorBlinkRate")
  v.regGblFun(actorColor, "actorColor")
  v.regGblFun(actorCostume, "actorCostume")
  v.regGblFun(actorDistanceTo, "actorDistanceTo")
  v.regGblFun(actorDistanceWithin, "actorDistanceWithin")
  v.regGblFun(actorFace, "actorFace")
  v.regGblFun(actorHidden, "actorHidden")
  v.regGblFun(actorHideLayer, "actorHideLayer")
  v.regGblFun(actorInTrigger, "actorInTrigger")
  v.regGblFun(actorInWalkbox, "actorInWalkbox")
  v.regGblFun(actorLockFacing, "actorLockFacing")
  v.regGblFun(actorPlayAnimation, "actorPlayAnimation")
  v.regGblFun(actorPosX, "actorPosX")
  v.regGblFun(actorPosY, "actorPosY")
  v.regGblFun(actorRenderOffset, "actorRenderOffset")
  v.regGblFun(actorRoom, "actorRoom")
  v.regGblFun(actorShowLayer, "actorShowLayer")
  v.regGblFun(actorSlotSelectable, "actorSlotSelectable")
  v.regGblFun(actorStand, "actorStand")
  v.regGblFun(actorStopWalking, "actorStopWalking")
  v.regGblFun(actorTalkColors, "actorTalkColors")
  v.regGblFun(actorTalking, "actorTalking")
  v.regGblFun(actorTalkOffset, "actorTalkOffset")
  v.regGblFun(actorTurnTo, "actorTurnTo")
  v.regGblFun(actorUsePos, "actorUsePos")
  v.regGblFun(actorUseWalkboxes, "actorUseWalkboxes")
  v.regGblFun(actorVolume, "actorVolume")
  v.regGblFun(actorWalking, "actorWalking")
  v.regGblFun(actorWalkForward, "actorWalkForward")
  v.regGblFun(actorWalkSpeed, "actorWalkSpeed")
  v.regGblFun(actorWalkTo, "actorWalkTo")
  v.regGblFun(addSelectableActor, "addSelectableActor")
  v.regGblFun(createActor, "createActor")
  v.regGblFun(flashSelectableActor, "flashSelectableActor")
  v.regGblFun(is_actor, "is_actor")
  v.regGblFun(isActorOnScreen, "isActorOnScreen")
  v.regGblFun(isActorSelectable, "isActorSelectable")
  v.regGblFun(mumbleLine, "mumbleLine")
  v.regGblFun(masterActorArray, "masterActorArray")
  v.regGblFun(sayLine, "sayLine")
  v.regGblFun(sayLineAt, "sayLineAt")
  v.regGblFun(selectActor, "selectActor")
  v.regGblFun(stopTalking, "stopTalking")
  v.regGblFun(triggerActors, "triggerActors")
  v.regGblFun(verbUIColors, "verbUIColors")
