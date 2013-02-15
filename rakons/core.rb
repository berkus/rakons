#!/usr/bin/ruby1.8
require "test/unit/assertions"
require "singleton"
require "pathname"
require "set"

# core classes:
#  Target
#  Task (+TransformTask and InferredTask)
#  Environment
#  Rule
#  Tool
#  Current
# TODO
#  invariants (!!)
#  functional tests
#  fix task (re)make decision, fix terminology [done?]
#  from, to in rules (bork bork!)

module Promise
  def promise *bind # lazy evaluation anyone
    x = self
    y = Proc.new do |*args|
      b = Array.new bind
      b.concat args
      new *b
    end
    y
  end
end

module Rakons

  $dbgLevel = 0
  module Debug
    def debugEnter *args
      debug ['entering'] + args
      $dbgLevel += 1
    end
    
    def debugLeave *args
      $dbgLevel -= 1
      debug ['leaving'] + args
    end

    def debug *args
      printf ' ' * $dbgLevel
      p args.flatten
    end
  end
  
  module TaskHash # ==========================================================
    include Test::Unit::Assertions
    include Debug
    def add! task
      debug ['adding', task.id]
      self[task.id] = task
    end
    def invariants
      each_pair { |k, v| assert_equal k, v.id }
    end
  end

  class Target # =============================================================

    class Type
      def inspect; "#type("+self.class.name+")"; end
      def == other; other.class == self.class; end
    end
    class TypePhony < Type; end
    class TypeFake < Type; end
 
    include Test::Unit::Assertions
    attr_reader :name, :type

    def initialize name, type
      assert type.kind_of?(Type)
      assert(name == nil || name.class == String)
      @name = name
      @type = type
    end

    def to_s; name; end
    def inspect; "#target("+name.to_s+', '+type.class.name+")"; end

    class << self
      include Test::Unit::Assertions
      def normalize t
        t = Target::Type.new if t == nil
        t = Target.new t, Target::Type.new if t.class == String
        t = Target.new nil, t if t.kind_of? Target::Type
        assert_equal Target, t.class
        t
      end
    end

  end
  
  class Environment # ========================================================
    include Test::Unit::Assertions
    include Debug

    attr_reader :path
    attr_accessor :tools

    def initialize parent = false, path = nil
      parent = Current::parent if parent == false
      @parent = parent
      path = Current::path if not path
      @path = path
      debugEnter 'Environment.initialize (parent == nil, path)', parent == nil, path
      @vars = {}
      @tools = {}
      if @parent == nil
        @tasks = Hash.new
        @tasks.extend TaskHash
        @defaultVars = {}
      else
        parent.tools.each_value { |t| t.extendEnvironment self }
      end
      @children = Array.new
      @rules = Set.new
      parent.addChild self if parent
      debugLeave
    end

    # -- environment handling stuff ----
    def addChild c
      invariants
      @children.push c
    end

    def rules # rules are inherited at reference time
      r = @rules
      r.merge @parent.rules unless root?
      r
    end

    def root # find root (obviously)
      if @parent == nil
        self
      else
        @parent.root
      end
    end

    def root? # is this a root environment?
      @parent == nil
    end

    def each_descendant &action
      action.call self
      @children.each { |c| c.each_descendant &action }
    end

    def finalize # clean up (like, write out caches)
      if root?
        tools = Set.new
        each_descendant do |e| # collect all tools
          e.tools.each_value { |t| tools.add? t }
        end
        tools.each { |t| t.finalize }
      end
    end

    def each &action
      root.each_descendant &action
    end

    def createChild
      self.class.new self
    end

    # -- task handling stuff ----
    def tasks; root.mytasks; end
    def mytasks; @tasks; end

    def task target, type = Target::TypePhony.new, &action
      invariants
      Task.new self, (Target.new target, type), &action
    end

    # ensure task is the active one for given target
    def activateTask task
      invariants
      root.tasks.add! task
    end

    def qualifiedTarget target # = task.id = path from root rakonsfile.rb dir
      return nil if target == nil or target.name == nil
      target = target.name if target.class == Target
      tp = Pathname.new './'+path.to_s+'/'+target
      tp.relative_path_from(Pathname.new('.')).to_s
    end

    def taskForTarget target
      return nil if target.name == nil
      if target.name[0] == ?# # absolute target path
        root.taskForTarget Target.new(target.name[1..-1], target.type)
      else
        t = qualifiedTarget target
        debug ["taskForTarget looking for", t]
        tasks[t]
      end
    end

    def request target = nil, from = nil # ensure target is up to date
      debugEnter 'request'
      changed = nil
      task = inferTask target, from
      changed = task.request unless task == nil
      debugLeave 'request returning', changed, task.target
      [changed, task == nil ? nil : task.real]
    end

    def inferTask target, from
      (t, f) = [target, from].map { |x| Target::normalize x }
      task = nil
      task = taskForTarget t unless t.name == nil
      task = InferredTask.new self, from, target if task == nil
      debug ['inferTask', target, from, task == nil]
      task
    end

    # -- invariants aka check sanity ----
    def invariants
      assert_equal self, root if @parent == nil
      tasks.invariants
      @children.each { |c|
        c.invariants }
    end

    # -- rakonsfile.rb handling :-) ----
    def load p
      invariants
      Current::path = p
      Current::parent = self
      require p+"/"+"rakonsfile.rb"
      invariants
    end

    # -- envvar handling :) ----
    def [] name # vars are inherited at reference time
      v = @vars[name]
      if v == nil
        v = @parent[name] unless root?
        v = @defaultVars[name] if root?
      end
      v
    end

    def []= name, value # only affects ourselves and descendants
      @vars[name] = value
    end

    # for tool use only! set default value for a var
    def setDefault name, value
      return root.setDefault name, value unless root?
      @defaultVars[name] = value
    end

  end
  
  class Tool # ===============================================================
    include Debug
    def extendEnvironment env # magic :-)
      x = self
      m = Module.new do
        define_method(x.name) {
          t = tools[x.name.to_s]
          t.calledFrom self
          t
        }
      end
      env.extend m
      # which one of those two?
      env.tools[name.to_s] = self
      #env.tools[name] = self
    end

    def calledFrom env # @environment = current calling context
      debug ['tool called from', env.path]
      @environment = env
    end

    def initialize env = nil
      env = Current::parent if env == nil
      @environment = env
      extendEnvironment env
    end

    ## def name; :undefined; end # default - better leave undefined?
    def finalize
      debug ['finalize', self.class.name]
    end

  end

  class Rule # ===============================================================
    attr_reader :price
    include Test::Unit::Assertions
    include Debug

    def initialize env, price, promise, &rewrite
      @rewrite = rewrite
      @promise = promise
      @price = price
      env.rules.add self
      debug ['rule rewrite (rewr, id)', rewrite, object_id]
      # better forget env, we want a current context, like with Tool
    end

    def promise env, from, to
      assert_equal Target, from.class
      to = @rewrite.call env, from, to
      if to == nil # failed
        [nil, nil]
      else # matched
        [to, Proc.new { @promise.call env, from, to }]
      end
    end

    def task env, from, to
      (target, promise) = promise env, from, to
      if target == nil
        nil
      else
        mt = env.taskForTarget target
        debug ['about to call (promise, id)', promise, object_id]
        mt = promise.call if mt == nil
        mt
      end
    end

    class << self
      def from env, pri, promis, &rewrite
        new env, pri, promis do
          |env, from, to|
          t = (from == nil ? nil : rewrite.call(env, from))
          if to.name == nil || to.name == t.name
            t
          else
            nil
          end
        end
      end

      def to env, pri, promis, &rewrite
        new env, pri, promis do
          |env, from, to|
          to == nil ? nil : rewrite.call(env, to)
        end
      end
    end

  end

  class Task # ===============================================================
    include Enumerable
    include Debug
    include Test::Unit::Assertions

    def invariants
      assert @environment.kind_of?(Environment)
    end

    attr_reader :prerequisites, :target
    attr_accessor :done
    def real; debug ['Task.real']; self; end
    def needUpdate?; @needUpdate; end
    def forceUpdate; @needUpdate = true; end
    def forceMake;
      debug ['forcing make of', id]
      @needMake = true;
    end
    def <=> (task); id <=> task.id; end # enumerable
    def id; @environment.qualifiedTarget target; end

    def initialize env, target, &updateaction
     debugEnter ["creating task", target, self.class.name]
      debug ['caller', Kernel.caller]
      target = Target::normalize target
      @environment = env
      @target = target
      assert @target.class == Target
      @updateAction = updateaction
      @needUpdate = true
      @needMake = false
      @changed = false
      activate
      invariants
      debugLeave
    end

    def activate
      debug ["activating", target, self.class.name]
      @environment.activateTask self
      invariants
    end

    def request target = nil, from = nil
      if target == nil and from == nil # request self
        updateNow if needUpdate?
        @needMake = false
        ret = @changed
      else # conve
        # erm, also forces update if the request resulted in some action :-)
        (changed, t) = @environment.request target, from
        forceMake if changed
        ret = [changed, t]
      end
      invariants
      ret
    end

    def updateNow # call the updateAction, that is, request depends and so
      debugEnter ['updating', target]
      @updateAction.call self unless @updateAction == nil
      invariants
      debugLeave
    end

    # action... call to conditionally run code when update is needed
    # should be called from updateNow after all requests have been done
    # err, updateNow or updateAction, which is the block you pass to
    # Task constructor :)
    def action &a
      if @needMake
        @changed = true
        debug ['making', target]
        a.call self
        invariants
      else
        debug ['not making', target]
      end
    end

    class << self
      include Promise
    end
  end

  class TransformTask < Task # ===============================================
    def initialize env, from, to, &action
      super env, to, &action
      @from = from
    end
  end

  $inferLevel = 0
  class InferredTask < Task # ================================================
    def request; real.request; end
    def updateNow; infer; end

    def real
      # RUBY BUG! segfault: p ['bla', real == nil]
      #return @environment.taskForTarget @to
      debug ['InferredTask.real (@real == nil)', @real == nil]
      infer if @real == nil
      debug ['InferredTask.real getting @real.real']
      @real = @real.real #if @real.class == InferredTask
      debug ['InferredTask.real got @real.real']
      @real
    end

    def initialize env, from = nil, to = nil, &action
      fake = Target.new "fake", Target::TypeFake.new
      super env, fake, &action
      (@from, @to) = [from, to].map { |x| Target::normalize x }
      @real = nil
      @inferred = false
    end

    def activate; end # noop - never activate

    def infer rules = @environment.rules
      debugEnter [$inferLevel, 'entering InferredTask.infer']
      $inferLevel += 1
      fail "oops!" if @inferred
      @inferred = true
      (minp, mint) = [nil, nil]
      rules.each { |r|
        debug ['rules.each for', r.to_s, to_s]
        # get ourselves a task for this rule/@from combination
        task = r.task @environment, @from, @to
        target = task == nil ? nil : task.target
        debug ['task (@to, task)', @to, task.to_s]
        if target == nil
          debug ['oops, target == nil']
        else
          assert_equal Target, @to.class
          assert_equal Target, target.class
          if @to.type == target.type # got a match, stop here
            debug ['@to.type == target.type, task, self',
              @to.type, target.type, task.to_s, to_s]
            if minp == nil || minp > r.price
              (minp, mint) = [r.price, task]
            end
          else # no match, continue inference from target
            debug ['@to.type != target.type', @to.type, target.type]
            task = @environment.inferTask @to, target
            debug ['task.class', task.class]
            if task.class == InferredTask # task = inference result
              (price, task) = task.infer(rules - [r])
              if price != nil && (minp == nil || minp > price + r.price)
                debug ['inferred price (so far minimal)', price]
                (minp, mint) = [price+r.price, task]
                #?? @to = tr.target
              end
            else
              (minp, mint) = [r.price, task]
            end
          end
        end
      }
      debug ['inference OK (price, task)', minp, mint.to_s] unless mint == nil
      mint.activate unless mint == nil
      @real = mint
      $inferLevel -= 1; debugLeave [$inferLevel, 'leaving `InferredTask.infer']
      fail "Coludn't infer tasks!" if minp == nil
      [minp, mint]
    end
  end

  # current evaluation context for rakonsfiles - singleton
  class Current # ============================================================
    include Singleton
    attr_accessor :path, :parent

    def initialize
      @path = ::Pathname.new '.'
      @parent = nil
    end

    class << self
      def path= path
        instance.path = ::Pathname.new path
      end
      def path
        instance.path
      end
      def parent
        instance.parent
      end
      def parent= parent
        instance.parent = parent
      end
    end

  end
  
end
