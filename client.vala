namespace Airtunes
{

public extern bool alac_encode(uint8[] input, out uint8[] output);

public errordomain ClientError
{
	HANDSHAKE_FAILED,
}

public delegate int64 ClockFunc();

public enum ClientState
{
	// when first created, and after disconnection/error
	DISCONNECTED,
	// after connection is made, before it's ready to accept data
	CONNECTED,
	// connected and ready to accept data
	READY,
	// connected, ready, and currently streaming data
	PLAYING,
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
	
	// used to get a monotonic time
	// units are in microseconds! 1000000μs == 1s
	// if not set, we use GLib.get_monotonic_time()
	public ClockFunc clock_func { get; set; default = get_monotonic_time; }
	// connection state
	public ClientState state { get; private set; default = ClientState.DISCONNECTED; }
	public signal void on_error(Error e);
	
	// set by connect_to_host
	private string? connect_host_and_port = null;
	
	// AES key and IV
	private uint8[] aes_key;
	private uint8[] aes_iv;
	private string rsa_aes_key;
	// whether the remote requires encryption
	private bool require_encryption = false;
	
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
	// used to position audio packets in time
	private uint32 timestamp;
	// used to sequence audio packets
	private uint16 sequence;
	
	private RingBuffer audio_buffer;
	
	private RTSP rtsp_channel;
	private RTP server_channel;
	private RTP control_channel;
	private RTP timing_channel;
	
	construct
	{
		timestamp = GLib.Random.next_int();
		sequence = (uint16) GLib.Random.next_int();
		
		// TODO generate keys! (needs rsa encryption)
		//aes_key = random_bytes(16);
		//aes_iv = random_bytes(16);
		aes_key = { 0x14, 0x49, 0x7d, 0xcc, 0x98, 0xe1, 0x37, 0xa8, 0x55, 0xc1, 0x45, 0x5a, 0x6b, 0xc0, 0xc9, 0x79 };
		aes_iv = { 0x78, 0xf4, 0x41, 0x2c, 0x8d, 0x17, 0x37, 0x90, 0x2b, 0x15, 0xa6, 0xb3, 0xee, 0x77, 0x0d, 0x67 };
		rsa_aes_key = "VjVbxWcmYgbBbhwBNlCh3K0CMNtWoB844BuiHGUJT51zQS7SDpMnlbBIobsKbfEJ3SCgWHRXjYWf7VQWRYtEcfx7ejA8xDIk5PSBYTvXP5dU2QoGrSBv0leDS6uxlEWuxBq3lIxCxpWO2YswHYKJBt06Uz9P2Fq2hDUwl3qOQ8oXb0OateTKtfXEwHJMprkhsJsGDrIc5W5NJFMAo6zCiM9bGSDeH2nvTlyW6bfI/Q0v0cDGUNeY3ut6fsoafRkfpCwYId+bg3diJh+uzw5htHDyZ2sN+BFYHzEfo8iv4KDxzeya9llqg6fRNQ8d5YjpvTnoeEQ9ye9ivjkBjcAfVw";
		
		audio_packets.resize(PACKET_BACKLOG);
		for (var i = 0; i < audio_packets.length; i++)
			audio_packets[i] = AudioPacket();
		
		audio_buffer = new RingBuffer();
		audio_buffer.init(BUFFER_SIZE);
		
		rtsp_channel = new RTSP();
	}
	
	private bool transition(ClientState target) throws Error
	{
		var loop = new MainLoop();
		bool ret = false;
		Error? err = null;
		transition_async.begin(target, (obj, res) =>
			{
				try
				{
					ret = transition_async.end(res);
				} catch (Error e) {
					err = e;
				}
				loop.quit();
			});
		loop.run();
		
		if (err != null)
			throw err;
		return ret;
	}
	
	private async bool transition_async(ClientState target) throws Error
	{
		try
		{
			return yield transition_intern(target);
		} catch (Error e) {
			on_error(e);
			throw e;
		}
	}
	
	private async bool transition_intern(ClientState target) throws Error
	{
		if (target == state)
			return true;
		
		var elevate = (target > state);
		return_if_fail(elevate); // TODO de-elevating not yet implemented
		
		while (state != target)
		{
			bool success = false;
			if (elevate)
				success = yield elevate_state();
			
			if (!success)
				return false;
		}
		
		return true;
	}
	
	private async bool elevate_state() throws Error
	{
		switch (state)
		{
		case ClientState.DISCONNECTED:
			return_if_fail(connect_host_and_port != null);
			yield rtsp_channel.connect_to_host_async(connect_host_and_port);
		
			// generate 16 random bytes for apple-challenge
			var apple_challenge = bytes_to_base64(random_bytes(16));
			
			// send RTSP OPTIONS
			rtsp_channel.request_full("OPTIONS", "*", null,
									  Apple_Challenge: apple_challenge);
			
			var resp = yield rtsp_channel.recv_response();
			if (resp.code != 200)
				throw new ClientError.HANDSHAKE_FAILED(resp.message);
			if ("Apple-Response" in resp.headers)
				require_encryption = true;
			
			if (require_encryption)
				debug("using encryption");
			else
				debug("not using encryption");

			state = ClientState.CONNECTED;
			return true;

		case ClientState.CONNECTED:
			// send RTSP ANNOUNCE
			// TODO - use auth, if needed
			rtsp_channel.request("ANNOUNCE");
			rtsp_channel.header("Content-Type", "application/sdp");
			rtsp_channel.finish(("v=0\r\n" +
								 "o=iTunes %u O IN IP4 %s\r\n" +
								 "s=iTunes\r\n" +
								 "c=IN IP4 %s\r\n" +
								 "t=0 0\r\n" +
								 "m=audio 0 RTP/AVP 96\r\n" +
								 "a=rtpmap:96 AppleLossless\r\n" +
								 "a=fmtp:96 %i 0 16 40 10 14 2 255 0 0 %i\r\n" +
								 "a=rsaaeskey:%s\r\n" +
								 "a=aesiv:%s\r\n"),
								(uint)rtsp_channel.client_session,
								rtsp_channel.remote_address,
								rtsp_channel.local_address,
								FRAMES_PER_PACKET,
								TIMESTAMPS_PER_SECOND,
								rsa_aes_key,
								bytes_to_base64(aes_iv));
			
			var resp = yield rtsp_channel.recv_response();
			if (resp.code != 200)
				throw new ClientError.HANDSHAKE_FAILED(resp.message);
			
			// send RTSP SETUP
			// TODO select ports for control and timing
			var local_server_port = 6000;
			var local_control_port = 6001;
			var local_timing_port = 6002;

			server_channel = new RTP(rtsp_channel.local_address, local_server_port);
			control_channel = new RTP(rtsp_channel.local_address, local_control_port);
			timing_channel = new RTP(rtsp_channel.local_address, local_timing_port);
			
			server_channel.uses_source_id = true;
			control_channel.uses_timestamp = false;

			//control_channel.verbose = true;
			//timing_channel.verbose = true;
			//server_channel.verbose = true;
			
			rtsp_channel.request("SETUP");
			rtsp_channel.header("Transport",
								"RTP/AVP/UDP;unicast;interleaved=0-1;mode=record;control_port=%i;timing_port=%i",
								local_control_port, local_timing_port);
			rtsp_channel.finish();
			
			resp = yield rtsp_channel.recv_response();
			if (resp.code != 200)
				throw new ClientError.HANDSHAKE_FAILED(resp.message);
			if (!("Transport" in resp.headers))
				throw new ClientError.HANDSHAKE_FAILED("did not get transport from server");
			
			var transport = resp.headers["Transport"];
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
				throw new ClientError.HANDSHAKE_FAILED("did not get ports from server");
			
			server_channel.connect_to(rtsp_channel.remote_address, server_port);
			timing_channel.connect_to(rtsp_channel.remote_address, timing_port);
			control_channel.connect_to(rtsp_channel.remote_address, control_port);
			
			timing_ref_time = clock_func();			
			timing_channel.on_packet.connect(on_timing_packet);
			control_channel.on_packet.connect(on_resend_packet);
						
			// send RTSP RECORD (using seq/timestamp)
			rtsp_channel.request("RECORD");
			rtsp_channel.header("Range", "ntp=0-");
			rtsp_channel.header("RTP-Info", "seq=%u;rtptime=%u", sequence, timestamp);
			rtsp_channel.finish();
			
			resp = yield rtsp_channel.recv_response();
			if (resp.code != 200)
				throw new ClientError.HANDSHAKE_FAILED(resp.message);
		
			state = ClientState.READY;
			return true;
		
		case ClientState.READY:
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
		
			state = ClientState.PLAYING;
			return true;
		
		default:
			return_if_reached();
		}
	}

	public bool connect_to_host(string host_and_port) throws Error
	{
		return_if_fail(state == ClientState.DISCONNECTED);
		connect_host_and_port = host_and_port;
		return transition(ClientState.CONNECTED);
	}
	
	public async bool connect_to_host_async(string host_and_port) throws Error
	{
		return_if_fail(state == ClientState.DISCONNECTED);
		connect_host_and_port = host_and_port;
		return yield transition_async(ClientState.CONNECTED);
	}

	public bool play() throws Error
	{
		return transition(ClientState.PLAYING);
	}
	
	public async bool play_async() throws Error
	{
		return yield transition_async(ClientState.PLAYING);
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
			source_id = rtsp_channel.client_session
		};
		
		// +16 for the ALAC header
		var data_size = 2 * SHORTS_PER_PACKET;
		uint8[] frames = {};
		frames.resize(data_size);
		uint8[] payload;
		audio_buffer.read(frames);
		if (!alac_encode(frames, out payload))
		{
			// TODO error
			stderr.printf("encode fail\n");
			return;
		}
		timestamp += FRAMES_PER_PACKET;
		frames_since_sync += FRAMES_PER_PACKET;
		
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
			last_sync_time = clock_func();
			last_sync_timestamp = timestamp;
			timestamp_delta = 0;
		}
		
		var projected_timestamp = last_sync_timestamp;
		var now = clock_func();
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
		var mono = (uint64)(clock_func() - timing_ref_time);
		
		var seconds = (uint64)(mono / 1000000) + NTP_EPOCH;
		var microsecs = (uint64)(mono % 1000000);
		microsecs *= (uint64)1 << 32;
		microsecs /= 1000000;
		return (seconds << 32) | (microsecs & 0xffffffff);
	}
	
	private void on_resend_packet(RTP c, RTPPacket p, DataInputStream dat)
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
	
	private void on_timing_packet(RTP c, RTPPacket p, DataInputStream dat)
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
	
	// native endian!!
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
