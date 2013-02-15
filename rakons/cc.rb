require "rakons/compiled"
module Rakons

  class Target # =============================================================
    class TypeCObject < TypeFile; end
    class TypeCSource < TypeFile; end
  end

  class CCObject < GeneratedFile # ===========================================
    def initialize env, from, to, &action
      to = Target.new to.name, Target::TypeCObject.new
      super env, from, to, &action
    end

    def updateNow
      super
      (_, t) = request @from
      cmd = nil
      generator {
        cmd = [@environment['CC'], ' -o '+path,
          @cflags, t.path].flatten.join " "
        @generatorSig << cmd
      }
      generate {
        debug ['!compile', cmd]
        Kernel.system cmd
      }
    end

  end

  class CCProgram < CompiledProgram # ========================================

    def initialize env, name, &action
      debug ['CCProgram.initialize', env.path]
      super env, name, &action
      @libs = []
      @ldflags = []
      @cflags = []
      @cxxflags = []
      @linksrc = []
    end
    
    def updateNow
      super
      @sources.each { |s|
        (_, o) = request Target::TypeCObject.new, s
        @linksrc.push o.path
      }
      cmd = nil
      generator {
        @libflags = []
        @libs.each { |f| @libflags << '-l'+f }
        cmd = [@environment['LINK'], ' -o '+path,
          @ldflags, @libflags, @linksrc].flatten.join " "
        @generatorSig << cmd
      }
      generate {
        debug ['!link', cmd]
        Kernel.system cmd
      }
    end

    def library(*args)
      @libs.concat args.flatten
    end

    def ldflags(*args)
      @ldflags.concat args.flatten
    end

    def cflags(*args)
      @cflags.concat args.flatten
    end

    def cxxflags(*args)
      @cxxflags.concat args.flatten
    end

  end

  class CC < Compiler # ======================================================
    def name
      :cc
    end

    def initialize env = nil
      super env
      debug ['CC: initialize']
      env.setDefault('LINK', 'gcc')
      env.setDefault('CC', 'gcc -c')
      @srcpat = /^(.*)\.(c|cc|cpp|C)$/
      Rule.from env, 1000, CCObject.promise do
        |env, from|
        if from.name =~ @srcpat
          n = from.name.gsub @srcpat, '\1.o'
          Target.new n, Target::TypeCObject.new
        else
          nil
        end
      end
    end

    def isSource? file
      from.name =~ @srcpat
    end

    def program(name, &action)
      CCProgram.new @environment, name, &action
    end

  end

end
