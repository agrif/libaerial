namespace Airtunes
{

private struct RTSPResponse
{
	public int code;
	public string message;
	public HashTable<string, string> headers;
}

errordomain RTSPError
{
	BAD_RESPONSE,
	HANDSHAKE_FAILED,
}

private struct AudioPacket
{
	bool in_use;
	uint16 sequence;
	uint8[] data;
}

public class Client : GLib.Object
{
	private const int FRAMES_PER_PACKET = 352;
	private const int SHORTS_PER_PACKET = 2 * FRAMES_PER_PACKET;
	private const int TIMESTAMPS_PER_SECOND = 44100;
	private const int TIMESYNC_INTERVAL = 1000;
	private const int TIME_PER_PACKET = (FRAMES_PER_PACKET * 1000 / TIMESTAMPS_PER_SECOND) - 1;
	private const int PACKET_BACKLOG = 1000;
	private const int BUFFER_SECONDS = 2;
	private const int MAX_DELTA = 10 * FRAMES_PER_PACKET;
	
	private const int64 NTP_EPOCH = 0x83aa7e80;
	
	private const int BUFFER_SIZE = 2 * SHORTS_PER_PACKET * 50;
	
	private const uint16 DEFAULT_PORT = 5000;
	private const string PROTOCOL = "RTSP/1.0";
	// TODO track version properly
	private const string USER_AGENT = "libairtunes/0.0.0";
	private const string WHITESPACE = " ";
	
	// used in outgoing RTSP urls, and elsewhere (client client_session id)
	private uint32 client_session;
	// given by the server during SETUP, used in Session: header
	private string? session = null;
	// used to position audio packets in time
	private uint32 timestamp;
	// used to sequence audio packets
	private uint16 sequence;
	// used as CSeq: header on outgoing
	private int rtspsequence;
	// used as Client-Instance: header on outgoing
	private string client_instance;
	// address of the airtunes device
	private string remote_address;
	// our address
	private string local_address;
	// whether the remote requires encryption
	private bool require_encryption = false;
	// AES key and IV
	private uint8[] aes_key;
	private uint8[] aes_iv;
	private string rsa_aes_key;
	// reference time for when the channels opened
	private int64 timing_ref_time;
	// number of frames written since last sync
	private uint32 frames_since_sync;
	// when the last sync packet was emitted
	private int64 last_sync_time;
	// what timestamp the last sync packet had
	private uint32 last_sync_timestamp;
	// how many timestamps ahead the audio packets are
	private int32 timestamp_delta;
	// previously-sent audio packets
	private AudioPacket[] audio_packets;
	
	private RingBuffer audio_buffer;
	
	private GLib.SocketClient connector;
	private GLib.SocketConnection socket;
	private GLib.DataOutputStream output;
	private GLib.DataInputStream input;
	
	private RTPClient server_channel;
	private RTPClient control_channel;
	private RTPClient timing_channel;
	
	construct
	{
		client_session = GLib.Random.next_int();
		timestamp = GLib.Random.next_int();
		sequence = (uint16) GLib.Random.next_int();
		rtspsequence = 0;
		client_instance = bytes_to_hex(random_bytes(8));
		
		// TODO generate keys! (needs rsa encryption)
		//aes_key = random_bytes(16);
		//aes_iv = random_bytes(16);
		aes_key = { 0x14, 0x49, 0x7d, 0xcc, 0x98, 0xe1, 0x37, 0xa8, 0x55, 0xc1, 0x45, 0x5a, 0x6b, 0xc0, 0xc9, 0x79 };
		aes_iv = { 0x78, 0xf4, 0x41, 0x2c, 0x8d, 0x17, 0x37, 0x90, 0x2b, 0x15, 0xa6, 0xb3, 0xee, 0x77, 0x0d, 0x67 };
		rsa_aes_key = "VjVbxWcmYgbBbhwBNlCh3K0CMNtWoB844BuiHGUJT51zQS7SDpMnlbBIobsKbfEJ3SCgWHRXjYWf7VQWRYtEcfx7ejA8xDIk5PSBYTvXP5dU2QoGrSBv0leDS6uxlEWuxBq3lIxCxpWO2YswHYKJBt06Uz9P2Fq2hDUwl3qOQ8oXb0OateTKtfXEwHJMprkhsJsGDrIc5W5NJFMAo6zCiM9bGSDeH2nvTlyW6bfI/Q0v0cDGUNeY3ut6fsoafRkfpCwYId+bg3diJh+uzw5htHDyZ2sN+BFYHzEfo8iv4KDxzeya9llqg6fRNQ8d5YjpvTnoeEQ9ye9ivjkBjcAfVw";
		
		audio_packets.resize(PACKET_BACKLOG);
		for (var i = 0; i < audio_packets.length; i++)
			audio_packets[i] = AudioPacket();
		
		audio_buffer = new RingBuffer(BUFFER_SIZE);
		
		connector = new GLib.SocketClient();
	}
	
	public Client()
	{
		//Object();
	}
	
	public bool connect_to_host(string host_and_port) throws Error
	{
		socket = connector.connect_to_host(host_and_port, DEFAULT_PORT);
		main_loop.begin();
		return true;
	}
	
	public async bool connect_to_host_async(string host_and_port) throws Error
	{
		socket = yield connector.connect_to_host_async(host_and_port, DEFAULT_PORT);
		main_loop.begin();
		return true;
	}
	
	private async string? recv_line() throws IOError
	{
		var line = yield input.read_line_async();
		debug("RTSP >>> %s", line);
		return line;
	}
	
	private async RTSPResponse recv_response() throws IOError, RTSPError
	{
		var first = (yield recv_line()).split_set(WHITESPACE, 3);
		if (first.length != 3 || first[0] != PROTOCOL)
			throw new RTSPError.BAD_RESPONSE("bad RTSP response");
		
		string code_end;
		long code = first[1].to_long(out code_end);
		if (code_end.length > 0)
			throw new RTSPError.BAD_RESPONSE("bad RTSP response");
		
		var resp = RTSPResponse()
		{
			code = (int)code,
			message = first[2],
			headers = new HashTable<string, string>(str_hash, str_equal)
		};
		
		while (true)
		{
			var line = yield recv_line();
			if (line == "")
				break;
			
			var split = line.split(": ", 2);
			if (split.length != 2)
				throw new RTSPError.BAD_RESPONSE("bad RTSP header");
			resp.headers.insert(split[0], split[1]);
		}
		
		return resp;
	}
	
	private bool send_line(string line) throws IOError
	{
		string s = line + "\r\n";
		debug ("RTSP <<< %s", line);
		return output.put_string(s);
	}
	
	private bool send_request(string name, string? uri=null) throws IOError
	{
		var final_uri = uri;
		if (uri == null)
			final_uri = "rtsp://%s/%u".printf(remote_address, (uint)client_session);
		
		string s = "%s %s %s".printf(name, final_uri, PROTOCOL);
		rtspsequence++;
		return send_line(s) &&
			send_header("CSeq", rtspsequence) &&
			send_header("Client-Instance", client_instance) &&
			(session == null || send_header("Session", session)) &&
			send_header("User-Agent", USER_AGENT);
	}
	
	private bool send_header(string name, Variant value) throws IOError
	{
		string val_as_str;
		if (value.classify() == Variant.Class.STRING)
		{
			val_as_str = (string)value;
		} else {
			val_as_str = value.print(false);
		}
		
		string s = "%s: %s".printf(name, val_as_str);
		return send_line(s);
	}
	
	private bool send_finalize(string? data=null) throws IOError
	{
		if (data == null)
		{
			return send_line("");			
		}
		
		debug("body: %s", data);
		return send_header("Content-Length", (uint)data.length) && send_line("") && output.put_string(data);
	}
	
	private async void main_loop()
	{
		stdout.printf("got connection %p\n", socket);
		input = new GLib.DataInputStream(socket.input_stream);
		input.set_newline_type(DataStreamNewlineType.CR_LF);
		output = new GLib.DataOutputStream(socket.output_stream);
		
		try
		{
			try
			{
				var isa = socket.get_remote_address() as InetSocketAddress;
				remote_address = isa.address.to_string();
				isa = socket.get_local_address() as InetSocketAddress;
				local_address = isa.address.to_string();
			} catch (Error e2) {
				throw new RTSPError.HANDSHAKE_FAILED("can't get endpoint addresses");
			}
			
			// generate 16 random bytes for apple-challenge
			var apple_challenge = bytes_to_base64(random_bytes(16));
			
			// send RTSP OPTIONS
			send_request("OPTIONS", "*");
			send_header("Apple-Challenge", apple_challenge);
			send_finalize();
			var resp = yield recv_response();
			if (resp.code != 200)
				throw new RTSPError.HANDSHAKE_FAILED(resp.message);
			if (resp.headers.lookup_extended("Apple-Response", null, null))
				require_encryption = true;
			
			if (require_encryption)
				debug("using encryption");
			else
				debug("not using encryption");
			
			// send RTSP ANNOUNCE
			// TODO - use auth, if needed
			send_request("ANNOUNCE");
			send_header("Content-Type", "application/sdp");
			var announce_body =
				"v=0\r\n" +
				"o=iTunes %u O IN IP4 %s\r\n" +
				"s=iTunes\r\n" +
				"c=IN IP4 %s\r\n" +
				"t=0 0\r\n" +
				"m=audio 0 RTP/AVP 96\r\n" +
				"a=rtpmap:96 AppleLossless\r\n" +
				"a=fmtp:96 %i 0 16 40 10 14 2 255 0 0 %i\r\n" +
				"a=rsaaeskey:%s\r\n" +
				"a=aesiv:%s\r\n";
			
			announce_body = announce_body.printf((uint)client_session, remote_address, local_address, FRAMES_PER_PACKET, TIMESTAMPS_PER_SECOND, rsa_aes_key, bytes_to_base64(aes_iv));
			send_finalize(announce_body);
			resp = yield recv_response();
			if (resp.code != 200)
				throw new RTSPError.HANDSHAKE_FAILED(resp.message);
			
			// send RTSP SETUP
			// TODO select ports for control and timing
			var local_server_port = 6000;
			var local_control_port = 6001;
			var local_timing_port = 6002;

			server_channel = new RTPClient(local_address, local_server_port);
			control_channel = new RTPClient(local_address, local_control_port);
			timing_channel = new RTPClient(local_address, local_timing_port);
			
			server_channel.uses_source_id = true;
			control_channel.uses_timestamp = false;

			//control_channel.verbose = true;
			//timing_channel.verbose = true;
			//server_channel.verbose = true;
			
			send_request("SETUP");
			var transport = "RTP/AVP/UDP;unicast;interleaved=0-1;mode=record;control_port=%i;timing_port=%i";
			transport = transport.printf(local_control_port, local_timing_port);
			send_header("Transport", transport);
			send_finalize();
			resp = yield recv_response();
			if (resp.code != 200)
				throw new RTSPError.HANDSHAKE_FAILED(resp.message);
			if (!resp.headers.lookup_extended("Session", null, null))
				throw new RTSPError.HANDSHAKE_FAILED("did not get session from server");
			if (!resp.headers.lookup_extended("Transport", null, null))
				throw new RTSPError.HANDSHAKE_FAILED("did not get transport from server");
			
			session = resp.headers.lookup("Session");
			transport = resp.headers.lookup("Transport");
			// remote ports!
			uint16? server_port = null;
			uint16? control_port = null;
			uint16? timing_port = null;
			foreach (var part in transport.split(";"))
			{
				var parts = part.split("=", 2);
				if (parts.length != 2)
					continue;
				if (parts[0] == "server_port")
					server_port = (uint16)parts[1].to_int();
				if (parts[0] == "timing_port")
					timing_port = (uint16)parts[1].to_int();
				if (parts[0] == "control_port")
					control_port = (uint16)parts[1].to_int();
			}
			
			if (server_port == null || timing_port == null || control_port == null)
				throw new RTSPError.HANDSHAKE_FAILED("did not get ports from server");
			
			server_channel.connect_to(remote_address, server_port);
			timing_channel.connect_to(remote_address, timing_port);
			control_channel.connect_to(remote_address, control_port);
			
			timing_ref_time = get_monotonic_time();			
			timing_channel.on_packet.connect(on_timing_packet);
			control_channel.on_packet.connect(on_resend_packet);
						
			// send RTSP RECORD (using seq/timestamp)
			send_request("RECORD");
			send_header("Range", "ntp=0-");
			send_header("RTP-Info", "seq=%u;rtptime=%u".printf(sequence, timestamp));
			send_finalize();
			
			resp = yield recv_response();
			if (resp.code != 200)
				throw new RTSPError.HANDSHAKE_FAILED(resp.message);
			
			// send RTSP SET_PARAMETER to set initial volume
			// TODO

			// prepare RTP connection for audio
			send_sync_packet(true);
			send_audio_packet(true);
			debug("sending audio every %ims", TIME_PER_PACKET);
			debug("sending sync every %ims", TIMESYNC_INTERVAL);
			var audio_time = new TimeoutSource(TIME_PER_PACKET);
			var sync_time = new TimeoutSource(TIMESYNC_INTERVAL);
			audio_time.set_callback(() => { send_audio_packet(false); return true; });
			sync_time.set_callback(() => { send_sync_packet(false); return true; });
			audio_time.attach(MainContext.default());
			sync_time.attach(MainContext.default());
		} catch (Error e) {
			// TODO proper error reporting
			stderr.printf("error: %s\n", e.message);
		}
	}
	
	private void send_audio_packet(bool is_first)
	{
		// if we're ahead by 10+ packets, ignore this
		if (!is_first && (int)timestamp_delta > MAX_DELTA)
		{
			timestamp_delta -= FRAMES_PER_PACKET;
			return;
		}
		
		// if we don't have data, also ignore this
		if (audio_buffer.get_read_space() < 2 * SHORTS_PER_PACKET)
		{
			stdout.printf("buffer underrun\n");
			return;
		}
		
		var outp = RTPPacket() {
			version = 2,
			padding = false,
			extension = false,
			source_id_count = 0,
			marker = is_first,
			payload_type = 96,
			sequence = sequence,
			timestamp = timestamp,
			source_id = client_session
		};
		
		// +16 for the ALAC header
		var data_size = 2 * SHORTS_PER_PACKET;
		var num_frames = FRAMES_PER_PACKET;
		var bw = new BitWriter(data_size + 16);
		
		// ALAC header
		bw.write(1, 3); // channel=1, stereo
		bw.write(0, 4); // unknown
		bw.write(0, 8); // unknown
		bw.write(0, 4); // unknown
		bw.write(1, 1); // hassize
		bw.write(0, 2); // unused
		bw.write(1, 1); // is-not-compressed
		
		// size of data
		bw.write((num_frames >> 24) & 0xff, 8);
		bw.write((num_frames >> 16) & 0xff, 8);
		bw.write((num_frames >> 8 ) & 0xff, 8);
		bw.write((num_frames      ) & 0xff, 8);
		
		// write the data!
		for (var i = 0; i < data_size; i += 4)
		{
			uint8 frame[4];
			var framelen = audio_buffer.read(frame);
			
			bw.write(frame[0], 8);
			bw.write(frame[1], 8);
			bw.write(frame[2], 8);
			bw.write(frame[3], 8);
			timestamp++;
			frames_since_sync++;
		}
		
		uint8[] payload = bw.finalize();
		if (require_encryption)
			payload = aes_encrypt(aes_key, aes_iv, payload);
		
		try
		{
			var data = server_channel.send(outp, payload);
			
			var i = sequence % audio_packets.length;
			audio_packets[i].in_use = true;
			audio_packets[i].sequence = sequence;
			audio_packets[i].data = data;
			sequence++;
		} catch (Error e) {
			// TODO error handling
			stderr.printf(e.message);
		}
	}
	
	private void send_sync_packet(bool is_first)
	{
		if (is_first)
		{
			last_sync_time = get_monotonic_time();
			last_sync_timestamp = timestamp;
			timestamp_delta = 0;
		}
		
		var projected_timestamp = last_sync_timestamp;
		var now = get_monotonic_time();
		if (now > last_sync_time)
		{
			var delta = now - last_sync_time;
			projected_timestamp = (uint32)(last_sync_timestamp + (TIMESTAMPS_PER_SECOND * delta / 1000000));
			timestamp_delta = (int32)timestamp - (int32)projected_timestamp;
		}
			
		try
		{
			var ostream = new MemoryOutputStream(null, realloc, free);
			var odat = new DataOutputStream(ostream);
			odat.put_uint64(get_ntp_time());
			odat.put_uint32(timestamp);
			odat.close();
			
			uint8[] payload = ostream.steal_data();
			payload.length = (int)ostream.get_data_size();
			
			var outp = RTPPacket() {
				version = 2,
				padding = false,
				extension = is_first,
				source_id_count = 0,
				marker = true,
				payload_type = 84,
				sequence = 7, // yes, on purpose. ewwwwww
				timestamp = projected_timestamp - BUFFER_SECONDS * TIMESTAMPS_PER_SECOND,
				source_id = null
			};
			
			// okay so here's the (assumed) deal with this packet
			// the RTP header timestamp is the one that should be playing
			// RIGHT NOW, as defined by the now() time in the ntptime.
			// the payload timestamp after that is the next one we'll send
			
			// the RIGHT NOW timestamp should be very carefully calculated
			// so that as close to TIMESTAMPS_PER_SECOND pass every second
			// and (importantly!) should be independent of the audio packet rate
			// or you'll get skipping!
			
			debug("sync current: %u projected: %u delta: %i", timestamp, projected_timestamp, timestamp_delta);
			stdout.printf("sync current: %u projected: %u delta: %i\n", timestamp, projected_timestamp, timestamp_delta);
			control_channel.send(outp, payload);
			last_sync_time = now;
			last_sync_timestamp = projected_timestamp;
			frames_since_sync = 0;
		} catch (Error e) {
			// TODO error
			stderr.printf(e.message);
		}
	}
	
	private uint64 get_ntp_time()
	{
		var mono = (uint64)(get_monotonic_time() - timing_ref_time);
		
		var seconds = (uint64)(mono / 1000000) + NTP_EPOCH;
		var microsecs = (uint64)(mono % 1000000);
		microsecs *= (uint64)1 << 32;
		microsecs /= 1000000;
		return (seconds << 32) | (microsecs & 0xffffffff);
	}
	
	private void on_resend_packet(RTPClient c, RTPPacket p, DataInputStream dat)
	{
		if (p.payload_type != 85)
			return;
		
		var outp = RTPPacket()
		{
			version = p.version,
			padding = p.padding,
			extension = p.extension,
			source_id_count = p.source_id_count,
			marker = p.marker,
			payload_type = 86,
			sequence = p.sequence,
			timestamp = p.timestamp,
			source_id = p.source_id
		};
		
		try
		{
			var first_seq = dat.read_uint16();
			var count = dat.read_uint16();
			print("!!!!! error count %u\n", count);
			for (var s = first_seq; s < first_seq + count; s++)
			{
				var i = s % audio_packets.length;
				if (audio_packets[i].in_use && audio_packets[i].sequence == s)
				{
					debug("resending packet %u", s);
					stdout.printf("resending packet %u\n", s);
					c.send(outp, audio_packets[i].data);
				} else {
					debug("packet %u requested but not found", s);
					stdout.printf("packet %u requested but not found\n", s);
				}
			}
		} catch (Error e) {
			// TODO error
			stderr.printf(e.message);
		}
	}
	
	private void on_timing_packet(RTPClient c, RTPPacket p, DataInputStream dat)
	{
		if (p.payload_type != 82)
			return;
		
		try
		{
			dat.read_uint64(); // origin
			dat.read_uint64(); // receive
			var in_transmit = dat.read_uint64();
			var out_origin = in_transmit;
			var out_receive = get_ntp_time();
			var out_transmit = get_ntp_time();
			
			var ostream = new MemoryOutputStream(null, realloc, free);
			var odat = new DataOutputStream(ostream);
			odat.put_uint64(out_origin);
			odat.put_uint64(out_receive);
			odat.put_uint64(out_transmit);
			odat.close();
			var outp = RTPPacket() {
				version = p.version,
				padding = false,
				extension = false,
				source_id_count = 0,
				marker = true,
				payload_type = 83,
				sequence = p.sequence,
				timestamp = 0,
				source_id = null
			};
			
			uint8[] payload = ostream.steal_data();
			payload.length = (int)ostream.get_data_size();
			c.send(outp, payload);
		} catch (Error e) {
			// TODO error handling!
			stderr.printf(e.message);
		}		
	}
	
	public size_t write_raw(uint8[] data)
	{
		return audio_buffer.write(data);
	}
	
	public uint get_queued_samples()
	{
		return (uint)audio_buffer.get_read_space() / 4;
	}
}

}
