namespace Airtunes
{

public struct RTSPResponse
{
	public int code;
	public string message;
	public HashTable<string, string> headers;
}

public errordomain RTSPError
{
	BAD_RESPONSE,
}

public class RTSP : Object
{
	private const uint16 DEFAULT_PORT = 5000;
	private const string PROTOCOL = "RTSP/1.0";
	// TODO track version properly
	private const string USER_AGENT = "libairtunes/0.0.0";
	private const string WHITESPACE = " ";
	private const string LOGDOMAIN = "AirtunesRTSP";

	// address of the server
	public string? remote_address { get; private set; default = null; }
	// our address
	public string? local_address { get; private set; default = null; }
	// used in the default outgoing RTSP urls
	public uint32 client_session { get; private set; }
	
	// given by the server during SETUP, used in Session: header
	private string? session = null;
	// used as CSeq: header on outgoing
	private int sequence;
	// used as Client-Instance: header on outgoing
	private string client_instance;

	// connection stuff
	private SocketClient connector;
	private SocketConnection socket;
	private DataOutputStream output;
	private DataInputStream input;
	
	construct
	{
		client_session = Random.next_int();
		sequence = 0;
		client_instance = bytes_to_hex(random_bytes(8));
		connector = new SocketClient();
	}
	
	public bool connect_to_host(string host_and_port) throws Error
	{
		socket = connector.connect_to_host(host_and_port, DEFAULT_PORT);
		setup_streams();
		return true;
	}
	
	public async bool connect_to_host_async(string host_and_port) throws Error
	{
		socket = yield connector.connect_to_host_async(host_and_port, DEFAULT_PORT);
		setup_streams();
		return true;
	}
	
	private void setup_streams() throws Error
	{
		input = new DataInputStream(socket.input_stream);
		output = new DataOutputStream(socket.output_stream);
		input.newline_type = DataStreamNewlineType.CR_LF;		
		
		var isa = socket.get_remote_address() as InetSocketAddress;
		remote_address = isa.address.to_string();
		isa = socket.get_local_address() as InetSocketAddress;
		local_address = isa.address.to_string();
	}

	private async string? recv_line() throws IOError
	{
		var line = yield input.read_line_async();
		log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, ">>> %s", line);
		return line;
	}
	
	public async RTSPResponse recv_response() throws IOError, RTSPError
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
		
		// set our session if we get a Session header
		if ("Session" in resp.headers)
			session = resp.headers["Session"];
		
		return resp;
	}
	
	private bool send_line(string line) throws IOError
	{
		string s = line + "\r\n";
		log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, "<<< %s", line);
		return output.put_string(s);
	}
	
	public bool request_full(string name, string? uri=null, string? data=null, ...) throws IOError
	{
		var l = va_list();
		
		var r = request(name, uri);
		if (!r)
			return r;
		while (true)
		{
			string? key = l.arg();
			if (key == null)
				break;
			string val = l.arg();
			r = header(key, val);
			if (!r)
				return r;
		}
		return finish(data);
	}
	
	public bool request(string name, string? uri=null) throws IOError
	{
		var final_uri = uri;
		if (uri == null)
			final_uri = "rtsp://%s/%u".printf(remote_address, (uint)client_session);
		
		string s = "%s %s %s".printf(name, final_uri, PROTOCOL);
		sequence++;
		return send_line(s) &&
			header("CSeq", "%i", sequence) &&
			header("Client-Instance", client_instance) &&
			(session == null || header("Session", session)) &&
			header("User-Agent", USER_AGENT);
	}
	
	[PrintfFormat]
    public bool header(string name, string format, ...) throws IOError
	{
		var l = va_list();
		var val = format.vprintf(l);
		return header_raw(name, val);
	}
	
	public bool header_raw(string name, string value) throws IOError
	{
		string s = "%s: %s".printf(name, value);
		return send_line(s);
	}
	
	[PrintfFormat]
	public bool finish(string? format=null, ...) throws IOError
	{
		var l = va_list();
		if (format == null)
			return send_line("");
		
		var body = format.vprintf(l);
		log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, "body: %s", body);
		if (body == null)
			return send_line("");
		return finish_raw(body.data);
	}
	
	public bool finish_raw(uint8[] data) throws IOError
	{
		var b = header("Content-Length", "%u", (uint)data.length) && send_line("");
		if (!b)
			return b;
		
		
		return output.write(data) == data.length;
	}
}

}