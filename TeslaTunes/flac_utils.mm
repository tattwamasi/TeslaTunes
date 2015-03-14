//
//  flac_utils.m
//  TeslaTunesCL
//
//  Created by Rob Arnold on 2/5/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//
#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>


#include <mp4v2/mp4v2.h>
#include <FLAC++/metadata.h>
#include <FLAC++/encoder.h>

#include <cstring>
#include <vector>

#include "flac_utils.h"


class FlacEncoderFromAlac: public FLAC::Encoder::File {
public:
    FlacEncoderFromAlac(): FLAC::Encoder::File() {}
protected:
    //virtual void progress_callback(FLAC__uint64 bytes_written, FLAC__uint64 samples_written, unsigned frames_written, unsigned total_frames_estimate);
};

#if 0
void FlacEncoderFromAlac::progress_callback(FLAC__uint64 bytes_written, FLAC__uint64 samples_written, unsigned frames_written, unsigned total_frames_estimate)
{
    //fprintf(stderr, "wrote %llu bytes, %llu samples, %u/%u frames\n", bytes_written, samples_written, frames_written, total_frames_estimate);
}

#endif

// adapted from sbooth's Max UtilityFunctions.m
void addVorbisCommentIfExists( FLAC__StreamMetadata		*block,
                              const char				*key,
                              const char 				*value)
{
    if (value && key) {
        FLAC__StreamMetadata_VorbisComment_Entry	entry;
        FLAC__bool									result;
        
        result			= FLAC__metadata_object_vorbiscomment_entry_from_name_value_pair(&entry, key, value);
        NSCAssert1(YES == result, NSLocalizedStringFromTable(@"The call to %@ failed.", @"Exceptions", @""), @"FLAC__metadata_object_vorbiscomment_entry_from_name_value_pair");
        
        result = FLAC__metadata_object_vorbiscomment_append_comment(block, entry, NO);
        NSCAssert1(YES == result, NSLocalizedStringFromTable(@"The call to %@ failed.", @"Exceptions", @""), @"FLAC__metadata_object_vorbiscomment_append_comment");
    }
}


FLAC__StreamMetadata *MakeFlacImgTag(NSImage *img) {
    FLAC__StreamMetadata *block = FLAC__metadata_object_new(FLAC__METADATA_TYPE_PICTURE);
    if (block) {
        NSEnumerator		*enumerator					= nil;
        NSImageRep			*currentRepresentation		= nil;
        NSBitmapImageRep	*bitmapRep					= nil;
        NSData				*imageData					= nil;
        const char			*errorDescription;
        NSSize				size;
        
        // from sbooth's max - todo: is this actually going to go through multiple loops?  If so and if found, why not break early?
        enumerator = [[img representations] objectEnumerator];
        while((currentRepresentation = [enumerator nextObject])) {
            if([currentRepresentation isKindOfClass:[NSBitmapImageRep class]]) {
                bitmapRep = (NSBitmapImageRep *)currentRepresentation;
            }
        }
        
        // Create a bitmap representation if one doesn't exist
        if(nil == bitmapRep) {
            size = [img size];
            [img lockFocus];
            bitmapRep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0, 0, size.width, size.height)];
            [img unlockFocus];
        }
        
        imageData	= [bitmapRep representationUsingType:NSPNGFileType properties:nil];
        
        // Add the image data to the metadata block
        block->data.picture.type		= FLAC__STREAM_METADATA_PICTURE_TYPE_FRONT_COVER;
        
        FLAC__bool result = FLAC__metadata_object_picture_set_mime_type(block, const_cast<char*>("image/png"), YES);
        assert(result == YES);
        result = FLAC__metadata_object_picture_set_data(block, reinterpret_cast<FLAC__byte*>(const_cast<void*>([imageData bytes]))  , static_cast<FLAC__uint32>([imageData  length]), YES);
        assert(result == YES);
        
        block->data.picture.width		= [bitmapRep size].width;
        block->data.picture.height		= [bitmapRep size].height;
        block->data.picture.depth		= static_cast<FLAC__uint32>([bitmapRep bitsPerPixel]);
        
        result = FLAC__metadata_object_picture_is_legal(block, &errorDescription);
        if (!result) {
            NSLog(@"Flac metadata picture tag error %s", errorDescription);
        }
    }
    return block;
}


auto FlacMetadataFromMP4fileURL(NSURL *mp4, std::vector<FLAC__StreamMetadata *> &metadata ){
    // read the metadata from alac file a
    auto mp4FileHandle	= MP4Read(mp4.fileSystemRepresentation);
    
    if(MP4_INVALID_FILE_HANDLE == mp4FileHandle) {
        return metadata.size();
    }
    
    // Read the tags
    auto tags = MP4TagsAlloc();
    if (NULL == tags) {
        MP4Close(mp4FileHandle);
        return metadata.size();
    }
    MP4TagsFetch(tags, mp4FileHandle);
    
    // we should be able to create all the flac metadata now. It'll be
    // 1) the Vorbis comment
    // 2) any artwork tags
    auto vorb = FLAC__metadata_object_new(FLAC__METADATA_TYPE_VORBIS_COMMENT);
    if (!vorb) {
        return metadata.size();
    }
    // Album title
    addVorbisCommentIfExists(vorb, "ALBUM", tags->album);
    // Artist -- TODO:  should album artist really override artist?? Seems odd - think I'm conforming to the way sbooth's Max does it.  Investigate.
    if(tags->albumArtist)
        addVorbisCommentIfExists(vorb, "ARTIST", tags->albumArtist);
    else if(tags->artist)
        addVorbisCommentIfExists(vorb, "ARTIST",tags->artist);
    
    // Genre  -- TODO:  should we look at the genreType instead and translate?
    addVorbisCommentIfExists(vorb, "GENRE", tags->genre);
    
    // Year
    addVorbisCommentIfExists(vorb, "DATE", tags->releaseDate);
    
    // Composer
    addVorbisCommentIfExists(vorb, "COMPOSER", tags->composer);
    
    // Comment
    addVorbisCommentIfExists(vorb, "DESCRIPTION", tags->comments);

    // Track title
    addVorbisCommentIfExists(vorb, "TITLE", tags->name);
    
    // Track number
    if(tags->track) {
        if(tags->track->index)
            addVorbisCommentIfExists(vorb, "TRACKNUMBER", [NSNumber numberWithUnsignedShort:tags->track->index].stringValue.UTF8String);
        if(tags->track->total)
            addVorbisCommentIfExists(vorb, "TRACKTOTAL", [NSNumber numberWithUnsignedShort:tags->track->total].stringValue.UTF8String);
    }
    // Compilation
    if(tags->compilation)
        addVorbisCommentIfExists(vorb, "COMPILATION", [NSNumber numberWithBool:*(tags->compilation)].stringValue.UTF8String);
    
    
    // Disc number
    if(tags->disk) {
        if(tags->disk->index)
            addVorbisCommentIfExists(vorb, "DISKNUMBER", [NSNumber numberWithUnsignedShort:tags->disk->index].stringValue.UTF8String);
        if(tags->disk->total)
            addVorbisCommentIfExists(vorb, "DISKTOTAL", [NSNumber numberWithUnsignedShort:tags->disk->total].stringValue.UTF8String);
    }

    // Other tags to potentially add:  ISRC, MCN, ENCODER, ENCODING
    
    // done with Vorbis tag
    metadata.push_back(vorb);
    
    
    // Album art
    // Both mp4 and flac can contain multiple artwork tags in the file, but assume the first one is the front cover art and
    // just copy the rest as other
    for(int i = 0; i< tags->artworkCount; ++i) {
        MP4TagArtwork artwork = (tags->artwork)[i];
        NSData *artworkData = [NSData dataWithBytes:artwork.data length:artwork.size];
        NSImage *image = [[NSImage alloc] initWithData:artworkData] ;
        
        FLAC__StreamMetadata *fimg = MakeFlacImgTag(image);
        if (fimg) {
            if (i>0) {
                // change the artwork type - only set first as cover
                fimg->data.picture.type		= FLAC__STREAM_METADATA_PICTURE_TYPE_OTHER;
            }
            metadata.push_back(fimg);
        }
    } // end for
    
    MP4TagsFree(tags);
    MP4Close(mp4FileHandle);

    
    return metadata.size();
}

void cleanUpMetadataAndPartialFiles(std::vector<FLAC__StreamMetadata*>&metadata, NSURL *f){
    // clean/free up the metadata
    for (auto entry : metadata) {
        FLAC__metadata_object_delete(entry);
    }
    NSError *e;
    if (![[NSFileManager defaultManager] removeItemAtURL:f error:&e]) {
        // check and report potential cleanup failure - note that if f is nil, the operation returns YES
        // TODO: see above
    }
}

BOOL ConvertAlacToFlac(NSURL* a, NSURL *f, volatile const BOOL *cancelFlag){
    BOOL placeholderCancelFlag=NO;
    if (cancelFlag==nullptr) {
        cancelFlag=&placeholderCancelFlag;
    }
    
    FlacEncoderFromAlac encoder;
    ExtAudioFileRef inFile=nullptr;
    
    OSStatus result = ExtAudioFileOpenURL( (__bridge CFURLRef)a, &inFile);
    if (result != noErr) {
        NSLog(@"Failed to open input file %s for conversion to flac. (err %i, %@)", a.fileSystemRepresentation, result, UTCreateStringForOSType(result));
        return NO;
    }
    if (*cancelFlag) return NO;
    assert(inFile != nullptr);
    // give management of the open file to the unique_ptr so it'll get closed when scope ends, regardless of where/why the scope ends
    // TODO: understand the unique_ptr template instantiation - tried decltype(*inFile) but didn't work.  Not sure I really understant why the * is needed after the deleter type either.
    std::unique_ptr<OpaqueExtAudioFile, decltype(ExtAudioFileDispose)*> extFileManager {inFile, ExtAudioFileDispose};
    
    UInt32 dataSize = sizeof(AudioStreamBasicDescription);
    AudioStreamBasicDescription inFile_absd;
    result = ExtAudioFileGetProperty(inFile, kExtAudioFileProperty_FileDataFormat, &dataSize, &inFile_absd);
    if (noErr != result) {
        NSLog(@"Failed to read properties of input file %s (err %i, %@).", a.fileSystemRepresentation, result, UTCreateStringForOSType(result));
        return NO;
    }
    if (*cancelFlag) return NO;
    
    SInt64 totalFrames;
    dataSize=sizeof(totalFrames);
    result = ExtAudioFileGetProperty(inFile, kExtAudioFileProperty_FileLengthFrames, &dataSize, &totalFrames);
    if (noErr != result) {
        NSLog(@"Failed to read properties of input file %s (err %i, %@).", a.fileSystemRepresentation, result, UTCreateStringForOSType(result));
        return NO;
    }
    if (*cancelFlag) return NO;
    assert(inFile_absd.mFormatID == kAudioFormatAppleLossless);
    unsigned bps;
    switch (inFile_absd.mFormatFlags) {
        case kAppleLosslessFormatFlag_16BitSourceData:
            bps=16;
             break;
        // for now, we aren't going to support non 16 bit sources. due to the sign extending issue with the buffers - will investigate fix later
        case kAppleLosslessFormatFlag_24BitSourceData:
            bps=24;
            //break;
        case kAppleLosslessFormatFlag_32BitSourceData:
            bps=32;
            //break;
        default:
            NSLog(@"Unexpected bits per sample (format flag = %u) from source file %s", inFile_absd.mFormatFlags, a.fileSystemRepresentation );
            return NO;
    }
    
    
    // Set up the desired processing format that ExtAudioFile routines will convert into
    // NOTE: upon testing, what actually happens with the below is that the signed int's bits are copied into the 32bit space without sign extension.  For example with a 16bit source,
    //       a 16bit signed int is bitwise placed without sign extension into the 32 bit field, so the top 16 bits will be 0 (it does seem the bits are at least cleared).
    //       So the not packed, low aligned, signed int part sort of works, but without sign extension, the flac encoder makes a file that sounds right (to a first listen) but is nearly 2x the size it should be
    AudioStreamBasicDescription decoded_absd = inFile_absd;
    decoded_absd.mFormatID = kAudioFormatLinearPCM;
    decoded_absd.mFormatFlags = kAudioFormatFlagIsSignedInteger  | kAudioFormatFlagIsNonInterleaved; // also implicitly not packed, low aligned by virtue of not setting the opposite flags
    // not sure about needed the below...
    decoded_absd.mBitsPerChannel = bps;
    
    decoded_absd.mBytesPerFrame = 4; // for int32... hopefully in conjunction with the format flags indicating non packed and low aligned, will give me a int32 containing the low aligned 16 bit sample in the cast of 16 bit alac
    decoded_absd.mFramesPerPacket=1;
    decoded_absd.mBytesPerPacket = decoded_absd.mBytesPerFrame * decoded_absd.mFramesPerPacket;
    

    if (*cancelFlag) return NO;
    
    result = ExtAudioFileSetProperty(inFile, kExtAudioFileProperty_ClientDataFormat, sizeof(decoded_absd), &decoded_absd);
    if (noErr != result) {
        NSLog(@"Failed to set decode properties of input file %s (err %i, %@).", a.fileSystemRepresentation, result, UTCreateStringForOSType(result));
        return NO;
    }
    
    
    // set up the buffers for decoded audio from the alac file
    // Note there is some pointer aliasing going on here because the encoder and decoder both want to look at the buffers through different structures, and because I want to
    // guarantee proper memory cleanup when we leave this scope, thus the std::unique_ptr's to hold buffers (for automated cleanup) and the inBuffsForFlacEncoder pointing into the AudioBuffers data fields
    //std::unique_ptr<AudioBufferList, decltype(free)*> decBuffers{static_cast<AudioBufferList*>(malloc(sizeof(AudioBufferList)-sizeof(AudioBuffer)+decoded_absd.mChannelsPerFrame*sizeof(AudioBuffer))),
    //                                                             free};
    
    std::unique_ptr<AudioBufferList, decltype(free)*> decBuffers{static_cast<AudioBufferList*>(malloc(offsetof(AudioBufferList, mBuffers)+sizeof(AudioBuffer)*decoded_absd.mChannelsPerFrame)), free};
    decBuffers->mNumberBuffers = decoded_absd.mChannelsPerFrame;

    std::vector<std::unique_ptr<Byte[]>> decoderBufferManager;  // keep track of dynamically allocated buffers so we can properly deallocate
    decoderBufferManager.reserve(decBuffers->mNumberBuffers);

    // make a flac compatible buffer array alias for these buffers
    FLAC__int32* inBuffsForFlacEncoder[decBuffers->mNumberBuffers];

    unsigned numFramesToReadPerLoop = decoded_absd.mSampleRate; // let's read 1 seconds worth at a time.
    unsigned bufSizeinBytes = numFramesToReadPerLoop * decoded_absd.mBytesPerFrame;

    
    
    for(int i = 0; i < decBuffers->mNumberBuffers; ++i) {
        decBuffers->mBuffers[i].mNumberChannels = 1;
        decoderBufferManager.push_back(std::unique_ptr<Byte[]>(new Byte[bufSizeinBytes] ));
        decBuffers->mBuffers[i].mData =  decoderBufferManager[i].get();
        decBuffers->mBuffers[i].mDataByteSize = bufSizeinBytes;
        inBuffsForFlacEncoder[i] = static_cast<FLAC__int32*>(decBuffers->mBuffers[i].mData);
    }
    
    // create flac metadata from the metadata in the mp4 file container
    std::vector<FLAC__StreamMetadata*> metadata;
    auto metadata_entry_count = FlacMetadataFromMP4fileURL(a, metadata );
    assert(metadata_entry_count >0);
    // create a seektable for seeking through stream at a regular interval
    FLAC__StreamMetadata *seektable = FLAC__metadata_object_new(FLAC__METADATA_TYPE_SEEKTABLE);
    assert(seektable);
    // Append seekpoints (one every 5 seconds)
    FLAC__bool flacResult = FLAC__metadata_object_seektable_template_append_spaced_points_by_samples(seektable, 5 * inFile_absd.mSampleRate, totalFrames);
    assert(flacResult);
    // Sort the table
    result = FLAC__metadata_object_seektable_template_sort(seektable, NO);
    assert(result);
    metadata.push_back(seektable);

    FLAC__StreamMetadata   *padding = FLAC__metadata_object_new(FLAC__METADATA_TYPE_PADDING);
    if (padding) {
        padding->length=8192; // ?? needed ??  Don't really think the padding chunk is needed at all
        metadata.push_back(padding);
    }

    // write out the metadata
    encoder.set_metadata(metadata.data(), static_cast<unsigned>(metadata.size()) );
    
    // set up the encoder, but don't actually start encoding samples
    encoder.set_channels(inFile_absd.mChannelsPerFrame);
    encoder.set_bits_per_sample(bps);
    encoder.set_sample_rate(inFile_absd.mSampleRate);
    encoder.set_total_samples_estimate(totalFrames);

    // Encoder parameters
    encoder.set_compression_level(5);
    encoder.set_do_mid_side_stereo(true); // default false
    encoder.set_max_lpc_order(8); // default 0
    
    //encoder.set_apodization("tukey(0.5)");
    //encoder.set_loose_mid_side_stereo(false);
    //encoder.set_qlp_coeff_precision(0);
    //encoder.set_do_qlp_coeff_prec_search(false);
    //encoder.set_do_exhaustive_model_search(false);
    //encoder.set_min_residual_partition_order(0);
    encoder.set_max_residual_partition_order(4);
    

    
    // initialize the encoder TODO:  after this point, there's potentially a partial flac file left on the system - need to add cleanup of it on error.
    FLAC__StreamEncoderInitStatus status = encoder.init(f.fileSystemRepresentation);
    if (status != FLAC__STREAM_ENCODER_INIT_STATUS_OK) {
        NSLog(@"flac encoding failed, %s", encoder.get_state().resolved_as_cstring(encoder));
        cleanUpMetadataAndPartialFiles(metadata, f);
        return NO;
    }

    if (*cancelFlag) {cleanUpMetadataAndPartialFiles(metadata, f); return NO;}
    

    FLAC__int32 min=0;
    FLAC__int32 max=0;
    // encode the samples
    bool readCompleted = false;
    while (!*cancelFlag) {
        UInt32 numFrames = numFramesToReadPerLoop;
        result=ExtAudioFileRead(inFile, &numFrames, decBuffers.get());
        if (*cancelFlag) break;
        FLAC__int32 sample;
        for (size_t i=0 ; i< numFrames; ++i) {
            sample = (int16_t)inBuffsForFlacEncoder[0][i];
            if (sample < min) min=sample;
            if (sample > max) max=sample;
            inBuffsForFlacEncoder[0][i] = sample;
            
            sample = (int16_t)inBuffsForFlacEncoder[1][i];
            if (sample < min) min=sample;
            if (sample > max) max=sample;
            inBuffsForFlacEncoder[1][i] = sample;
            
        }
        
        if (numFrames) {
            //NSLog(@"sample samples, channel 0,1 = %i, %i", inBuffsForFlacEncoder[0][0], inBuffsForFlacEncoder[1][0]);
            if (! encoder.process(inBuffsForFlacEncoder, numFrames)) {
                NSLog(@"flac encoding failed, %s", encoder.get_state().resolved_as_cstring(encoder));
                break;
            }
        } else {
            // we're done
            NSLog(@"%s: min sample: %i, max sample: %i", a.fileSystemRepresentation, min, max);
            readCompleted=true;
            break;
        }
    }
    
    
    // finish the encode
    result = encoder.finish();
    if (!result) {
        NSLog(@"flac encoding failed while finishing up, %s", encoder.get_state().resolved_as_cstring(encoder));
    }
    cleanUpMetadataAndPartialFiles(metadata, (result && readCompleted)?nil:f);
    return result && readCompleted;
}

