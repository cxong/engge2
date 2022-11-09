import glm
import node
import uinode
import textnode
import sqnim
import ../gfx/color
import ../gfx/text
import ../game/resmanager
import ../game/screen
import ../game/states/state
import ../game/states/dlgstate
import ../io/textdb
import ../script/squtils
import ../script/vm
import ../audio/audio
import optionsdlg
import saveloaddlg
import quitdlg

const
  LoadGame = 99910
  NewGame = 99912
  Options = 99913
  Help = 99961
  Quit = 99915

type StartScreen* = ref object of UINode

proc onQuitClick(node: Node, id: int) =
  case id:
  of Yes:
    quit()
  of No:
    popState(1)
  else:
    discard

proc newStartScreen*(): StartScreen

proc onLoadBackClick(node: Node, id: int) =
  popState(1)

proc onButtonDown(node: Node, id: int) =
  case id:
  of NewGame:
    popState(1)
    sqCall("start", [1])
  of Options:
    pushState newDlgState(newOptionsDialog(FromStartScreen))
  of LoadGame:
    pushState newDlgState(newSaveLoadDialog(smLoad, onLoadBackClick))
  of Quit:
    pushState newDlgState(newQuitDialog(onQuitClick))
  else:
    discard

proc onButton(src: Node, event: EventKind, pos: Vec2f, tag: pointer) =
  let id = cast[int](tag)
  case event:
  of Enter:
    src.color = Yellow
    playSoundHover()
  of Leave:
    src.color = White
  of Down:
    onButtonDown(src.getParent, id)
  else:
    discard

proc newLabel(id: int, y: float): TextNode =
  let titleTxt = newText(gResMgr.font("UIFontLarge"), getText(id), thCenter)
  result = newTextNode(titleTxt)
  result.pos = vec2(ScreenWidth/2f - titleTxt.bounds.x/2f, y)
  result.addButton(onButton, cast[pointer](id))

proc newStartScreen*(): StartScreen =
  result = StartScreen()
  result.init()
  
method activate*(self: StartScreen) =
  self.addChild newLabel(LoadGame, 600f)
  self.addChild newLabel(NewGame, 500f)
  self.addChild newLabel(Options, 400f)
  self.addChild newLabel(Help, 300f)
  self.addChild newLabel(Quit, 200f)

method deactivate*(self: StartScreen) =
  self.children.setLen 0