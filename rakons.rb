#!/usr/bin/ruby1.8
require "rakons/core"

Root = Rakons::Environment.new nil
Current = Rakons::Current
Root.load '.'
Root.finalize
