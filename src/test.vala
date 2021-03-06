/* libaerial - an AirPlay audio client
 * Copyright (C) 2013 Aaron Griffith
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	 See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 */

extern const string PACKAGE_NAME;
extern const string PACKAGE_VERSION;
extern const string PACKAGE_BUGREPORT;
extern const string PACKAGE_URL;

private static bool version = false;
private static string? host = null;

private const GLib.OptionEntry[] options = {
	{"version", 0, 0, OptionArg.NONE, ref version, "print verision and exit", null},
	{"host", 'h', 0, OptionArg.STRING, ref host, "airtunes server to connect to", "HOST"},
	
	{ null }
};

public int main(string[] args)
{
	try
	{
		var opts = new GLib.OptionContext("- an airtunes test client");
		opts.set_summary(
			" Connects to the provided server and emits a sine wave at 440Hz for 10 seconds."
			);
		opts.set_description(
			" This program is distributed as part of " + PACKAGE_NAME + ". Please report bugs to\n" +
			" <" + PACKAGE_URL + ">.\n"
			);
		opts.set_help_enabled(true);
		opts.add_main_entries(options, null);
		opts.parse(ref args);
	} catch (OptionError e) {
		stderr.printf("error: %s\n", e.message);
		stderr.printf("run %s --help to see some help\n", args[0]);
		return 1;
	}
	
	if (version)
	{
		stdout.printf("%s %s\n", PACKAGE_NAME, PACKAGE_VERSION);
		return 0;
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
				if (client.state != Aerial.ClientState.PLAYING)
					return false;
				
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
