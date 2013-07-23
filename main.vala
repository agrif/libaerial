private static string? host = null;

private const GLib.OptionEntry[] options = {
	{"host", 'h', 0, OptionArg.STRING, ref host, "airtunes server", "HOST"},
	
	{ null }
};

public int main(string[] args)
{
	try
	{
		var opts = new GLib.OptionContext("- an airtunes test client");
		opts.set_help_enabled(true);
		opts.add_main_entries(options, null);
		opts.parse(ref args);
	} catch (OptionError e) {
		stderr.printf("error: %s\n", e.message);
		stderr.printf("run %s --help to see some help\n", args[0]);
		return 1;
	}
	
	if (host == null)
		host = "localhost";
	
	stdout.printf("connecting to %s\n", host);
	var client = new Aerial.Client();
	try
	{
		var loop = new GLib.MainLoop();
		client.on_error.connect((c, err) =>
			{
				stderr.printf("error: %s\n", err.message);
			});
		client.notify["state"].connect((o, p) =>
			{
				stdout.printf("client entered state %s\n", client.state.to_string());
			});
		
		client.connect_to_host(host);
		client.play();
		client.set_volume(1.0f);
		client.set_metadata("Aerial Test Signal");
		
		uint32 t = 0;
		Idle.add(() =>
			{
				var freq = 440.0;
				uint8[] buf = {};
				buf.resize(1024 * 4);
				for (var i = 0; i < 1024; i++)
				{
					var sample = Math.sin((t + i) * 2 * Math.PI * freq / Aerial.Client.FRAMES_PER_SECOND);
					int16 samplei = (int16)(sample * int16.MAX);
					Memory.copy(&buf[4 * i], &samplei, 2);
					Memory.copy(&buf[4 * i + 2], &samplei, 2);
				}

				var written = client.write(buf);
				t += (uint32)(written / 4);

				return true;
			});
		Timeout.add(5000, () =>
			{
				loop.quit();
				return false;
			});
		
		loop.run();
	} catch (Error e) {
	} finally {
		try
		{
			client.disconnect_from_host();			
		} catch (Error e) {
		}
	}
	return 0;
}
