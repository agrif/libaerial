public class AirtunesSink : Gst.Audio.Sink
{
	static construct
	{
		set_metadata("Airtunes Sink", "FIXME:General", "an audio sink for airtunes devices", "Aaron Griffith <aargri@gmail.com>");
		
		var caps = new Gst.Caps.empty_simple("audio/x-raw");
		caps.set_value("rate", 44100);
		caps.set_value("layout", "interleaved");
		caps.set_value("channels", 2);
		// TODO use native endianness (this breaks BE systems)
		caps.set_value("format", "S16LE");
		
		var sink = new Gst.PadTemplate("sink", Gst.PadDirection.SINK, Gst.PadPresence.ALWAYS, caps);
		add_pad_template(sink);
	}
	
	public string host { get; set; default = "localhost"; }
	private Airtunes.Client? client = null;
	
	public override bool open()
	{
		client = new Airtunes.Client();
		client.on_error.connect((c, e) =>
			{
				stderr.printf("got error %s\n", e.message);
			});
		client.notify["state"].connect((c, prop) =>
			{
				stdout.printf("client changed to state %s\n", client.state.to_string());
			});
		
		try
		{
			stdout.printf("connecting to %s\n", host);
			client.connect_to_host(host);
			client.play();
			return true;
		} catch (Error e) {
			return false;
		}
	}
	
	public override bool prepare(Gst.Audio.RingBufferSpec spec)
	{
		return true;
	}
	
	public override bool unprepare()
	{
		return true;
	}
	
	public override bool close()
	{
		client = null;
		return true;
	}
	
	public override int write(uint8[] data)
	{
		return (int)client.write_raw(data);
	}
	
	public override uint delay()
	{
		return client.get_queued_samples();
	}
	
	public override void reset()
	{
		//
	}
}

static bool plugin_init(Gst.Plugin plugin)
{
	return Gst.Element.register(plugin, "airtunes", Gst.Rank.NONE, typeof(AirtunesSink));
}
