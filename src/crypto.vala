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
	public uint8[] aes_encrypt(uint8[] key, uint8[] iv, uint8[] data)
	{
		return_if_fail(iv.length == Nettle.AES_BLOCK_SIZE);
		
		// nettle overrites the iv, so make a copy
		uint8[] iv_copy = {};
		iv_copy.resize(iv.length);
		Posix.memcpy(iv_copy, iv, iv.length);
		
		var encrypt_part = data.length / Nettle.AES_BLOCK_SIZE;
		encrypt_part *= Nettle.AES_BLOCK_SIZE;
		
		var aes = Nettle.AES();
		aes.set_encrypt_key(key.length, key);
		uint8[] result = {};
		result.resize(data.length);

		Nettle.cbc_encrypt(&aes, aes.encrypt, Nettle.AES_BLOCK_SIZE, iv_copy, encrypt_part, result, data);
		
		if (encrypt_part != data.length)
			Posix.memcpy(&result[encrypt_part], &data[encrypt_part], data.length - encrypt_part);
		
		return result;
	}
}
