import std/sequtils
import sqnim
import ../game/engine
import ../game/room
import ../game/thread
import ../script/squtils
import ../util/easing
import ../audio/audio

proc soundDef*(id: int): SoundDefinition =
  for sound in gEngine.audio.soundDefs:
    if sound.id == id:
      return sound
  nil

proc soundDef*(v: HSQUIRRELVM, i: int): SoundDefinition =
  var id: int
  if SQ_SUCCEEDED(get(v, i, id)):
    result = soundDef(id)

proc sound*(id: int): SoundId =
  for sound in gEngine.audio.sounds:
    if not sound.isNil and sound.id == id:
      return sound
  nil

proc sound*(v: HSQUIRRELVM, i: int): SoundId =
  var id: int
  if SQ_SUCCEEDED(get(v, i, id)):
    result = sound(id)

proc room*(id: int): Room =
  for room in gEngine.rooms:
    if room.table.getId() == id:
      return room
  nil

proc room*(table: HSQOBJECT): Room =
  for room in gEngine.rooms:
    if room.table == table:
      return room
  nil

proc room*(v: HSQUIRRELVM, i: int): Room =
  var table: HSQOBJECT
  if SQ_SUCCEEDED(get(v, i, table)):
    result = room(table)

proc actor*(table: HSQOBJECT): Object =
  for actor in gEngine.actors:
    if actor.table == table:
      return actor
  nil

proc actor*(v: HSQUIRRELVM, i: int): Object =
  var table: HSQOBJECT
  if SQ_SUCCEEDED(get(v, i, table)):
    result = actor(table)

iterator objs*(): Object =
  for obj in gEngine.inventory:
    yield obj
  for actor in gEngine.actors:
    yield actor
  for room in gEngine.rooms:
    for layer in room.layers:
      for o in layer.objects:
        yield o

proc obj*(table: HSQOBJECT): Object =
  for obj in gEngine.inventory:
    if obj.table == table:
      return obj
  for actor in gEngine.actors:
    if actor.table == table:
      return actor
  for room in gEngine.rooms:
    for layer in room.layers:
      for o in layer.objects:
        if o.table == table:
          return o
  nil

proc obj*(v: HSQUIRRELVM, i: int): Object =
  var table: HSQOBJECT
  discard sq_getstackobj(v, i, table)
  obj(table)

proc objRoom*(table: HSQOBJECT): Room =
  for room in gEngine.rooms:
    for layer in room.layers:
      for o in layer.objects:
        if o.table == table:
          return room
  nil

proc thread*(v: HSQUIRRELVM): Thread =
  var threads = gEngine.threads.toSeq
  for t in threads:
    if t.getThread() == v:
      return t
  nil

proc thread*(id: int): Thread =
  var threads = gEngine.threads.toSeq
  for t in threads:
    if t.id == id:
      return t
  nil

proc thread*(v: HSQUIRRELVM, i: int): Thread =
  var id: int
  if SQ_SUCCEEDED(get(v, i, id)):
    result = thread(id)

proc easing*(easing: int): easing_func =
  case easing and 7:
  of 0: linear
  of 1: easeIn
  of 2: easeInOut
  of 3: easeOut
  of 4: easeIn  # TODO: slowEaseIn
  of 5: easeOut # TODO: slowEaseOut
  else: linear
