require "rakons/cc"

module Rakons
  class Target
    class TypeMocSource < TypeCSource; end
    class TypeUiSource < TypeFile; end
  end

  class KDE < CC
    def initialize env = nil
      super env
      debug ['KDE: initialize']
      env.setDefault('UIC', 'uic')
      env.setDefault('MOC', 'moc')
      @srcpat = /^(.*).ui/
      Rule.new env, 1000, promise(UiCompiled) do
        |env, from|
        if from.name =~ @srcpat
          n = from.name.gsub @srcpat, '\1.cpp'
          Target.new n, Target::TypeCSource.new
        else
          nil
        end
      end
      Rule.new env, 1000, TransformTask::promise(UiCompiled, &nil) do
      end
    end
end
