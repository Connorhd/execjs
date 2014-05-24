require 'execjs/runtime'

module ExecJS
  class RubyRacerRuntime < Runtime
    class Context < Runtime::Context
      def create_context
        @v8_context = ::V8::Context.new
      end

      def evaluate_string(str)
        @v8_context.eval(str)
      rescue ::V8::JSError => e
        if e.value['name'] == 'SyntaxError'
          raise RuntimeError, e.value.to_s
        else
          raise ProgramError, e.value.to_s
        end
      end
    end

    def name
      'therubyracer (V8)'
    end

    def available?
      require 'v8'
      true
    rescue LoadError
      false
    end
  end
end
