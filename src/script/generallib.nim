import std/random as rnd
import std/logging
import std/strformat
import std/streams
import std/strutils
import std/json
import sqnim
import glm
import squtils
import vm
import ../game/camera
import ../game/screen
import ../game/verb
import ../game/prefs
import ../game/room
import ../game/resmanager
import ../game/achievementsmgr
import ../util/utils
import ../util/easing
import ../util/crc
import ../game/engine
import ../gfx/graphics
import ../gfx/spritesheet
import ../gfx/recti
import ../scenegraph/node
import ../scenegraph/hud
import ../scenegraph/dialog
import ../scenegraph/inventory
import ../io/ggpackmanager
import ../io/textdb
import ../sys/app

proc getarray(obj: HSQOBJECT, arr: var seq[HSQOBJECT]) =
  for o in obj.items:
    arr.add(o)

proc activeVerb(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  push(v, gEngine.hud.verb.id.int)
  1

proc adhocalytics(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  warn "adhocalytics not implemented"
  0

proc arrayShuffle(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  if sq_gettype(v, 2) != OT_ARRAY:
    return sq_throwerror(v, "An array is expected")
  var obj: HSQOBJECT
  discard sq_getstackobj(v, 2, obj)
  var arr: seq[HSQOBJECT]
  obj.getarray(arr)
  shuffle(arr)

  sq_newarray(v, 0)
  for o in arr:
    push(v, o)
    discard sq_arrayappend(v, -2)
  1

proc assetExists(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Returns TRUE if the specified entry exists in the assets.
  var filename: string
  if SQ_FAILED(get(v, 2, filename)):
      return sq_throwerror(v, "failed to get filename")
  push(v, gGGPackMgr.assetExists(filename))
  1

proc cameraAt(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Moves the camera to the specified x, y location.
  ## If a spot is specified, will move to the x, y specified by that spot.
  ## .. code-block:: Squirrel
  ## cameraAt(450, 128)
  ##
  ## enterRoomFromDoor(Bridge.startRight)
  ## actorAt(ray, Bridge.startLeft)
  ## actorAt(reyes, Bridge.startRight)
  ## cameraAt(Bridge.bridgeBody)
  let numArgs = sq_gettop(v)
  var pos: Vec2f
  if numArgs == 3:
    var x, y: SQInteger
    if SQ_FAILED(sq_getinteger(v, 2, x)):
      return sq_throwerror(v, "failed to get x")
    if SQ_FAILED(sq_getinteger(v, 3, y)):
      return sq_throwerror(v, "failed to get y")
    pos = vec2(x.float32, y.float32)
  elif numArgs == 2:
    let obj = obj(v, 2)
    if obj.isNil:
      return sq_throwerror(v, "failed to get spot or actor")
    gEngine.follow(nil)
    gEngine.setRoom(obj.room)
    pos = obj.getUsePos
  else:
    return sq_throwerror(v, fmt"invalid argument number: {numArgs}".cstring)
  gEngine.follow(nil)
  gEngine.cameraAt(pos)
  0

proc cameraBounds(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Sets how far the camera can pan.
  var xMin, xMax, yMin, yMax: int32
  if SQ_FAILED(get(v, 2, xMin)):
      return sq_throwerror(v, "failed to get xMin")
  if SQ_FAILED(get(v, 3, xMax)):
      return sq_throwerror(v, "failed to get xMax")
  if SQ_FAILED(get(v, 4, yMin)):
      return sq_throwerror(v, "failed to get yMin")
  if SQ_FAILED(get(v, 5, yMax)):
      return sq_throwerror(v, "failed to get yMax")
  gEngine.camera.bounds = rectFromMinMax(vec2f(xMin.float32, yMin.float32), vec2f(xMax.float32, yMax.float32))

proc cameraFollow(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  let actor = actor(v, 2)
  gEngine.follow(actor)
  let pos = actor.node.pos
  let oldRoom = gEngine.room
  if not actor.room.isNil:
    gEngine.setRoom(actor.room)
  if oldRoom != actor.room:
    gEngine.cameraAt(pos)
  0

proc cameraInRoom(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Moves the camera to the specified room.
  ##
  ## Does not move any of the actors.
  ##
  ## .. code-block:: Squirrel
  ## aStreetPhoneBook =
  ## {
  ##     name = "phone book"
  ##     verbLookAt = function()
  ##     {
  ##         cameraInRoom(PhoneBook)
  ##      }
  ## }
  let room = room(v, 2)
  if not room.isNil:
    gEngine.setRoom(room)
  else:
    let obj = obj(v, 2)
    if obj.isNil or obj.room.isNil:
      return sq_throwerror(v, "failed to get room")
    gEngine.setRoom(obj.room)
  0

proc cameraPanTo(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Pans the camera to the specified x, y location over the duration using the transition method.
  ## Transition methods are: EASE_IN, EASE_INOUT, EASE_OUT, LINEAR, SLOW_EASE_IN, SLOW_EASE_OUT.
  ##
  ## .. code-block:: Squirrel
  ## cameraPanTo(450, 128, pan_time, EASE_INOUT)
  ## inputOff()
  ## actorWalkTo(currentActor, Highway.detectiveSpot1)
  ## breakwhilewalking(currentActor)
  ## cameraPanTo(currentActor, 2.0)
  let numArgs = sq_gettop(v)
  var pos: Vec2f
  var duration: float
  var interpolation: InterpolationMethod
  if numArgs == 3:
    let obj = obj(v, 2)
    if obj.isNil:
      return sq_throwerror(v, "failed to get object/actor")
    pos = obj.getUsePos
    if SQ_FAILED(get(v, 3, duration)):
        return sq_throwerror(v, "failed to get duration")
    interpolation = ikLinear
  elif numArgs == 4:
    if sq_gettype(v, 2) == OT_INTEGER:
      var x: int
      if SQ_FAILED(get(v, 2, x)):
        return sq_throwerror(v, "failed to get x")
      if SQ_FAILED(get(v, 3, duration)):
        return sq_throwerror(v, "failed to get duration")
      var im: int
      if SQ_FAILED(get(v, 4, im)):
        return sq_throwerror(v, "failed to get interpolation method")
      pos = vec2(x.float32, cameraPos().y)
      interpolation = im
    else:
      let obj = obj(v, 2)
      if SQ_FAILED(get(v, 3, duration)):
        return sq_throwerror(v, "failed to get duration")
      var im: int
      if SQ_FAILED(get(v, 4, im)):
        return sq_throwerror(v, "failed to get interpolation method")
      pos = obj.node.absolutePosition()
      interpolation = im
  elif numArgs == 5:
    var x, y: int
    if SQ_FAILED(get(v, 2, x)):
      return sq_throwerror(v, "failed to get x")
    if SQ_FAILED(get(v, 3, y)):
      return sq_throwerror(v, "failed to get y")
    if SQ_FAILED(get(v, 4, duration)):
      return sq_throwerror(v, "failed to get duration")
    var im: int
    if SQ_FAILED(get(v, 5, im)):
      return sq_throwerror(v, "failed to get interpolation method")
    pos = vec2(x.float32, y.float32)
    interpolation = im
  else:
    return sq_throwerror(v, fmt"invalid argument number: {numArgs}".cstring)
  let halfScreen = vec2f(gEngine.room.getScreenSize())/2f
  info fmt"cameraPanTo: {pos}, dur={duration}, method={interpolation}"
  gEngine.follow(nil)
  gEngine.camera.panTo(pos-vec2(0f,halfScreen.y), duration, interpolation)
  0

proc cameraPos(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Returns the current camera position x, y.
  push(v, gEngine.cameraPos())
  1

proc cursorPosX(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Returns x coordinates of the mouse in screen coordinates.
  let scrPos = winToScreen(mousePos())
  push(v, scrPos.x)
  1

proc cursorPosY(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Returns y coordinates of the mouse in screen coordinates.
  let scrPos = winToScreen(mousePos())
  push(v, scrPos.y)
  1

proc sqChr(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  # Converts an integer to a char.
  var value: int
  discard get(v, 2, value)
  var s: string
  s.add(chr(value))
  push(v, s)
  1

proc distance(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  if sq_gettype(v, 2) == OT_INTEGER:
    var num1: int32
    if SQ_FAILED(get(v, 2, num1)):
      return sq_throwerror(v, "failed to get num1")
    var num2: int32
    if SQ_FAILED(get(v, 3, num2)):
      return sq_throwerror(v, "failed to get num2");
    let d = abs(num1 - num2)
    push(v, d)
    return 1
  else:
    let obj1 = obj(v, 2);
    if obj1.isNil:
      return sq_throwerror(v, "failed to get object1 or actor1")
    let obj2 = obj(v, 3)
    if obj2.isNil:
      return sq_throwerror(v, "failed to get object2 or actor2")
    let d = obj1.node.pos - obj2.node.pos
    push(v, sqrt(d.x*d.x+d.y*d.y))
    return 1

proc findScreenPosition(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  if sq_gettype(v, 2) == OT_INTEGER:
    var verb: int
    if SQ_FAILED(get(v, 2, verb)):
      return sq_throwerror(v, "failed to get verb")
    let actorSlot = gEngine.hud.actorSlot(gEngine.actor)
    for i in 1..<actorSlot.verbs.len:
      let vb = actorSlot.verbs[i]
      if vb.id.int == verb:
        let verbSheet = gResMgr.spritesheet("VerbSheet")
        let verbFrame = verbSheet.frame(fmt"{vb.image}_en")
        let pos = vec2(verbFrame.spriteSourceSize.x.float32 + verbFrame.frame.size.x.float32/2f, verbFrame.sourceSize.y.float32 - verbFrame.spriteSourceSize.y.float32 - verbFrame.spriteSourceSize.h.float32  + verbFrame.frame.size.y.float32/2f)
        info fmt"findScreenPosition({verb}) => {pos}"
        push(v, pos)
        return 1
    return sq_throwerror(v, "failed to find verb")
  else:
    let obj = obj(v, 2)
    if obj.isNil:
      return sq_throwerror(v, "failed to get object or actor")
    if obj.inInventory():
      push(v, gEngine.uiInv.getPos(obj))
      result = 1
    else:
      let rPos = gEngine.room.roomToScreen(obj.node.pos)
      let pos = vec2(rPos.x + obj.node.size.x/2f, rPos.y + obj.node.size.y/2f)
      info fmt"findScreenPosition({obj.name}) => {pos}"
      push(v, pos)
      result = 1

proc frameCounter(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  push(v, gEngine.frameCounter)
  1

proc push(v: HSQUIRRELVM, node: JsonNode): SQInteger =
  case node.kind:
  of JInt:
    push(v, node.getInt())
    result = 1
  of JString:
    push(v, node.getStr())
    result = 1
  of JFloat:
    push(v, node.getFloat())
    result = 1
  else:
    result = sq_throwerror(v, "This kind of node is not supported")

proc getUserPref(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var key: string
  if SQ_FAILED(get(v, 2, key)):
    result = sq_throwerror(v, "failed to get key")
  elif hasPrefs(key):
    result = push(v, prefsAsJson(key))
  elif sq_gettop(v) == 3:
    var obj: HSQOBJECT
    discard sq_getstackobj(v, 3, obj)
    push(v, obj)
    result = 1

proc getPrivatePref(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var key: string
  if SQ_FAILED(get(v, 2, key)):
    result = sq_throwerror(v, "failed to get key")
  elif hasPrivPref(key):
    result = push(v, privPrefAsJson(key))
  elif sq_gettop(v) == 3:
    var obj: HSQOBJECT
    discard sq_getstackobj(v, 3, obj)
    push(v, obj)
    result = 1

proc incutscene(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  push(v, not gEngine.cutscene.isNil)
  1

proc indialog(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  push(v, gEngine.dlg.state != DialogState.None)
  1

proc inputVerbs(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var on: bool
  if SQ_FAILED(get(v, 2, on)):
    return sq_throwerror(v, "failed to get isActive")
  gEngine.inputState.inputVerbsActive = on
  1

proc integer(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var f = 0.0
  if SQ_FAILED(get(v, 2, f)):
    return sq_throwerror(v, "failed to get float value")
  push(v, f.int)
  1

proc is_oftype(v: HSQUIRRELVM, types: openArray[SQ_ObjectType]): SQInteger =
  push(v, sq_gettype(v, 2) in types)
  1

proc in_array(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var obj: HSQOBJECT
  sq_resetobject(obj)
  if SQ_FAILED(get(v, 2, obj)):
    return sq_throwerror(v, "Failed to get object")
  var arr: HSQOBJECT
  sq_resetobject(arr)
  if SQ_FAILED(get(v, 3, arr)):
    return sq_throwerror(v, "Failed to get array")

  var objs: seq[HSQOBJECT]
  sq_pushobject(v, arr)
  sq_pushnull(v) # null iterator
  while SQ_SUCCEEDED(sq_next(v, -2)):
    var tmp: HSQOBJECT
    discard sq_getstackobj(v, -1, tmp)
    objs.add(tmp)
    sq_pop(v, 2)  # pops key and val before the nex iteration
  sq_pop(v, 1)    # pops the null iterator

  for o in objs:
    sq_pushobject(v, obj)
    sq_pushobject(v, o)
    if sq_cmp(v) == 0:
      sq_pop(v, 2)
      push(v, 1)
      return 1
    sq_pop(v, 2)

  sq_pushinteger(v, 0)
  return 1

proc is_array(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  is_oftype(v, [OT_ARRAY])

proc is_function(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  is_oftype(v, [OT_CLOSURE, OT_NATIVECLOSURE])

proc is_string(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  is_oftype(v, [OT_STRING])

proc is_table(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  is_oftype(v, [OT_TABLE])

proc loadArray(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Returns an array of all the lines of the given `filename`.
  var orgFilename: string
  if SQ_FAILED(get(v, 2, orgFilename)):
    return sq_throwerror(v, "failed to get filename")
  info fmt"loadArray: {orgFilename}"
  let filename = getKey(orgFilename)
  let content = gGGPackMgr.loadStream(if gGGPackMgr.assetExists(filename): filename else: orgFilename).readAll
  sq_newarray(v, 0)
  for line in content.splitLines:
    sq_pushstring(v, line.cstring, -1)
    discard sq_arrayappend(v, -2)
  1

proc markAchievement(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var id: string
  if SQ_FAILED(get(v, 2, id)):
    return sq_throwerror(v, "Failed to get id")
  var earned = getPrivPref("earnedAchievements", "")
  let numArgs = sq_gettop(v)
  case numArgs:
  of 2:
    privPref("earnedAchievements", earned & '|' & id)
  of 4:
    var count, total: int
    if SQ_FAILED(get(v, 3, count)):
      return sq_throwerror(v, "Failed to get count")
    if SQ_FAILED(get(v, 4, total)):
      return sq_throwerror(v, "Failed to get total")
    if count == total:
      privPref("earnedAchievements", earned & '|' & id)
  else:
    warn fmt"markAchievement not implemented"
  0

proc markProgress(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  warn fmt"markProgress not implemented"
  0

proc markStat(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  warn fmt"markStat not implemented"
  0

proc ord(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  # Returns the internal int value of x
  var letter: SQString
  if SQ_FAILED(sq_getstring(v, 2, letter)):
    return sq_throwerror(v, "Failed to get letter")
  if letter.len > 0:
    sq_pushinteger(v, ord(letter[0]))
  else:
    sq_pushinteger(v, 0)
  1

proc pushSentence(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Executes a verb sentence as though the player had inputted/constructed it themselves.
  ## You can push several sentences one after the other.
  ## They will execute in reverse order (it's a stack).
  let nArgs = sq_gettop(v)
  var id: int
  if SQ_FAILED(get(v, 2, id)):
    return sq_throwerror(v, "Failed to get verb id")

  if id == VERB_DIALOG:
    var choice: int
    if SQ_FAILED(get(v, 3, choice)):
      return sq_throwerror(v, "Failed to get choice")
    # TODO choose(choice)
    warn "pushSentence with VERB_DIALOG not implemented"
    return 0

  var obj1, obj2: Object
  if nArgs >= 3:
    obj1 = obj(v, 3);
    if obj1.isNil:
      return sq_throwerror(v, "Failed to get obj1")
  if nArgs == 4:
    obj2 = obj(v, 4);
    if obj2.isNil:
      return sq_throwerror(v, "Failed to get obj2")
  discard gEngine.execSentence(nil, id, obj1, obj2)
  0

proc random(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Returns a random number from from to to inclusively.
  ## The number is a pseudo-random number and the game will produce the same sequence of numbers unless primed using randomSeed(seed).
  ##
  ## .. code-block:: Squirrel
  ## wait_time = random(0.5, 2.0)
  if sq_gettype(v, 2) == OT_FLOAT or sq_gettype(v, 3) == OT_FLOAT:
    var min, max: SQFloat
    discard sq_getfloat(v, 2, min)
    discard sq_getfloat(v, 3, max)
    if min > max:
      swap(min, max)
    let value = gEngine.rand.rand(min..max)
    # info fmt"rand({min}..{max}) -> {value}"
    sq_pushfloat(v, value)
  else:
    var min, max: SQInteger
    discard sq_getinteger(v, 2, min)
    discard sq_getinteger(v, 3, max)
    if min > max:
      swap(min, max)
    let value = gEngine.rand.rand(min..max)
    # info fmt"rand({min}..{max}) -> {value}"
    sq_pushinteger(v, value)
  return 1

proc randomFrom(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Selects an item randomly from the given array or listed options.
  ##
  ## .. code-block:: Squirrel
  ## local line = randomfrom(lines)
  ## breakwhiletalking(willie)
  ## mumbleLine(willie, line)
  ##
  ## local snd = randomfrom(soundBeep1, soundBeep2, soundBeep3, soundBeep4, soundBeep5, soundBeep6)
  ## playObjectSound(snd, Highway.pigeonVan)
  if sq_gettype(v, 2) == OT_ARRAY:
    var obj: HSQOBJECT
    sq_resetobject(obj)
    let size = sq_getsize(v, 2)
    let index = gEngine.rand.rand(0..size - 1)
    var i = 0
    sq_push(v, 2)  # array
    sq_pushnull(v) # null iterator
    while SQ_SUCCEEDED(sq_next(v, -2)):
      discard sq_getstackobj(v, -1, obj)
      sq_pop(v, 2) # pops key and val before the nex iteration
      if index == i:
        sq_pop(v, 2) # pops the null iterator and array
        sq_pushobject(v, obj)
        return 1
      i += 1
    sq_pop(v, 2) # pops the null iterator and array
    sq_pushobject(v, obj)
  else:
    let size = sq_gettop(v)
    let index = gEngine.rand.rand(0..size - 2)
    sq_push(v, 2 + index)
  1

proc randomOdds(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Returns TRUE or FALSE based on the percent, which needs to be from 0.0 to 1.0.
  ##
  ## A percent of 0.0 will always return FALSE and 1.0 will always return TRUE.
  ## `randomOdds(0.3333)` will return TRUE about one third of the time.
  ##
  ## .. code-block:: Squirrel
  ## if (randomOdds(0.5) { ... }
  var value = 0.0f
  if SQ_FAILED(sq_getfloat(v, 2, value)):
    return sq_throwerror(v, "failed to get value")
  let rnd = gEngine.rand.rand(0.0f..1.0f)
  let res = rnd <= value
  sq_pushbool(v, res)
  1

proc randomseed(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Initializes a new Rand state using the given seed.
  ## Providing a specific seed will produce the same results for that seed each time.
  ## The resulting state is independent of the default RNG's state.
  let nArgs = sq_gettop(v)
  case nArgs:
  of 1:
    push(v, gEngine.seed)
    return 1
  of 2:
    var seed = 0
    if sq_gettype(v, 2) == OT_NULL:
      gEngine.seedWithTime()
      return 0
    if SQ_FAILED(get(v, 2, seed)):
      return sq_throwerror(v, "failed to get seed")
    gEngine.seed = seed
    return 0
  else:
    sq_throwerror(v, "invalid number of parameters for randomseed")

proc refreshUI(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  warn fmt"refreshUI not implemented"
  0

proc screenSize(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Returns the x and y dimensions of the current screen/window.
  ##
  ## .. code-block:: Squirrel
  ## function clickedAt(x,y) {
  ##     local screenHeight = screenSize().y
  ##     local exitButtonB = screenHeight - (exitButtonPadding + 16)
  ##     if (y > exitButtonB) { ... }
  ## }
  var screen = gEngine.room.getScreenSize()
  push(v, screen)
  return 1;

proc setDebugger(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  warn "setDebugger not implemented"
  0

proc setPrivatePref(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var key: string
  if SQ_FAILED(get(v, 2, key)):
    return sq_throwerror(v, "failed to get key")
  let otype = sq_gettype(v, 3)
  case otype:
  of OT_STRING:
    var str: string
    discard get(v, 3, str)
    privPref(key, str)
  of OT_INTEGER:
    var n: int
    discard get(v, 3, n)
    privPref(key, n)
  of OT_BOOL:
    var b: bool
    discard get(v, 3, b)
    privPref(key, b)
  of OT_FLOAT:
    var f: float
    discard get(v, 3, f)
    privPref(key, f)
  else:
    warn "setPrivatePref not implemented"
  0

proc setUserPref(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var key: string
  if SQ_FAILED(get(v, 2, key)):
    return sq_throwerror(v, "failed to get key")
  let otype = sq_gettype(v, 3)
  case otype:
  of OT_STRING:
    var str: string
    discard get(v, 3, str)
    setPrefs(key, str)
  of OT_INTEGER:
    var n: int
    discard get(v, 3, n)
    setPrefs(key, n)
  of OT_BOOL:
    var b: bool
    discard get(v, 3, b)
    setPrefs(key, b)
  of OT_FLOAT:
    var f: float
    discard get(v, 3, f)
    setPrefs(key, f)
  else:
    warn "setUserPref not implemented"
  0

proc setVerb(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var actorSlot: int
  if SQ_FAILED(get(v, 2, actorSlot)):
    return sq_throwerror(v, "failed to get actor slot")
  var verbSlot: int
  if SQ_FAILED(get(v, 3, verbSlot)):
    return sq_throwerror(v, "failed to get verb slot")
  var table: HSQOBJECT
  if SQ_FAILED(get(v, 4, table)):
    return sq_throwerror(v, "failed to get verb definitionTable")
  if not sq_istable(table):
    return sq_throwerror(v, "verb definitionTable is not a table")
  var id: int
  var image: string
  var text: string
  var fun: string
  var key: string
  var flags: int
  table.getf("verb", id)
  table.getf("text", text)
  if table.rawexists("image"):
    table.getf("image", image)
  if table.rawexists("func"):
    table.getf("func", fun)
  if table.rawexists("key"):
    table.getf("key", key)
  if table.rawexists("flags"):
    table.getf("flags", flags)
  info fmt"setVerb {actorSlot}, {verbSlot}, {id}, {text}"
  gEngine.hud.actorSlots[actorSlot - 1].verbs[verbSlot] = Verb(id: id.VerbId, image: image, fun: fun, text: text, key: key, flags: flags)

proc startDialog(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  let nArgs = sq_gettop(v)
  var dialog: string
  if SQ_FAILED(get(v, 2, dialog)):
    return sq_throwerror(v, "failed to get dialog")

  var node = "start"
  if nArgs == 3:
    if SQ_FAILED(get(v, 3, node)):
      return sq_throwerror(v, "failed to get node")
  let actor = if gEngine.actor.isNil: "" else: gEngine.actor.key
  gEngine.dlg.start(actor, dialog, node)
  0

proc stopSentence(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  let nArgs = sq_gettop(v)
  case nArgs:
  of 1:
    for layer in gEngine.room.layers:
      for obj in layer.objects:
        obj.exec = nil
  of 2:
    let obj = obj(v, 2)
    obj.exec = nil
  else:
    warn fmt"stopSentence not implemented with {nArgs} arguments"
  0

proc strcount(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Counts the occurrences of a substring sub in the string `str`.
  var str, sub: string
  if SQ_FAILED(get(v, 2, str)):
    return sq_throwerror(v, "Failed to get str")
  if SQ_FAILED(get(v, 3, sub)):
    return sq_throwerror(v, "Failed to get sub")
  push(v, count(str, sub))
  1

proc strcrc(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Computes the CRC of a specified string `str`.
  var str: string
  if SQ_FAILED(get(v, 2, str)):
    return sq_throwerror(v, "Failed to get str")
  push(v, crc32(str).int)
  1

proc strfind(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Searches for sub in s.
  ## Searching is case-sensitive.
  ## If sub is not in s, -1 is returned.
  ## Otherwise the index is returned.
  var str, sub: string
  if SQ_FAILED(get(v, 2, str)):
    return sq_throwerror(v, "Failed to get str")
  if SQ_FAILED(get(v, 3, sub)):
    return sq_throwerror(v, "Failed to get sub")
  push(v, find(str, sub))
  1

proc strfirst(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Returns the first character of the given `string`.
  var str: string
  if SQ_FAILED(get(v, 2, str)):
    return sq_throwerror(v, "Failed to get str")
  if str.len > 0:
    push(v, str[0..0])
  else:
    push(v, "")
  1

proc strlast(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Returns the last character of the given `string`.
  var str: string
  if SQ_FAILED(get(v, 2, str)):
    return sq_throwerror(v, "Failed to get str")
  if str.len > 0:
    push(v, str[^1..^1])
  else:
    push(v, "")
  1

proc strlines(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Splits the string `str` into its containing lines.
  var str: string
  if SQ_FAILED(get(v, 2, str)):
    return sq_throwerror(v, "Failed to get str")
  sq_newarray(v, 0)
  for line in str.splitLines():
    push(v, line)
    discard sq_arrayappend(v, -2)
  1

proc strreplace(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Replaces every occurrence of the string sub in s with the string by.
  var str, sub, by: string
  if SQ_FAILED(get(v, 2, str)):
    return sq_throwerror(v, "Failed to get str")
  if SQ_FAILED(get(v, 3, sub)):
    return sq_throwerror(v, "Failed to get sub")
  if SQ_FAILED(get(v, 4, by)):
    return sq_throwerror(v, "Failed to get by")
  push(v, replace(str, sub, by))
  1

proc strsplit(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  ## Splits the string `str` into substrings using a string separator.
  var str, delimiter: string
  if SQ_FAILED(get(v, 2, str)):
    return sq_throwerror(v, "Failed to get str")
  if SQ_FAILED(get(v, 3, delimiter)):
    return sq_throwerror(v,   "Failed to get delimiter")
  sq_newarray(v, 0)
  for tok in str.split(delimiter):
    push(v, tok)
    discard sq_arrayappend(v, -2)
  1

proc translate(v: HSQUIRRELVM): SQInteger {.cdecl.} =
  var text: string
  if SQ_FAILED(get(v, 2, text)):
    return sq_throwerror(v, "Failed to get text")
  let newText = getText(text)
  # info fmt"translate({text}): {newText}"
  push(v, newText)
  1

proc register_generallib*(v: HSQUIRRELVM) =
  ## Registers the game general library
  ##
  ## It adds all the general functions in the given Squirrel virtual machine.
  v.regGblFun(activeVerb, "activeVerb")
  v.regGblFun(adhocalytics, "adhocalytics")
  v.regGblFun(arrayShuffle, "arrayShuffle")
  v.regGblFun(assetExists, "assetExists")
  v.regGblFun(cameraAt, "cameraAt")
  v.regGblFun(cameraBounds, "cameraBounds")
  v.regGblFun(cameraFollow, "cameraFollow")
  v.regGblFun(cameraInRoom, "cameraInRoom")
  v.regGblFun(cameraPanTo, "cameraPanTo")
  v.regGblFun(cameraPos, "cameraPos")
  v.regGblFun(sqChr, "chr")
  v.regGblFun(cursorPosX, "cursorPosX")
  v.regGblFun(cursorPosY, "cursorPosY")
  v.regGblFun(distance, "distance")
  v.regGblFun(findScreenPosition, "findScreenPosition")
  v.regGblFun(frameCounter, "frameCounter")
  v.regGblFun(getPrivatePref, "getPrivatePref")
  v.regGblFun(getUserPref, "getUserPref")
  v.regGblFun(incutscene, "incutscene")
  v.regGblFun(indialog, "indialog")
  v.regGblFun(inputVerbs, "inputVerbs")
  v.regGblFun(integer, "int")
  v.regGblFun(in_array, "in_array")
  v.regGblFun(is_array, "is_array")
  v.regGblFun(is_function, "is_function")
  v.regGblFun(is_string, "is_string")
  v.regGblFun(is_table, "is_table")
  v.regGblFun(loadArray, "loadArray")
  v.regGblFun(markAchievement, "markAchievement")
  v.regGblFun(markProgress, "markProgress")
  v.regGblFun(markStat, "markStat")
  v.regGblFun(ord, "ord")
  v.regGblFun(pushSentence, "pushSentence")
  v.regGblFun(random, "random")
  v.regGblFun(randomFrom, "randomfrom")
  v.regGblFun(randomOdds, "randomOdds")
  v.regGblFun(randomOdds, "randomodds")
  v.regGblFun(randomseed, "randomseed")
  v.regGblFun(refreshUI, "refreshUI")
  v.regGblFun(screenSize, "screenSize")
  v.regGblFun(setDebugger, "setDebugger")
  v.regGblFun(setPrivatePref, "setPrivatePref")
  v.regGblFun(setUserPref, "setUserPref")
  v.regGblFun(setVerb, "setVerb")
  v.regGblFun(startDialog, "startDialog")
  v.regGblFun(stopSentence, "stopSentence")
  v.regGblFun(strcrc, "strcrc")
  v.regGblFun(strcount, "strcount")
  v.regGblFun(strfind, "strfind")
  v.regGblFun(strfirst, "strfirst")
  v.regGblFun(strlast, "strlast")
  v.regGblFun(strlines, "strlines")
  v.regGblFun(strreplace, "strreplace")
  v.regGblFun(strsplit, "strsplit")
  v.regGblFun(translate, "translate")
