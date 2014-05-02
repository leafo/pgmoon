
socket = require "socket"
server = socket.bind "*", 35004
print server\getsockname!

while true
  client = server\accept!
  print "Got client:", client\getsockname!

  while true
    c, err = client\receive(1)
    break unless c
    b = c\byte!

    if b >= 32 and b <= 126
      print " #{b}\t`#{c}`"
    else
      print " #{b}"

  print "\nDisconnected"



