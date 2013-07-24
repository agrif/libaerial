import sys
from gi.repository import GLib, Aerial

# try to get the host to connect to from our first argument
try:
    host = sys.argv[1]
except IndexError:
    print("usage: {} host[:port]".format(sys.argv[0]))
    sys.exit(1)

# input file, amount to read at once, and a place to store it
infile = sys.stdin.buffer
bufsize = 4096
buf = b''

# called often, to shuffle data from infile to the airtunes client
def transfer_data():
    global loop, client, buf, bufsize, infile
    
    # first, if we have something to write...
    if len(buf) >= Aerial.Client.BYTES_PER_FRAME:
        # if our client has shifted out of the PLAYING state,
        # we want to stop
        if client.props.state != Aerial.ClientState.PLAYING:
            loop.quit()
            return False
        
        # write() only accepts whole frames, so we find out the biggest
        # length we can write without writing partial frames
        nicepartlen = len(buf) / Aerial.Client.BYTES_PER_FRAME
        nicepartlen = int(nicepartlen) * Aerial.Client.BYTES_PER_FRAME
        
        # write our frames, and get back how many bytes were written
        # and a timestamp (which we don't use here)
        written, tstamp = client.write(buf[:nicepartlen])
        
        # discard the written frames
        buf = buf[written:]
        return True
    
    # since we have nothing to write, read something in to be written
    # next time!
    buf = infile.read(bufsize)
    if not buf:
        # stdin has reached the end!
        loop.quit()
        return False
    
    return True

# called when the client encounters an error
def on_error(e):
    global loop
    print("client error: {}".format(e))
    loop.quit()

# we need an event loop...
loop = GLib.MainLoop()

# create our client, add our error callback, connect, and tell it to play
client = Aerial.Client.new()
client.connect("on_error", on_error)
client.connect_to_host(host)
client.play()

# add our data shuffler
GLib.idle_add(transfer_data)

# run until complete
loop.run()

# disconnect gracefully
client.disconnect_from_host()
