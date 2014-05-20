# -*- coding: utf-8 -*-
require "test/unit"
require "execjs/module"

begin
  require "execjs"
rescue ExecJS::RuntimeUnavailable => e
  warn e
  exit 2
end

class TestExecJS < Test::Unit::TestCase
  def test_runtime_available
    runtime = ExecJS::ExternalRuntime.new(:command => "nonexistent")
    assert !runtime.available?

    runtime = ExecJS::ExternalRuntime.new(:command => "ruby")
    assert runtime.available?
  end

  def test_runtime_assignment
    original_runtime = ExecJS.runtime
    runtime = ExecJS::ExternalRuntime.new(:command => "nonexistent")
    assert_raises(ExecJS::RuntimeUnavailable) { ExecJS.runtime = runtime }
    assert_equal original_runtime, ExecJS.runtime

    runtime = ExecJS::ExternalRuntime.new(:command => "ruby")
    ExecJS.runtime = runtime
    assert_equal runtime, ExecJS.runtime
  ensure
    ExecJS.runtime = original_runtime
  end

  def test_context_call
    context = ExecJS.compile("id = function(v) { return v; }")
    assert_equal "bar", context.call("id", "bar")
  end

  def test_nested_context_call
    context = ExecJS.compile("a = {}; a.b = {}; a.b.id = function(v) { return v; }")
    assert_equal "bar", context.call("a.b.id", "bar")
  end

  def test_context_call_missing_function
    context = ExecJS.compile("")
    assert_raises ExecJS::ProgramError do
      context.call("missing")
    end
  end

  def test_exec
    assert_nil ExecJS.exec("1")
    assert_nil ExecJS.exec("return")
    assert_nil ExecJS.exec("return null")
    assert_nil ExecJS.exec("return function() {}")
    assert_equal 0, ExecJS.exec("return 0")
    assert_equal true, ExecJS.exec("return true")
    assert_equal [1, 2], ExecJS.exec("return [1, 2]")
    assert_equal "hello", ExecJS.exec("return 'hello'")
    assert_equal({"a"=>1,"b"=>2}, ExecJS.exec("return {a:1,b:2}"))
    assert_equal "café", ExecJS.exec("return 'café'")
    assert_equal "☃", ExecJS.exec('return "☃"')
    assert_equal "☃", ExecJS.exec('return "\u2603"')
    assert_equal "\\", ExecJS.exec('return "\\\\"')
  end

  def test_eval
    assert_nil ExecJS.eval("")
    assert_nil ExecJS.eval(" ")
    assert_nil ExecJS.eval("null")
    assert_nil ExecJS.eval("function x() {}")
    assert_equal 0, ExecJS.eval("0")
    assert_equal true, ExecJS.eval("true")
    assert_equal [1, 2], ExecJS.eval("[1, 2]")
    assert_equal [1, nil], ExecJS.eval("[1, function() {}]")
    assert_equal "hello", ExecJS.eval("'hello'")
    assert_equal ["red", "yellow", "blue"], ExecJS.eval("'red yellow blue'.split(' ')")
    assert_equal({"a"=>1,"b"=>2}, ExecJS.eval("x = {a:1,b:2}"))
    assert_equal({"a"=>true}, ExecJS.eval("x = {a:true,b:function (){}}"))
    assert_equal "café", ExecJS.eval("'café'")
    assert_equal "☃", ExecJS.eval('"☃"')
    assert_equal "☃", ExecJS.eval('"\u2603"')
    assert_equal "\\", ExecJS.eval('"\\\\"')
  end

  if defined? Encoding
    def test_encoding
      utf8 = Encoding.find('UTF-8')

      assert_equal utf8, ExecJS.exec("return 'hello'").encoding
      assert_equal utf8, ExecJS.eval("'☃'").encoding

      ascii = "'hello'".encode('US-ASCII')
      result = ExecJS.eval(ascii)
      assert_equal "hello", result
      assert_equal utf8, result.encoding

      assert_raise Encoding::UndefinedConversionError do
        binary = "\xde\xad\xbe\xef".force_encoding("BINARY")
        ExecJS.eval(binary)
      end
    end

    def test_encoding_compile
      utf8 = Encoding.find('UTF-8')

      context = ExecJS.compile("foo = function(v) { return '¶' + v; }".encode("ISO8859-15"))

      assert_equal utf8, context.exec("return foo('hello')").encoding
      assert_equal utf8, context.eval("foo('☃')").encoding

      ascii = "foo('hello')".encode('US-ASCII')
      result = context.eval(ascii)
      assert_equal "¶hello", result
      assert_equal utf8, result.encoding

      assert_raise Encoding::UndefinedConversionError do
        binary = "\xde\xad\xbe\xef".force_encoding("BINARY")
        context.eval(binary)
      end
    end
  end

  def test_compile
    context = ExecJS.compile("foo = function() { return \"bar\"; }")
    assert_equal "bar", context.exec("return foo()")
    assert_equal "bar", context.eval("foo()")
    assert_equal "bar", context.call("foo")
  end

  def test_this_is_global_scope
    assert_equal true, ExecJS.eval("this === (function() {return this})()")
    assert_equal true, ExecJS.exec("return this === (function() {return this})()")
  end

  def test_commonjs_vars_are_undefined
    assert ExecJS.eval("typeof module == 'undefined'")
    assert ExecJS.eval("typeof exports == 'undefined'")
    assert ExecJS.eval("typeof require == 'undefined'")
  end

  def test_console_is_undefined
    assert ExecJS.eval("typeof console == 'undefined'")
  end

  def test_compile_large_scripts
    body = "var foo = 'bar';\n" * 100_000
    assert ExecJS.exec("function foo() {\n#{body}\n};\nreturn true")
  end

  def test_syntax_error
    assert_raise ExecJS::RuntimeError do
      ExecJS.exec(")")
    end
  end

  def test_thrown_exception
    assert_raise ExecJS::ProgramError do
      ExecJS.exec("throw 'hello'")
    end
  end

  def test_coffeescript
    require "open-uri"
    assert source = open("http://cdnjs.cloudflare.com/ajax/libs/coffee-script/1.7.1/coffee-script.min.js").read
    context = ExecJS.compile(source)
    assert_equal 64, context.call("CoffeeScript.eval", "((x) -> x * x)(8)")
    assert_equal 64, context.eval("CoffeeScript.eval('((x) -> x * x)(8)')")
  end

  def test_benchmark
    require 'coffee-script'
    require 'uglifier'
    result = ''
    100.times do
      result += CoffeeScript.compile <<-'END'
fs = require 'fs'
path = require 'path'
vm = require 'vm'
nodeREPL = require 'repl'
CoffeeScript = require './coffee-script'
{merge, updateSyntaxError} = require './helpers'

replDefaults =
  prompt: 'coffee> ',
  historyFile: path.join process.env.HOME, '.coffee_history' if process.env.HOME
  historyMaxInputSize: 10240
  eval: (input, context, filename, cb) ->
    # XXX: multiline hack.
    input = input.replace /\uFF00/g, '\n'
    # Node's REPL sends the input ending with a newline and then wrapped in
    # parens. Unwrap all that.
    input = input.replace /^\(([\s\S]*)\n\)$/m, '$1'

    # Require AST nodes to do some AST manipulation.
    {Block, Assign, Value, Literal} = require './nodes'

    try
      # Generate the AST of the clean input.
      ast = CoffeeScript.nodes input
      # Add assignment to `_` variable to force the input to be an expression.
      ast = new Block [
        new Assign (new Value new Literal '_'), ast, '='
      ]
      js = ast.compile bare: yes, locals: Object.keys(context)
      result = if context is global
        vm.runInThisContext js, filename 
      else
        vm.runInContext js, context, filename
      cb null, result
    catch err
      # AST's `compile` does not add source code information to syntax errors.
      updateSyntaxError err, input
      cb err

addMultilineHandler = (repl) ->
  {rli, inputStream, outputStream} = repl

  multiline =
    enabled: off
    initialPrompt: repl.prompt.replace /^[^> ]*/, (x) -> x.replace /./g, '-'
    prompt: repl.prompt.replace /^[^> ]*>?/, (x) -> x.replace /./g, '.'
    buffer: ''

  # Proxy node's line listener
  nodeLineListener = rli.listeners('line')[0]
  rli.removeListener 'line', nodeLineListener
  rli.on 'line', (cmd) ->
    if multiline.enabled
      multiline.buffer += "#{cmd}\n"
      rli.setPrompt multiline.prompt
      rli.prompt true
    else
      nodeLineListener cmd
    return

  # Handle Ctrl-v
  inputStream.on 'keypress', (char, key) ->
    return unless key and key.ctrl and not key.meta and not key.shift and key.name is 'v'
    if multiline.enabled
      # allow arbitrarily switching between modes any time before multiple lines are entered
      unless multiline.buffer.match /\n/
        multiline.enabled = not multiline.enabled
        rli.setPrompt repl.prompt
        rli.prompt true
        return
      # no-op unless the current line is empty
      return if rli.line? and not rli.line.match /^\s*$/
      # eval, print, loop
      multiline.enabled = not multiline.enabled
      rli.line = ''
      rli.cursor = 0
      rli.output.cursorTo 0
      rli.output.clearLine 1
      # XXX: multiline hack
      multiline.buffer = multiline.buffer.replace /\n/g, '\uFF00'
      rli.emit 'line', multiline.buffer
      multiline.buffer = ''
    else
      multiline.enabled = not multiline.enabled
      rli.setPrompt multiline.initialPrompt
      rli.prompt true
    return

# Store and load command history from a file
addHistory = (repl, filename, maxSize) ->
  lastLine = null
  try
    # Get file info and at most maxSize of command history
    stat = fs.statSync filename
    size = Math.min maxSize, stat.size
    # Read last `size` bytes from the file
    readFd = fs.openSync filename, 'r'
    buffer = new Buffer(size)
    fs.readSync readFd, buffer, 0, size, stat.size - size
    # Set the history on the interpreter
    repl.rli.history = buffer.toString().split('\n').reverse()
    # If the history file was truncated we should pop off a potential partial line
    repl.rli.history.pop() if stat.size > maxSize
    # Shift off the final blank newline
    repl.rli.history.shift() if repl.rli.history[0] is ''
    repl.rli.historyIndex = -1
    lastLine = repl.rli.history[0]

  fd = fs.openSync filename, 'a'

  repl.rli.addListener 'line', (code) ->
    if code and code.length and code isnt '.history' and lastLine isnt code
      # Save the latest command in the file
      fs.write fd, "#{code}\n"
      lastLine = code

  repl.rli.on 'exit', -> fs.close fd

  # Add a command to show the history stack
  repl.commands['.history'] =
    help: 'Show command history'
    action: ->
      repl.outputStream.write "#{repl.rli.history[..].reverse().join '\n'}\n"
      repl.displayPrompt()

module.exports =
  start: (opts = {}) ->
    [major, minor, build] = process.versions.node.split('.').map (n) -> parseInt(n)

    if major is 0 and minor < 8
      console.warn "Node 0.8.0+ required for CoffeeScript REPL"
      process.exit 1

    CoffeeScript.register()
    process.argv = ['coffee'].concat process.argv[2..]
    opts = merge replDefaults, opts
    repl = nodeREPL.start opts
    repl.on 'exit', -> repl.outputStream.write '\n'
    addMultilineHandler repl
    addHistory repl, opts.historyFile, opts.historyMaxInputSize if opts.historyFile
    # Correct the description inherited from the node REPL
    repl.commands['.load'].help = 'Load code from a file into this REPL session'
    repl
END

    end
    Uglifier.compile result
  end
end
