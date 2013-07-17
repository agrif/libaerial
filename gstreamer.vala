private class AirtunesSink : Gst.Audio.Sink
{
	public override bool open()
	{
		debug("open");
		return true;
	}
}

static bool plugin_init(Gst.Plugin plugin)
{
	return Gst.Element.register(plugin, "airtunes", Gst.Rank.NONE, typeof(AirtunesSink));
}
