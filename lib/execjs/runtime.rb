require 'thread'
require 'json'

module ExecJS
  # Abstract base class for runtimes
  class Runtime
    class Context
      def initialize(runtime, source = "")
        @mutex = Mutex.new
        create_context
        exec source
      end

      def exec(source, options = {})
        eval "(function(){#{source}})()", options
      end

      def eval(source, options = {})
        source.encode!('UTF-8')

        if /\S/ =~ source
          @mutex.synchronize do
            JSON.parse(evaluate_string("JSON.stringify([#{source}])"))[0]
          end
        end
      end

      def call(properties, *args)
        eval "#{properties}.apply(this, #{JSON.dump(args)})"
      end

      protected

      def create_context
        raise NotImplementedError
      end

      def evaluate_string(str)
        raise NotImplementedError
      end
    end

    def name
      raise NotImplementedError
    end

    def context_class
      self.class::Context
    end

    def exec(source)
      context = context_class.new(self)
      context.exec(source)
    end

    def eval(source)
      context = context_class.new(self)
      context.eval(source)
    end

    def compile(source)
      context_class.new(self, source)
    end

    def deprecated?
      false
    end

    def available?
      raise NotImplementedError
    end
  end
end
