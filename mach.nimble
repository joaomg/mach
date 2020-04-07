# Package

version       = "0.1.0"
author        = "João Marques Gomes"
description   = "A MACHine originated data processing server"
license       = "Proprietary"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["mach"]

# Dependencies

requires "nim >= 1.0.6"
requires "jester >= 0.4.3"
requires "hmac >= 0.1.9"

# Tasks

task dev, "Run mach in dev mode":
    exec "nimble run mach ./config/dev_localhost.cfg"

