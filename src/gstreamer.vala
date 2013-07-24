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

extern const string PACKAGE_BUGREPORT;

namespace Aerial
{

public class Sink : Gst.Audio.Sink
{
	private string LOGDOMAIN = "AerialSink";
	
	// we *should* resize these, but, that's a little bit out of the scope
	// of this sink!
	private int MAX_ART_SIZE = 200;
	
	public string host { get; set; default = "localhost"; }
	private Aerial.Client? client = null;
	
	private string? cur_artist = null;
	private string? cur_album = null;
	private string? cur_title = null;

	static construct
	{
		set_metadata("Aerial Airtunes Sink", "FIXME:General", "an audio sink for airtunes devices", PACKAGE_BUGREPORT);
		
		var caps = new Gst.Caps.empty_simple("audio/x-raw");
		caps.set_value("rate", 44100);
		caps.set_value("layout", "interleaved");
		caps.set_value("channels", 2);
		// TODO use native endianness (this breaks BE systems)
		caps.set_value("format", "S16LE");
		
		var sink = new Gst.PadTemplate("sink", Gst.PadDirection.SINK, Gst.PadPresence.ALWAYS, caps);
		add_pad_template(sink);
	}
	
	public override bool event(Gst.Event ev)
	{
		switch (ev.type)
		{
		case Gst.EventType.TAG:
			Gst.TagList tags;
			ev.parse_tag(out tags);
			
			string? artistp = null, albump = null, titlep = null;
			string artist, album, title;
			bool hasartist, hasalbum, hastitle;
			
			hasartist = tags.get_string(Gst.Tags.ALBUM_ARTIST, out artist);
			if (!hasartist)
				hasartist = tags.get_string(Gst.Tags.ARTIST, out artist);
			hasalbum = tags.get_string(Gst.Tags.ALBUM, out album);
			hastitle = tags.get_string(Gst.Tags.TITLE, out title);
			
			if (hasartist)
				artistp = artist;
			if (hasalbum)
				albump = album;
			if (hastitle)
				titlep = title;
			
			Gst.Sample image;
			bool has_image;
			Aerial.ImageType image_type = 0;
			uint8[] imagedata = {};
			has_image = tags.get_sample(Gst.Tags.IMAGE, out image);
			if (has_image)
			{
				var s = image.get_caps().get_structure(0);
				int width = 0, height = 0;
				if (!s.get_int("width", out width) || !s.get_int("height", out height))
				{
					has_image = false;
				} else {
					if (width > MAX_ART_SIZE || height > MAX_ART_SIZE)
						has_image = false;
				}
				
				switch (s.get_name())
				{
				case "image/jpeg":
					image_type = Aerial.ImageType.JPEG;
					break;
				case "image/png":
					image_type = Aerial.ImageType.PNG;
					break;
				default:
					has_image = false;
					break;
				}
				
				if (has_image)
				{
					var b = image.get_buffer();
					imagedata.resize((int)b.get_size());
					b.extract(0, imagedata, imagedata.length);
				}
			}
			
			if (artistp != cur_artist || titlep != cur_title || albump != cur_album)
			{
				// we'll be changing it in a moment, but for now...
				int64 pos = 0, len = 0;
				bool has_pos = true;
				has_pos = has_pos && query_position(Gst.Format.TIME, out pos);
				has_pos = has_pos && query_duration(Gst.Format.TIME, out len);
				
				client.set_metadata(titlep, artistp, albump);
				if (has_image)
					client.set_artwork(image_type, imagedata);
				if (has_pos)
				{
					// gstreamer speaks in nanoseconds
					float fpos = (float)pos / (1000.0f * 1000.0f * 1000.0f);
					float flen = (float)len / (1000.0f * 1000.0f * 1000.0f);
					client.set_progress(flen, fpos);
				}
				
				cur_artist = artistp;
				cur_title = titlep;
				cur_album = albump;
			}
			break;
		}
		
		return base.event(ev);
	}
	
	public override bool open()
	{
		client = new Aerial.Client();
		client.on_error.connect((c, e) =>
			{
				log(LOGDOMAIN, LogLevelFlags.LEVEL_ERROR, "aerial client error: %s", e.message);
			});
		client.notify["state"].connect((c, prop) =>
			{
				log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, "client changed to state %s", client.state.to_string());
			});
		
		try
		{
			log(LOGDOMAIN, LogLevelFlags.LEVEL_DEBUG, "connecting to %s", host);
			client.connect_to_host(host);
			client.play();
			client.set_volume(1.0f);
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
		try
		{
			client.disconnect_from_host();
			client = null;
			return true;
		} catch (Error e) {
			return false;
		}
	}
	
	public override int write(uint8[] data)
	{
		if (client.state != ClientState.PLAYING)
		{
			try
			{
				client.play();
			} catch (Error e) {
				return 0;
			}
		}
		return (int)client.write(data);
	}
	
	public override uint delay()
	{
		var v = client.get_queued_samples();
		return v;
	}
	
	public override void reset()
	{
		try
		{
			client.stop();
		} catch (Error e) {
		}
	}
}

public static bool plugin_init(Gst.Plugin plugin)
{
	return Gst.Element.register(plugin, "aerialsink", Gst.Rank.NONE, typeof(Sink));
}

}
