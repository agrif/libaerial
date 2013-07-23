namespace Aerial
{

public struct RTPPacket
{
	uint8 version; // 2 bits
	bool padding;
	bool extension;
	uint8 source_id_count; // 4 bits
	bool marker;
	uint8 payload_type; // 7 bits
	uint16 sequence;
	uint32? timestamp;
	uint32? source_id;
}

public class RTP : Object
{	
	private const string LOGDOMAIN = "AerialRTP";
	
	public string local_host { get; construct; }
	public uint local_port { get; construct; }
	private string remote_host;
	private uint remote_port;
	
	public bool uses_source_id { get; set; default = false; }
	public bool uses_timestamp { get; set; default = true; }
	
	public signal void on_packet(RTPPacket packet, DataInputStream payload);
	// only used when an error occurs while trying to receive a packet
	public signal void on_error(Error e);
	
	private Socket socket;
	private Error? construct_error = null;
	
	construct
	{
		try
		{
			var local_addr = new InetAddress.from_string(local_host);			
			socket = new Socket(local_addr.family, SocketType.DATAGRAM, SocketProtocol.UDP);
			var local_sa = new InetSocketAddress(local_addr, (uint16)local_port);
			
			socket.bind(local_sa, true);
			
			log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, "bound to UDP port %u", local_port);
			
			var source = socket.create_source(IOCondition.IN);
			source.set_callback((s, cond) =>
				{
					try
					{
						uint8[] buffer;
						buffer.resize(4096);
						var read = s.receive(buffer);
						buffer.length = (int)read;
						log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, "received %i bytes on port %u", (int)read, local_port);
						
						dump_buffer(buffer);
						
						handle_packet(buffer);
					} catch (Error e) {
						on_error(e);
						return false;
					}
					return true;
				});
			source.attach(MainContext.default());
		} catch (Error e) {
			construct_error = e;
		}
	}
	
	public RTP(string local_host, uint16 local_port) throws Error
	{
		Object(local_host: local_host, local_port: local_port);
		if (construct_error != null)
			throw construct_error;
	}
	
	public void connect_to(string _remote_host, uint16 _remote_port) throws Error
	{
		remote_host = _remote_host;
		remote_port = _remote_port;
		var remote_addr = new InetAddress.from_string(remote_host);
		var remote_sa = new InetSocketAddress(remote_addr, (uint16)remote_port);
		socket.connect(remote_sa);
	}
	
	private void dump_buffer(uint8[] buffer)
	{
		var build = "";
		foreach (var byte in buffer)
		{
			build += "%02x ".printf(byte);
			if (build.length >= 16 * 3)
			{
				log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, build);
				debug(build);
				build = "";
			}
		}
		if (build.length > 0)
			log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, build);
			debug(build);
	}
	
	public uint8[] send(RTPPacket packet, uint8[] payload) throws Error
	{
		var ostream = new MemoryOutputStream(null, realloc, free);
		var dat = new DataOutputStream(ostream);

		uint8 byte1 = 0;
		byte1 |= (packet.version << 6);
		byte1 |= (int)packet.padding << 5;
		byte1 |= (int)packet.extension << 4;
		byte1 |= packet.source_id_count & 0x0f;
		uint8 byte2 = 0;
		byte2 |= (int)packet.marker << 7;
		byte2 |= packet.payload_type & 0x7f;
		
		dat.put_byte(byte1);
		dat.put_byte(byte2);
		dat.put_uint16(packet.sequence);
		if (packet.timestamp != null)
			dat.put_uint32(packet.timestamp);
		if (packet.source_id != null)
			dat.put_uint32(packet.source_id);
		foreach (var byte in payload)
			dat.put_byte(byte);
		dat.close();
		
		uint8[] buffer = ostream.steal_data();
		buffer.length = (int)ostream.get_data_size();
		log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, "writing %i bytes from port %u -> %s:%u", buffer.length, local_port, remote_host, remote_port);
		dump_buffer(buffer);
		socket.send(buffer);
		return buffer;
	}
	
	private void handle_packet(uint8[] buffer) throws Error
	{
		if (buffer.length < 8)
			return;
		
		var istream = new MemoryInputStream.from_data(buffer, null);
		var dstream = new DataInputStream(istream);
		
		var byte1 = dstream.read_byte();
		var byte2 = dstream.read_byte();
		
		var sequence = dstream.read_uint16();
		
		uint32? timestamp = null;
		if (uses_timestamp)
			timestamp = dstream.read_uint32();
		
		uint32? source_id = null;
		if (uses_source_id)
			source_id = dstream.read_uint32();
		
		var packet = RTPPacket() {
				version = (byte1 & 0xc0) >> 6,
				padding = (byte1 & 0x20) > 0,
				extension = (byte1 & 0x10) > 0,
				source_id_count = (byte1 & 0x0f),
				marker = (byte2 & 0x80) > 0,
				payload_type = (byte2 & 0x7f),
				sequence = sequence,
				timestamp = timestamp,
				source_id = source_id
		};
		
		on_packet(packet, dstream);
	}
}

}