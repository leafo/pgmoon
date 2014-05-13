lapis = require "lapis"
db = require "lapis.db"

lapis.serve class extends lapis.Application
  "/": =>
    json: { db.query "select * from hello_world" }

