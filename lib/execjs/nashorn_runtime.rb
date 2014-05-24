require "execjs/runtime"

module ExecJS
  class NashornRuntime < Runtime
    class Context < Runtime::Context
      def create_context
        @nashorn_context = javax.script.ScriptEngineManager.new().getEngineByName("nashorn")
      end

      def evaluate_string(str)
        @nashorn_context.eval(str)
      rescue Java::JavaxScript::ScriptException => e
        if e.message =~ /^\<eval\>/
          raise RuntimeError, e.message
        else
          raise ProgramError, e.message
        end
      end
    end

    def name
      "nashorn (Java 8)"
    end

    def available?
      javax.script.ScriptEngineManager.new().getEngineByName("nashorn") != nil
    rescue NameError
      false
    end
  end
end
