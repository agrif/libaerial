namespace Aerial
{

public extern bool alac_encode(uint8[] input, out uint8[] output);

public errordomain ClientError
{
	HANDSHAKE_FAILED,
}

public delegate int64 ClockFunc();

public enum ImageType
{
	PNG,
	JPEG,
}

private enum ParameterType
{
	VOLUME = 1 << 0,
	METADATA = 1 << 1,
	ARTWORK = 1 << 2,
	PROGRESS = 1 << 3;
	
	public bool supports(ParameterType type)
	{
		return (this & type) != 0;
	}
}

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
	public const int BYTES_PER_FRAME = 4;
	public const int FRAMES_PER_SECOND = 44100;

	private const int FRAMES_PER_PACKET = 352;
	private const int BYTES_PER_PACKET = BYTES_PER_FRAME * FRAMES_PER_PACKET;
	private const int SYNC_INTERVAL = 1000;
	private const int TIME_PER_PACKET = (FRAMES_PER_PACKET * 1000 / FRAMES_PER_SECOND) - 1;
	private const int PACKET_BACKLOG = 1024;	
	private const int64 NTP_EPOCH = 0x83aa7e80;
	
	private const string LOGDOMAIN = "AerialClient";

	// used to get a monotonic time
	// units are in microseconds! 1000000μs == 1s
	public ClockFunc clock_func { get; set; default = get_monotonic_time; }
	// size of buffer to use on device (in ms)
	public uint remote_buffer_length { get; set; default = 2000; }
	// size of buffer here (in ms)
	public uint local_buffer_length { get; set; default = 2000; }
	// whether to automatically send sync packets
	public bool auto_sync { get; set; default = true; }
	// how far behind the current time to play samples (in ms)
	// only useful when auto_sync is true
	public uint delay { get; set; default = 2000; }
	// connection state
	public ClientState state { get; private set; default = ClientState.DISCONNECTED; }
	// called for all errors, even those that propogate to the caller
	// (in addition to the asynchronously-caused ones)
	// by the time this is called, an appropriate state de-elevation has occurred
	public signal void on_error(Error e);
	
	// set by connect_to_host
	private string? connect_host_and_port = null;
	
	// AES key and IV
	private uint8[] aes_key;
	private uint8[] aes_iv;
	private string rsa_aes_key;
	// whether the remote requires encryption
	private bool require_encryption = false;
	
	// what sort of parameters our endpoint supports
	private ParameterType parameter_types = 0;
	
	// our timers!
	private TimeoutSource? sync_source = null;
	private TimeoutSource? audio_source = null;
	// whether we've sent a sync/audio packet yet
	private bool first_sync_sent = false;
	private bool first_audio_sent = false;
	// reference time for when the channels opened
	private int64 timing_ref_time;
	// when the last sync packet was emitted
	private int64 last_sync_time;
	// what timestamp the last sync packet had
	private uint32 last_sync_timestamp;
	
	// previously-sent audio packets
	private AudioPacket[] audio_packets;
	// used to position audio packets in time
	private uint32 timestamp;
	// used to sequence audio packets
	private uint16 sequence;
	
	private RingBuffer audio_buffer;
	
	private RTSP? rtsp_channel = null;
	private RTP? server_channel = null;
	private RTP? control_channel = null;
	private RTP? timing_channel = null;
	
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
		
		audio_buffer = RingBuffer();
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
			// bring the whole thing down without stopping
			rtsp_channel = null;
			try
			{
				transition(ClientState.DISCONNECTED);
			} catch (Error se) {
				// this should always, always work, so...
				return_if_reached();
			}
			on_error(e);
			throw e;
		}
	}
	
	private async bool transition_intern(ClientState target) throws Error
	{
		if (target == state)
			return true;
		
		var elevate = (target > state);
		
		while (state != target)
		{
			bool success = false;
			if (elevate)
				success = yield elevate_state();
			else
				success = yield deelevate_state();
			
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
			rtsp_channel = new RTSP();
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
			{
				// best guess: airport express
				require_encryption = true;
				parameter_types = ParameterType.VOLUME;
			} else {
				// something later, hopefully supports everything
				require_encryption = false;
				parameter_types = ParameterType.VOLUME | ParameterType.METADATA | ParameterType.ARTWORK | ParameterType.PROGRESS;
			}
			
			if (require_encryption)
				log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, "using encryption");
			else
				log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, "not using encryption");

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
								FRAMES_PER_SECOND,
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
			
			server_channel.on_error.connect(on_channel_error);
			control_channel.on_error.connect(on_channel_error);
			timing_channel.on_error.connect(on_channel_error);
			
			server_channel.uses_source_id = true;
			control_channel.uses_timestamp = false;

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
			first_sync_sent = false;
			first_audio_sent = false;
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
			// prepare RTP connection for audio
			
			audio_buffer.init((local_buffer_length * FRAMES_PER_SECOND / 1000) * BYTES_PER_FRAME);
			
			if (auto_sync)
			{
				var startsync = timestamp - (uint32)(delay * FRAMES_PER_SECOND / 1000);
				log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, "auto-sync starting at timestamp %u", startsync);
				sync(startsync);
				sync_source = new TimeoutSource(SYNC_INTERVAL);
				sync_source.set_callback(() =>
					{
						try
						{
							var est = estimated_timestamp();
							var rb = (float)(timestamp - est) / FRAMES_PER_SECOND;
							var lb = (float)(audio_buffer.get_read_space() / BYTES_PER_FRAME) / FRAMES_PER_SECOND;
							log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, "auto-sync timestamp %u remote-buffer %fms local-buffer %fms", est, rb * 1000, lb * 1000);
							sync(estimated_timestamp());
						} catch (Error e) {
							// handled within sync already
						}
						return true;
					});
				sync_source.attach(MainContext.default());
			}

			audio_source  = new TimeoutSource(TIME_PER_PACKET);
			audio_source.set_callback(() => { send_audio_packet(); return true; });
			audio_source.attach(MainContext.default());
		
			state = ClientState.PLAYING;
			return true;
		
		default:
			return_if_reached();
		}
	}
	
	private async bool deelevate_state() throws Error
	{
		// special thing here: cannot throw ANY ERRORS when
		// rtsp_channel == null. This means we're closing shop forever!
		
		switch (state)
		{
		case ClientState.PLAYING:
			// reset sync/audio state
			first_sync_sent = false;
			first_audio_sent = false;
			if (audio_source != null)
				audio_source.destroy();
			if (sync_source != null)
				sync_source.destroy();
			audio_source = null;
			sync_source = null;
			
			// send the FLUSH if rtsp_channel is still up
			if (rtsp_channel != null)
			{
				rtsp_channel.request("FLUSH");
				rtsp_channel.header("RTP-Info", "seq=%u;rtptime=%u", sequence, timestamp);
				rtsp_channel.finish();
				
				var resp = yield rtsp_channel.recv_response();
				if (resp.code != 200)
					throw new ClientError.HANDSHAKE_FAILED(resp.message);
			}
			
			state = ClientState.READY;
			return true;
		
		case ClientState.READY:
			// send TEARDOWN if rtsp_channel is still up
			if (rtsp_channel != null)
			{
				rtsp_channel.request_full("TEARDOWN", null, null);
				var resp = yield rtsp_channel.recv_response();
				if (resp.code != 200)
					throw new ClientError.HANDSHAKE_FAILED(resp.message);
			}
			
			server_channel = null;
			control_channel = null;
			timing_channel = null;
			
			state = ClientState.CONNECTED;
			return true;
		
		case ClientState.CONNECTED:
			rtsp_channel = null;
			
			state = ClientState.DISCONNECTED;
			return true;
		
		default:
			return_if_reached();
		}
	}

	private bool set_parameter(uint32? tstamp, string content_type, uint8[] body) throws Error
	{
		var loop = new MainLoop();
		bool ret = false;
		Error? err = null;
		set_parameter_async.begin(tstamp, content_type, body, (obj, res) =>
			{
				try
				{
					ret = set_parameter_async.end(res);
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
	
	private async bool set_parameter_async(uint32? tstamp, string content_type, uint8[] body) throws Error
	{
		try
		{
			return yield set_parameter_intern(tstamp, content_type, body);
		} catch (Error e) {
			// bring the whole thing down without stopping
			rtsp_channel = null;
			try
			{
				transition(ClientState.DISCONNECTED);
			} catch (Error se) {
				// this should always, always work, so...
				return_if_reached();
			}
			on_error(e);
			throw e;
		}
	}
	
	private async bool set_parameter_intern(uint32? tstamp, string content_type, uint8[] body) throws Error
	{
		return_if_fail(state >= ClientState.READY);
		
		if (tstamp == null)
			tstamp = timestamp + (uint32)(audio_buffer.get_read_space() / BYTES_PER_FRAME);
		
		rtsp_channel.request("SET_PARAMETER");
		rtsp_channel.header("RTP-Info", "rtptime=%u", tstamp);
		rtsp_channel.header("Content-Type", content_type);
		rtsp_channel.finish_raw(body);
		
		var resp = yield rtsp_channel.recv_response();
		if (resp.code != 200)
			throw new ClientError.HANDSHAKE_FAILED("could not SET_PARAMETER");
		return true;
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
	
	public bool disconnect_from_host() throws Error
	{
		return transition(ClientState.DISCONNECTED);
	}
	
	public async bool disconnect_from_host_async() throws Error
	{
		return yield transition_async(ClientState.DISCONNECTED);
	}

	public bool play() throws Error
	{
		return transition(ClientState.PLAYING);
	}
	
	public async bool play_async() throws Error
	{
		return yield transition_async(ClientState.PLAYING);
	}
	
	public bool stop() throws Error
	{
		if (state == ClientState.PLAYING)
			return transition(ClientState.READY);
		return true;
	}
	
	public async bool stop_async() throws Error
	{
		if (state == ClientState.PLAYING)
			return yield transition_async(ClientState.READY);
		return true;
	}
	
	private float get_dbvol(float volume)
	{
		var dbvol = -30.0f + (30.0f * volume);
		if (dbvol <= -30.0f)
			dbvol = -144.0f; // muted
		if (dbvol >= 0.0f)
			dbvol = 0.0f;
		return dbvol;
	}
	
	// between 0 and 1
	public bool set_volume(float volume, uint32? tstamp = null) throws Error
	{
		if (!parameter_types.supports(ParameterType.VOLUME))
			return true;
		var dbvol = get_dbvol(volume);
		var body = "volume: %f\r\n".printf(dbvol);
		return set_parameter(tstamp, "text/parameters", body.data);
	}

	public async bool set_volume_async(float volume, uint32? tstamp=null) throws Error
	{
		if (!parameter_types.supports(ParameterType.VOLUME))
			return true;
		var dbvol = get_dbvol(volume);
		var body = "volume: %f\r\n".printf(dbvol);
		return yield set_parameter_async(tstamp, "text/parameters", body.data);
	}
	
	private uint8[] dmap_metadata(string? title, string? artist, string? album) throws Error
	{
		var dmap = DMAP();
		dmap.init();
		dmap.start_container("mlit");
		if (title != null)
			dmap.put_string("minm", title);
		if (artist != null)
			dmap.put_string("asar", artist);
		if (album != null)
			dmap.put_string("asal", album);
		dmap.end_container();
		dmap.close();
		var metadata = dmap.steal_data();
		
		string buf = "";
		foreach (var b in metadata)
		{
			buf += "%02x ".printf(b);
		}
		log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, "DMAP metadata: %s", buf);
		
		return metadata;
	}
	
	public bool set_metadata(string? title=null, string? artist=null, string? album=null, uint32? tstamp=null) throws Error
	{
		if (!parameter_types.supports(ParameterType.METADATA))
			return true;
		var body = dmap_metadata(title, artist, album);
		return set_parameter(tstamp, "application/x-dmap-tagged", body);
	}
	
	public async bool set_metadata_async(string? title=null, string? artist=null, string? album=null, uint32? tstamp=null) throws Error
	{
		if (!parameter_types.supports(ParameterType.METADATA))
			return true;
		var body = dmap_metadata(title, artist, album);
		return yield set_parameter_async(tstamp, "application/x-dmap-tagged", body);
	}
	
	private string get_mime(ImageType type)
	{
		string content_type;
		switch (type)
		{
		case ImageType.PNG:
			content_type = "image/png";
			break;
		case ImageType.JPEG:
			content_type = "image/jpeg";
			break;
		default:
			return_if_reached();
		}
		return content_type;
	}
	
	public bool set_artwork(ImageType type, uint8[] data, uint32? tstamp=null) throws Error
	{
		if (!parameter_types.supports(ParameterType.ARTWORK))
			return true;
		return set_parameter(tstamp, get_mime(type), data);
	}
	
	public async bool set_artwork_async(ImageType type, uint8[] data, uint32? tstamp=null) throws Error
	{
		if (!parameter_types.supports(ParameterType.ARTWORK))
			return true;
		return yield set_parameter_async(tstamp, get_mime(type), data);
	}
	
	// times are in seconds!
	public bool set_progress(float length, float current, uint32? tstamp=null) throws Error
	{
		if (!parameter_types.supports(ParameterType.PROGRESS))
			return true;
		
		if (tstamp == null)
			tstamp = timestamp + (uint32)(audio_buffer.get_read_space() / BYTES_PER_FRAME);
		
		var start = tstamp - (uint32)(current * FRAMES_PER_SECOND);
		var end = start + (uint32)(length * FRAMES_PER_SECOND);
		var progress = "progress: %u/%u/%u\r\n".printf(start, tstamp, end);
		return set_parameter(tstamp, "text/parameters", progress.data);
	}
	
	public async bool set_progress_async(float length, float current, uint32? tstamp=null) throws Error
	{
		if (!parameter_types.supports(ParameterType.PROGRESS))
			return true;
		
		if (tstamp == null)
			tstamp = timestamp + (uint32)(audio_buffer.get_read_space() / BYTES_PER_FRAME);
		
		var start = tstamp - (uint32)(current * FRAMES_PER_SECOND);
		var end = start + (uint32)(length * FRAMES_PER_SECOND);
		var progress = "progress: %u/%u/%u\r\n".printf(start, tstamp, end);
		return yield set_parameter_async(tstamp, "text/parameters", progress.data);
	}
	
	private void send_audio_packet()
	{
		return_if_fail(server_channel != null);
		
		// delay until first sync is sent
		if (!first_sync_sent)
			return;
		
		// if we're ahead of the allowed device buffer, skiy
		if (timestamp - estimated_timestamp() > remote_buffer_length * FRAMES_PER_SECOND / 1000)
			return;
		
		// if we don't have data, also ignore this
		if (audio_buffer.get_read_space() < BYTES_PER_PACKET)
		{
			return;
		}
		
		var outp = RTPPacket() {
			version = 2,
			padding = false,
			extension = false,
			source_id_count = 0,
			marker = !first_audio_sent,
			payload_type = 96,
			sequence = sequence,
			timestamp = timestamp,
			source_id = rtsp_channel.client_session
		};
		
		uint8[] frames = {};
		frames.resize(BYTES_PER_PACKET);
		uint8[] payload;
		audio_buffer.read(frames);
		if (!alac_encode(frames, out payload))
		{
			// we should never fail at *encoding*
			return_if_reached();
		}
		timestamp += FRAMES_PER_PACKET;
		
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
			
			first_audio_sent = true;
		} catch (Error e) {
			try
			{
				transition(ClientState.CONNECTED);
			} catch (Error se) {
				// handled in transition
			}
			on_error(e);
		}
	}
	
	public bool sync(uint32 sync_timestamp) throws Error
	{
		return_if_fail(control_channel != null);
		
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
			extension = !first_sync_sent,
			source_id_count = 0,
			marker = true,
			payload_type = 84,
			sequence = 7, // yes, on purpose. ewwwwww
			timestamp = sync_timestamp,
			source_id = null
		};
		
		// okay so here's the (assumed) deal with this packet
		// the RTP header timestamp is the one that should be playing
		// RIGHT NOW, as defined by the now() time in the ntptime.
		// the payload timestamp after that is the next one we'll send
		
		// the RIGHT NOW timestamp should be very carefully calculated
		// so that as close to FRAMES_PER_SECOND pass every second
		// and (importantly!) should be independent of the audio packet rate
		// or you'll get skipping!
		
		try
		{
			control_channel.send(outp, payload);
			first_sync_sent = true;
			last_sync_time = clock_func();
			last_sync_timestamp = sync_timestamp;
		} catch (Error e) {
			try
			{
				transition(ClientState.CONNECTED);
			} catch (Error se) {
				// handled in transition
			}
			on_error(e);
			throw e;
		}
		
		return true;
	}
	
	public uint32 estimated_timestamp()
	{
		return_if_fail(first_sync_sent);
		var now = clock_func();
		var tsdelta = (now - last_sync_time) * FRAMES_PER_SECOND / 1000000;
		return last_sync_timestamp + (uint32)tsdelta;
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
	
	private void on_channel_error(RTP c, Error e)
	{
		try
		{
			transition(ClientState.CONNECTED);
			on_error(e);
		} catch (Error se) {
			// handled in transition
		}
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
			for (var s = first_seq; s < first_seq + count; s++)
			{
				var i = s % audio_packets.length;
				if (audio_packets[i].in_use && audio_packets[i].sequence == s)
				{
					log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, "resending packet %u", s);
					c.send(outp, audio_packets[i].data);
				} else {
					log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, "packet %u requested but not found", s);
				}
			}
		} catch (Error e) {
			try
			{
				transition(ClientState.CONNECTED);
			} catch (Error se) {
				// handled in transition
			}
			on_error(e);
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
			try
			{
				transition(ClientState.CONNECTED);
			} catch (Error se) {
				// handled in transition
			}
			on_error(e);
		}		
	}
	
	// native endian!! 16-bit! signed!!!
	public size_t write(uint8[] data, out uint32 scheduled = null)
	{
		return_if_fail(state >= ClientState.PLAYING);
		return_if_fail(data.length % BYTES_PER_FRAME == 0);
		
		scheduled = timestamp;
		scheduled += (uint32)(audio_buffer.get_read_space() / BYTES_PER_FRAME);
		
		var to_write = (int)audio_buffer.get_write_space() / BYTES_PER_FRAME;
		to_write *= BYTES_PER_FRAME;
		to_write = int.min(data.length, to_write);
		
		uint8[] adjusted_data = data;
		adjusted_data.length = to_write;
		
		var written = audio_buffer.write(adjusted_data);
		assert(written % BYTES_PER_FRAME == 0);
		return written;
	}
	
	public uint get_queued_samples()
	{
		uint32 queued_remote = 0;
		if (first_sync_sent)
			queued_remote = timestamp - estimated_timestamp();
		var queued_local = audio_buffer.get_read_space() / BYTES_PER_FRAME;
		return (uint)(queued_remote + queued_local);
	}
}

}
