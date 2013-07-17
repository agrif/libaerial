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
	var client = new Airtunes.Client();
	try
	{
		var loop = new GLib.MainLoop();
		client.connect_to_host(host);
		loop.run();
	} catch (Error e) {
		stderr.printf("error: %s\n", e.message);
		return 1;
	}
	return 0;
}
