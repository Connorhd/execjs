require 'execjs/runtime'

module ExecJS
  class RjbNashornRuntime < Runtime
    class Context < Runtime::Context
      def create_context
        @nashorn_context = Rjb.import('javax.script.ScriptEngineManager').new.getEngineByName('nashorn')
      end

      def evaluate_string(str)
        output = @nashorn_context.eval(str)
        if output.nil?
          nil
        else
          output.toString
        end
      rescue ScriptException => e
        if e.message =~ /^\<eval\>/
          raise RuntimeError, e.message
        else
          raise ProgramError, e.message
        end
      end
    end

    def name
      'nashorn (Java 8 via rjb)'
    end

    def available?
      require 'rjb'
      Rjb.load
      !Rjb.import('javax.script.ScriptEngineManager').new.getEngineByName('nashorn').nil?
    rescue LoadError
      false
    end
  end
end
