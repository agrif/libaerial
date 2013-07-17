namespace Airtunes
{
	// Vala version of JACK's ISO/POSIX C version of Paul Davis's lock
	// free ringbuffer C++ code, which assumes one read thread and one
	// write thread. This also operates on the assumption that size_t
	// reads/writes are atomic, which I'm told is a reasonable
	// assumption on modern systems.
	// http://jackit.sourceforge.net/cgi-bin/lxr/http/source/libjack/ringbuffer.c
	class RingBuffer
	{
		private uint8[] buf;
		private size_t write_head;
		private size_t read_head;
		private size_t size_mask;
		
		public RingBuffer(size_t sz)
		{
			uint power_of_two;
			for (power_of_two = 1; 1 << power_of_two < sz; power_of_two++);
			
			buf = new uint8[1 << power_of_two];
			size_mask = buf.length - 1;
			read_head = 0;
			write_head = 0;
		}
		
		// NOT THREAD SAFE
		public void reset()
		{
			read_head = 0;
			write_head = 0;
		}
		
		// bytes available for reading
		public size_t get_read_space()
		{
			var w = write_head;
			var r = read_head;
			
			if (w > r)
			{
				return w - r;
			} else {
				return (w - r + buf.length) & size_mask;
			}
		}
		
		// bytes available for writing
		public size_t get_write_space()
		{
			var w = write_head;
			var r = read_head;
			
			if (w > r)
			{
				return ((r - w + buf.length) & size_mask) - 1;
			} else if (w < r) {
				return (r - w) - 1;
			} else {
				return buf.length - 1;
			}
		}
		
		// advance read head
		public void advance_read_head(size_t amount)
		{
			read_head += amount;
			read_head &= size_mask;
		}
		
		// advance write head
		public void advance_write_head(size_t amount)
		{
			write_head += amount;
			write_head &= size_mask;
		}
		
		public size_t read(uint8[] dest)
		{
			var free_space = get_read_space();
			if (free_space == 0)
				return 0;
			
			var to_read = dest.length > free_space ? free_space : dest.length;
			var end_head = read_head + to_read;
			
			size_t first_length, second_length;
			if (end_head > buf.length)
			{
				first_length = buf.length - read_head;
				second_length = end_head & size_mask;
			} else {
				first_length = to_read;
				second_length = 0;
			}
			
			Memory.copy(dest, (uint8*)buf + read_head, first_length);
			advance_read_head(first_length);
			if (second_length > 0)
			{
				Memory.copy((uint8*)dest + first_length, (uint8*)buf + read_head, second_length);
				advance_read_head(second_length);
			}
			
			return to_read;
		}
		
		public size_t write(uint8[] src)
		{
			var free_space = get_write_space();
			if (free_space == 0)
				return 0;
			
			var to_write = src.length > free_space ? free_space : src.length;
			var end_head = write_head + to_write;
			
			size_t first_length, second_length;
			if (end_head > buf.length)
			{
				first_length = buf.length - write_head;
				second_length = end_head & size_mask;
			} else {
				first_length = to_write;
				second_length = 0;
			}
			
			Memory.copy((uint8*)buf + write_head, src, first_length);
			advance_write_head(first_length);
			if (second_length > 0)
			{
				Memory.copy((uint8*)buf + write_head, (uint8*)src + first_length, second_length);
				advance_write_head(second_length);
			}
			
			return to_write;
		}
	}
}
