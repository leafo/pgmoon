for st in *{"luasocket", "cqueues"}
  pgmoon = require("pgmoon.init").new {
    socket_type: st
    database: "postgres"
  }


  K = 10000

  pgmoon\connect!

  socket = require "socket"

  simple_count = 0
  simple_time = 0

  extended_params_count = 0
  extended_params_time = 0

  extended_simple_count = 0
  extended_simple_time = 0

  for m=1,3
    do -- simple query with string interpolation
      start = socket.gettime!
      for i=1,K
        assert pgmoon\simple_query "select #{pgmoon\escape_literal 5} + #{pgmoon\escape_literal 7} as sum, #{pgmoon\escape_literal "hello"} as name"
        simple_count += 1

      simple_time += socket.gettime! - start

    do -- extended query but using static query created by string interpolation
      start = socket.gettime!
      for i=1,K
        assert pgmoon\extended_query "select #{pgmoon\escape_literal 5} + #{pgmoon\escape_literal 7} as sum, #{pgmoon\escape_literal "hello"} as name"
        extended_simple_count += 1

      extended_simple_time += socket.gettime! - start

    do -- extended query with parameters
      start = socket.gettime!
      for i=1,K
        pgmoon\extended_query "select $1 + $2 as sum, $3 as name", 5, 7, "hello"
        extended_params_count += 1

      extended_params_time += socket.gettime! - start


  indent = (s) -> "% 30s"\format s

  print "Socket type: #{pgmoon.sock_type}"
  print "Query: select $1 + $2 as sum, $3 as name"
  print indent"simple", "%0.4fs"\format(simple_time), "%0.2f queries/s"\format simple_count / simple_time
  print indent"extended_params", "%0.4fs"\format(extended_params_time), "%0.2f queries/s"\format extended_params_count / extended_params_time
  print indent"extended_simple", "%0.4fs"\format(extended_simple_time), "%0.2f queries/s"\format extended_simple_count / extended_simple_time
  print!
