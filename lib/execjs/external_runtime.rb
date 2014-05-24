# -*- coding: utf-8 -*-
require 'execjs/runtime'
require 'open3'
require 'thread'
require 'json'

module ExecJS
  class ExternalRuntime < Runtime
    class Context < Runtime::Context
      def create_context
        @stdin, @stdout = @runtime.get_process
        unless @runtime.get_mutex.nil?
          @mutex = @runtime.get_mutex
        end

        runtime = @runtime
        context_id = object_id

        ObjectSpace.define_finalizer(self, proc do
          runtime.clean_up_context(context_id)
        end)
      end

      def evaluate_string(str)
        str = str.gsub(/[\u0080-\uffff]/) do |ch|
          '\\u%04x' % ch.codepoints.to_a
        end

        @stdin.write(JSON.dump([object_id, str]) + "\n")
        @stdin.flush
        result = @stdout.readline

        status, value = result.empty? ? [] : ::JSON.parse(result)
        if status == 'ok'
          value
        elsif value =~ /Syntax/
          fail RuntimeError, value
        else
          fail ProgramError, value
        end
      end
    end

    attr_reader :name

    def initialize(options)
      @name          = options[:name]
      @command       = options[:command]
      @runner_path   = options[:runner_path]
      @multi_context = !!options[:multi_context]
      @stdin         = nil
      @stdout        = nil
    end

    def available?
      binary ? true : false
    end

    def get_mutex
      @mutex ||= if @multi_context
        Mutex.new
      else
        nil
      end
    end

    def get_process
      if @multi_context && @stdout
        return @stdin, @stdout
      end
      stdin, stdout = Open3.popen3(*(binary.split(' ') << @runner_path))
      stdin.set_encoding('ASCII')
      stdout.set_encoding('UTF-8')
      if @multi_context
        @stdin, @stdout = stdin, stdout
      end
      [stdin, stdout]
    end

    def clean_up_context(context_id)
      if @multi_context
        @stdin.write(JSON.dump([context_id]) + "\n")
        @stdin.flush
        @stdout.readline
      else
        @stdin.close
        @stdout.close
      end
    end

    private

    def binary
      @binary ||= locate_binary
    end

    def locate_executable(cmd)
      if ExecJS.windows? && File.extname(cmd) == ''
        cmd << '.exe'
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
