lapis = require "lapis"

import Postgres from require "postgres"

lapis.serve class extends lapis.Application
  "/": =>
    p = Postgres "127.0.0.1", "5432", "postgres", "moonrocks"

    @html ->
      text ":"
      pre require("moon").dump {
        p\connect!
      }


