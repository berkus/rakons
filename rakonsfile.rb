require "rakons/generic"
require "rakons/cc"

Rakons::CC.new Toplevel
Toplevel.signatureFile "signature-cache"

Toplevel.load "test"
Toplevel.request "test/cc"

