# -*- coding: utf-8 -*-
require "execjs/runtime"
require "open3"
require "thread"
require "json"

module ExecJS
  class PersistentExternalRuntime < Runtime
    class Context < Runtime::Context
      def create_context
        @mutex = @runtime.instance_variable_get(:@mutex)

        @mutex.synchronize do
          @runtime.send(:start_process)
        end

        runtime = @runtime
        object_id = self.object_id
        mutex = @mutex
        ObjectSpace.define_finalizer(self, proc do
          source = JSON.dump([object_id])+"\n"

          mutex.synchronize do
            runtime.send(:exec_runtime, source)
          end
        end)
      end

      def evaluate_string(str)
        str = str.gsub(/[\u0080-\uffff]/) do |ch|
          "\\u%04x" % ch.codepoints.to_a
        end

        result = @runtime.send(:exec_runtime, JSON.dump([self.object_id, str])+"\n")
        status, value = result.empty? ? [] : ::JSON.parse(result)
        if status == "ok"
          value
        elsif value =~ /SyntaxError:/
          raise RuntimeError, value
        else
          raise ProgramError, value
        end
      end
    end

    attr_reader :name

    def initialize(options)
      @name          = options[:name]
      @command       = options[:command]
      @runner_path   = options[:runner_path]
      @multi_context = options[:multi_context]
      @binary        = nil
      @mutex         = Mutex.new
    end

    def available?
      binary ? true : false
    end

    private
      def start_process
        unless defined? @stdout
          @stdin, @stdout = Open3.popen3(*(binary.split(' ') << @runner_path))
        end
      end

      def exec_runtime(source)
        @stdin.write(source)
        @stdin.flush
        @stdout.readline
      end

      def binary
        @binary ||= locate_binary
      end

      def locate_executable(cmd)
        if ExecJS.windows? && File.extname(cmd) == ""
          cmd << ".exe"
        end

        if File.executable? cmd
          cmd
        else
          path = ENV['PATH'].split(File::PATH_SEPARATOR).find { |p|
            full_path = File.join(p, cmd)
            File.executable?(full_path) && File.file?(full_path)
          }
          path && File.expand_path(cmd, path)
        end
      end


      def locate_binary
        if binary = which(@command)
          binary
        end
      end

      def which(command)
        Array(command).find do |name|
          name, args = name.split(/\s+/, 2)
          path = locate_executable(name)

          next unless path

          args ? "#{path} #{args}" : path
        end
      end
  end
end