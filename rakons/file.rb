require "digest/sha1"

module Rakons
  class Target
    class TypeFile < Type; end
  end

  class Environment # ========================================================
    def file target, type = Target::TypeFile.new, &action
      File.new self, Target.new(target, type), &action
    end
  end

  class File < TransformTask # ===============================================
    attr_reader :file

    def initialize env, target, from = nil, &action
      debug ['File.initialize', target, from]
      from = target if from == nil
      super env, target, from, &action
    end

    def signature
      begin
        f = ::File.new path, "r"
        signatureFromString f.read
      rescue SystemCallError => e
        raise unless e.errno == Errno::EEXIST::Errno or e.errno == Errno::ENOENT::Errno
        nil
      end
    end

    def signatureFromString str
      d = Digest::SHA1.new
      d << str
      d.to_s
    end

    def updateSignature
      @environment.signatureCache.setSignature id, signature
    end

    def signatureChanged? 
      s = signature
      s == nil or s != @environment.signatureCache.signature(id)
    end

    def updateNow
      super
      action { updateSignature }
    end

  end

  class InputFile < File # ===================================================
    def initialize env, target, from = nil, &action
      super env, target, from, &action
      @file = ::File.new path, 'r'
      s = signature
      if signatureChanged?
        debug ['file changed', path]
        @changed = true
        @needMake = true # store the new signature!
      else
        @needMake = false
      end
    end
    def path
      Pathname.new @environment['filePrefix']+'/'+id
    end
  end

  class GeneratedFile < File # ===============================================
    def initialize env, target, from = nil, &action
      @generatorSig = ''
      super env, target, from, &action
      @needMake = true unless ::File.exists? path
      # do we remake file that changed all by itself?
    end

    def path
      Pathname.new @environment['generatedPrefix']+'/'+id
    end

    def signature # include @generatorSig in the signature
      s = super
      s == nil ? nil : signatureFromString(s + @generatorSig)
    end

    def generate &a
      action &a
      updateSignature
    end

    def generator &a
      a.call
      if signatureChanged?
        debug ['signature changed on', path]
        @needMake = true if signatureChanged?
      end
    end

    def sourcePath
      t = @environment.taskForTarget from
      t.path
    end

  end

  class Environment # ========================================================
    def signatureFile f
      SignatureCache.new self, f
    end

  end

  class FileTool < Tool # ====================================================
    def name; :fileTool; end

    def initialize env
      super env
      env.setDefault 'filePrefix', '.'
      env.setDefault 'generatedPrefix', '.'
      Rule.from env, 10000, InputFile.promise do
        |env, from|
        fn = env.qualifiedTarget from
        debug ['file tool rule:', env.path]
        if fn != nil and ::File.readable? env['filePrefix']+'/'+fn
          debug ["ok, file exists", from.name]
          Target.new from.name, Target::TypeFile.new
        else
          debug ["couldn't find file!", fn]
          nil
        end
      end
    end

  end

  class SignatureCache < Tool # ==============================================
    def name; :signatureCache; end

    def signature target
      debug ['cached signature', target, @sigs[target]]
      @sigs[target]
    end

    def setSignature target, sig
      @sigs[target] = sig
    end

    def initialize env, file
      super env
      env.setDefault 'cachePrefix', '.rakons'
      begin
        Dir.mkdir env['cachePrefix']
      rescue SystemCallError => e
        raise unless e.errno == Errno::EEXIST::Errno
      end
      @file = ::File.open env['cachePrefix']+'/'+file, "a+"
      @sigs = {}
      @file.each { |l|
        (t, s) = l[0..-2].split "//"
        debug ['loading signature', t, s]
        @sigs[t] = s
      }
    end

    def finalize
      debug ['signature cache finalize']
      @file.truncate 0
      @sigs.each_pair { |t, s|
        @file << t << "//" << s << "\n" }
      @file.close
      super
    end

  end

end
