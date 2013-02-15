require "rakons/generic"
Toplevel.task "test2" do
  puts "dum dum di dum di da!"
end

env = Toplevel.createChild

env.task "test3" do |t|
  t.request "test4"
  t.request "test-cc"
  t.action {
    puts "foobar"
  }
end

env2 = Rakons::Environment.new
env2["CFLAGS"] = '-I/something'
env2.task "test4" do |t|
  puts "wibble"
  t.done = false
end

env2.task "test5" do |t|
  t.request "test4"
  t.action {
    puts "baz"
  }
end

env['generatedPrefix'] = '/tmp'
env.cc.program "cc" do |p|
  p.source "test.c"
  p.source "test2.c"
  p.library "m" # -lm
  p.cflags "-W", "-pedantic"
  p.cxxflags "-Wall"
end

#env2.request("#test2")
#env2.request("test4")
#env2.request("#test/test3")
#env2.request("#test/test5")
