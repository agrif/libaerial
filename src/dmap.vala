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

struct DMAP
{
	public MemoryOutputStream ostream;
    public DataOutputStream odat;
	public unowned SList<int64?> containers;
	
	public void init()
	{
		ostream = new MemoryOutputStream(null, realloc, free);
		odat = new DataOutputStream(ostream);
		containers = null;
	}
	
	public void start_container(string chunk) throws Error
	{
		return_if_fail(chunk.length == 4);
		odat.put_string(chunk);
		odat.put_uint32(0);
		containers.prepend(ostream.tell());
	}

	public void end_container() throws Error
	{
		return_if_fail(containers != null);
		
		var end = ostream.tell();
		var start = containers.data;
		containers.remove_link(containers);
		
		ostream.seek(start - 4, SeekType.SET);
		odat.put_uint32((uint32)(end - start));
		ostream.seek(end, SeekType.SET);
	}
	
	public void put_string(string chunk, string data) throws IOError
	{
		return_if_fail(chunk.length == 4);
		odat.put_string(chunk);
		odat.put_uint32(data.length);
		odat.put_string(data);
	}
	
	public void close() throws IOError
	{
		odat.close();
	}
	
	public uint8[] steal_data()
	{
		var dat = ostream.steal_data();
		dat.length = (int)ostream.get_data_size();
		return dat;
	}
}

}
