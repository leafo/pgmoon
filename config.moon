
config = require "lapis.config"

config "development", ->
  postgres {
    backend: "pgmoon"
    database: "pgmoon"
  }
