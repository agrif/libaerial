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

namespace Aerial
{
	public uint8[] random_bytes(size_t count)
	{
		uint8[] buffer = {};
		buffer.resize((int)count);
		for (var i = 0; i < count; i++)
			buffer[i] = (uint8)Random.next_int();
		return buffer;
	}
	
	public string bytes_to_hex(uint8[] buffer)
	{
		string ret = "";
		for (var i = 0; i < buffer.length; i++)
		{
			ret += "%02x".printf(buffer[i]);
		}
		return ret;
	}
	
	public string bytes_to_base64(uint8[] buffer)
	{
		// strange base64 used in airtunes, no padding!
		return Base64.encode(buffer).replace("=", "");
	}
}
