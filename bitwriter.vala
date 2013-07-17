// interface for writing a bitstream
// shamelessly stolen from
// http://git.zx2c4.com/pulseaudio-raop2/tree/src/modules/raop/raop_client.c

namespace Airtunes
{

[Compact]
class BitWriter
{
	public uint8[] buffer;
	public uint byte_pos;
	public uint8 bit_pos;
	public uint size;
	
	public BitWriter(uint bufsize)
	{
		buffer = {};
		buffer.resize((int)bufsize);
		Posix.memset(buffer, 0, bufsize);
		byte_pos = 0;
		bit_pos = 0;
		size = 0;
	}
	
	public void write(int data, uint8 data_bit_len)
	{
		if (data_bit_len == 0)
			return;
		
		// if bit pos is zero, we will definitely use at least one bit from
		// the current byte
		if (bit_pos == 0)
			size++;
		
		// the number of bits left in the current byte of the buffer
		int bits_left = 8 - bit_pos;
		// the number of overflow bits
		int bit_overflow = bits_left - data_bit_len;
		
		if (bit_overflow >= 0)
		{
			// we can fit the new data in the current byte
			// as we write MSB->LSB we need to left shift by the overflow
			uint8 bit_data = (uint8)(data << bit_overflow);
			if (bit_pos > 0)
				buffer[byte_pos] |= bit_data;
			else
				buffer[byte_pos] = bit_data;
			
			// if our data fits exactly into this byte, we need to move forward
			if (bit_overflow == 0)
			{
				// size will be incremented on the next call
				byte_pos++;
				bit_pos = 0;
			} else {
				bit_pos += data_bit_len;
			}
		} else {
			// bit overflow is negative, therefore we need a new byte
			// but first fill up what's left of this byte
			uint8 bit_data = (uint8)(data >> -bit_overflow);
			buffer[byte_pos] |= bit_data;
			
			// increment our byte counter, size counter
			byte_pos++;
			size++;
			
			// write the next byte
			buffer[byte_pos] = (uint8)(data << (8 + bit_overflow));
			bit_pos = (uint8)(-bit_overflow);
		}
	}
	
	public uint8[] finalize()
	{
		buffer.length = (int)size;
		return buffer;
	}
}

}
