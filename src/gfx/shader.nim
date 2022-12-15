import nglib/opengl
import std/logging
import std/strutils
import std/strformat
import std/tables
import glm
import color
import glutils
import texture

type
  TextureSlot = object
    id: int
    texture: Texture
  Shader* = object
    program*: GLuint
    vertex: GLuint
    fragment: GLuint
    textures: Table[GLint, TextureSlot]

proc statusShader(shader: uint32) =
  var status: int32
  glGetShaderiv(shader, GL_COMPILE_STATUS, status.addr)
  if status != GL_TRUE.ord:
    var
      logLength: int32
      message = newString(1024)
    glGetShaderInfoLog(shader, 1024, logLength.addr, message[0].addr)
    warn(message)

proc loadShader(code: cstring, shaderType: GLEnum): GLuint =
  result = glCreateShader(shaderType)
  glShaderSource(result, 1'i32, code.unsafeAddr, nil)
  glCompileShader(result)
  statusShader(result)

proc newShader*(vertex, fragment: string): Shader =
  if vertex.len > 0:
    result.vertex = loadShader(vertex, GL_VERTEX_SHADER)
  if fragment.len > 0:
    result.fragment = loadShader(fragment, GL_FRAGMENT_SHADER)
  result.program = glCreateProgram()
  glAttachShader(result.program, result.vertex)
  glAttachShader(result.program, result.fragment)
  glLinkProgram(result.program)

  var
    logLength: int32
    message = newString(1024)
    pLinked: int32
  glGetProgramiv(result.program, GL_LINK_STATUS, pLinked.addr)
  if pLinked != GL_TRUE.ord:
    glGetProgramInfoLog(result.program, 1024, logLength.addr, message[0].addr)
    warn(message)

template ensureProgramActive*(self: Shader, statements: untyped) =
  var prev = 0.GLint
  glGetIntegerv(GL_CURRENT_PROGRAM, addr prev)
  if prev != self.program.GLint:
    glUseProgram(self.program)
  statements
  if prev != self.program.GLint:
    glUseProgram(prev.GLuint)

proc getUniformLocation*(self: Shader, name: string): GLint =
  result = glGetUniformLocation(self.program, name.cstring)
  checkGLError(fmt"getUniformLocation({name})")

proc setUniform*(self: Shader, name: string, value: int) =
  self.ensureProgramActive():
    let loc = self.getUniformLocation(name)
    glUniform1i(loc, value.GLint)
    checkGLError(fmt"setUniform({name},{value})")

proc setUniform*(self: Shader, name: string, value: Vec2f) =
  self.ensureProgramActive():
    let loc = self.getUniformLocation(name)
    var v = value
    glUniform2fv(loc, 1, v.caddr)
    checkGLError(fmt"setUniform({name},{value})")

proc setUniform*(self: Shader, name: string, value: Vec3f) =
  self.ensureProgramActive():
    let loc = self.getUniformLocation(name)
    var v = value
    glUniform3fv(loc, 1, v.caddr)
    checkGLError(fmt"setUniform({name},{value})")

proc setUniform*(self: Shader, name: string, value: Mat4f) =
  self.ensureProgramActive():
    let loc = self.getUniformLocation(name)
    var v = value
    glUniformMatrix4fv(loc, 1, false, v.caddr)
    checkGLError(fmt"setUniform({name},{value})")

proc setUniform*(self: Shader, name: string, value: float32) =
  self.ensureProgramActive():
    let loc = self.getUniformLocation(name)
    glUniform1f(loc, value)
    checkGLError(fmt"setUniform({name},{value})")

proc setUniform*(self: Shader, name: string, value: var openArray[float32]) =
  self.ensureProgramActive():
    let loc = self.getUniformLocation(name)
    glUniform1fv(loc, value.len.GLsizei, value[0].addr)
    checkGLError(fmt"setUniform({name},{value})")

proc setUniform*(self: Shader, name: string, value: var Color) =
  self.ensureProgramActive():
    let loc = self.getUniformLocation(name)
    glUniform4f(loc, value.r, value.g, value.b, value.a)
    checkGLError(fmt"setUniform({name},{value})")

proc setUniform*(self: var Shader, name: string, value: Texture) =
  self.ensureProgramActive():
    let loc = self.getUniformLocation(name)
    let id = self.textures.len
    glUniform1i(loc.GLint, id.GLint)
    self.textures[loc] = TextureSlot(id: id, texture: value);
    checkGLError(fmt"setUniform({name},texture: {value.id})")

proc activateTextures*(self: var Shader) =
  var index = GL_TEXTURE0.int
  for (id, slot) in self.textures.pairs:
    glActiveTexture((index + slot.id).GLenum)
    glBindTexture(GL_TEXTURE_2D, slot.texture.id)
    inc index