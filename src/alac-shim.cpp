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

#include "alac/ALACEncoder.h"
#include "alac/ALACDecoder.h"

#include <stdlib.h>

// 2 channels => 1. It just does. Sorry.
#define kTestFormatFlag_16BitSourceData 1

extern "C"
{
	int aerial_alac_encode(uint8_t* input, int input_length, uint8_t** output, int* output_length)
	{
		AudioFormatDescription inputFormat, outputFormat;
		
		// input format is pretty much dictated
		inputFormat.mFormatID = kALACFormatLinearPCM;
		inputFormat.mSampleRate = 44100; // 44100Hz
		inputFormat.mBitsPerChannel = 16; // 16-bit samples
		inputFormat.mFramesPerPacket = 1; // I guess 1 packet == 1 frame
		inputFormat.mChannelsPerFrame = 2; // stereo
		inputFormat.mBytesPerFrame = inputFormat.mChannelsPerFrame * inputFormat.mFramesPerPacket * (inputFormat.mBitsPerChannel / 8);
		inputFormat.mBytesPerPacket = inputFormat.mBytesPerFrame * inputFormat.mFramesPerPacket;
		inputFormat.mFormatFlags = kALACFormatFlagsNativeEndian | kALACFormatFlagIsSignedInteger; // expect signed native-endian data
		inputFormat.mReserved = 0;

		// and so is the output format
		outputFormat.mFormatID = kALACFormatAppleLossless;
		outputFormat.mSampleRate = inputFormat.mSampleRate;
		outputFormat.mFormatFlags = kTestFormatFlag_16BitSourceData;
		outputFormat.mFramesPerPacket = 352; // ewwwwwwwww but correct
		outputFormat.mChannelsPerFrame = inputFormat.mChannelsPerFrame;
		outputFormat.mBytesPerPacket = 0; // we're VBR
		outputFormat.mBytesPerFrame = 0; // same
		outputFormat.mBitsPerChannel = 0; // each bit doesn't really go with 1 sample
		outputFormat.mReserved = 0;

		// we need some buffers and sizes
		int32_t expectedInputSize = inputFormat.mBytesPerFrame * outputFormat.mFramesPerPacket;
		if (expectedInputSize != input_length)
			return 0;
		
		int32_t maxOutputSize = expectedInputSize + kALACMaxEscapeHeaderBytes;
		uint8_t* outputBuf = (uint8_t*)calloc(maxOutputSize, 1);
		
		// now we can start in earnest
		ALACEncoder* encoder = new ALACEncoder();
		encoder->SetFrameSize(outputFormat.mFramesPerPacket);
		encoder->InitializeEncoder(outputFormat);
		
		int32_t numBytes = expectedInputSize;
		encoder->Encode(inputFormat, inputFormat, input, outputBuf, &numBytes);
		if (output)
			*output = outputBuf;
		if (output_length)
			*output_length = numBytes;
		
		delete encoder;
		return 1;
	}
}
