namespace Airtunes
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
