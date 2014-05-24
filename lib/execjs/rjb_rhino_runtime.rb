require 'execjs/runtime'

module ExecJS
  class RjbRhinoRuntime < Runtime
    class Context < Runtime::Context
      def create_context
        @rhino_context = Rjb.import('org.mozilla.javascript.Context').enter()
        @rhino_scope = @rhino_context.initStandardObjects
        Rjb.import('org.mozilla.javascript.Context').exit()
      end

      def evaluate_string(str)
        Rjb.import('org.mozilla.javascript.Context').enter(@rhino_context)
        begin
          @rhino_context.evaluateString(@rhino_scope, str, '<eval>', 1, nil).toString
        ensure
          Rjb.import('org.mozilla.javascript.Context').exit()
        end
      rescue => e
        if e.message =~ /generated bytecode for method exceeds 64K limit/
          # Rhino can fail for large scripts with optimizations enabled
          @rhino_context.setOptimizationLevel(-1)
          retry
        end
        if e.class.name == 'JavaScriptException' || e.class.name == 'EcmaError'
          raise ProgramError, e.message
        elsif e.class.name == 'JavaScriptException' || e.class.name == 'EvaluatorException'
          raise RuntimeError, e.message
        end
        raise
      end
    end

    def name
      'therubyrhino (Rhino via rjb)'
    end

    def available?
      require 'rjb'
      require 'rhino/jar_path'
      Rjb.load(Rhino::JAR_PATH)
      true
    rescue LoadError
      false
    end
  end
end
