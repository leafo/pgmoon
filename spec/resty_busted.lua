-- This script is used to start busted from the resty command line tool


-- prevent the moonscript loader from being inserted
package.loaded.moonscript = require("moonscript.base")

-- manually compiled the needed files in spec
local dofile = require("moonscript.base").dofile
package.loaded["spec.util"] = dofile "spec/util.moon"

require 'busted.runner'({ standalone = false, output = 'TAP' })

