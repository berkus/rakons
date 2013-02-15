require "rakons/file"

module Rakons

  class Target
    class TypeCompiledProgram < TypeFile; end
  end

  class CompiledProgram < GeneratedFile
    def initialize(env, name, &action)
      super env, (Target.new executableName(name),
                  Target::TypeCompiledProgram.new), &action
      @sources = []
    end
    def executableName(name)
      name
    end
    def source(*args)
      @sources.concat args.flatten
    end
    def updateNow
      super
    end
  end

  class Compiler < Tool
    #attr_reader :environment # ??
    def initialize(env = nil)
      super(env)
      FileTool.new env
    end
    def program(name, &action)
      CompiledProgram.new @environment, name, &action
    end
  end
end
