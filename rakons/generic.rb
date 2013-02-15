module Rakons
  class Generic < Environment
    def initialize(parent, path = nil)
      super(parent, path)
      @test = "haha"
    end
    def blah
      p "hello world from generic"
      @test = "hihi"
    end
    def lala
      p @test
    end
  end
end

Toplevel = Rakons::Generic.new(Root)
