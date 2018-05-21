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

#include <tag/tag.h>
#include <tag/fileref.h>
#include <tag/tfile.h>
#include <tag/tpropertymap.h>
#include <tag/mp4coverart.h>
#include <tag/mp4tag.h>
#include <tag/mp4file.h>


#include <FLAC++/metadata.h>
#include <FLAC++/encoder.h>

#include <cstring>
#include <vector>

#include "flac_utils.h"

// used as, for example,
// int r = signextend<signed int,5>(x);  // sign extend 5 bit number x to r

template <typename T, unsigned B>
inline T signextend(const T x)
{
    struct {T x:B;} s;
    return s.x = x;
}


// todo: templatize?  Don't like the replicated code.  Test performance vs.
// bitshifted implementation that doesn't require constant bit width too.
void signExtendBuffers(FLAC__int32** buf, size_t numFrames, size_t numChannels, unsigned bps) {

    
    switch (bps) {
        case 16:
            for (size_t i=0 ; i< numFrames; ++i) {
                for (size_t channel=0; channel<numChannels; ++channel) {
                    buf[channel][i] = signextend<FLAC__int32, 16>(buf[channel][i]);
                }
            }
            break;
        case 20:
            for (size_t i=0 ; i< numFrames; ++i) {
                for (size_t channel=0; channel<numChannels; ++channel) {
                    buf[channel][i] = signextend<FLAC__int32, 20>(buf[channel][i]);
                }
            }
            break;
        case 24:
            for (size_t i=0 ; i< numFrames; ++i) {
                for (size_t channel=0; channel<numChannels; ++channel) {
                    buf[channel][i] = signextend<FLAC__int32, 24>(buf[channel][i]);
                }
            }
            break;
        case 32:
            // nothing to do for 32
        default:
            break;
    }
}


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

void addVorbisCommentIfExists( FLAC__StreamMetadata		*block,
                              const TagLib::String      &key,
                              const TagLib::String      &value)
{
    //NSLog(@"Trying to add Vorbis Comment tag \"%s\" ==> \"%s\"", key.toCString(true), value.toCString(true));
    
    if ((!value.isEmpty()) && (!key.isEmpty()) ) {
        FLAC__StreamMetadata_VorbisComment_Entry	entry;
        FLAC__bool									result;
        //NSLog(@"Adding Vorbis Comment tag \"%s\" ==> \"%s\"", key.toCString(true), value.toCString(true));
        result=FLAC__metadata_object_vorbiscomment_entry_from_name_value_pair(&entry, key.toCString(true), value.toCString(true));
        NSCAssert1(YES == result, NSLocalizedStringFromTable(@"The call to %@ failed.", @"Exceptions", @""), @"FLAC__metadata_object_vorbiscomment_entry_from_name_value_pair");
        
        result = FLAC__metadata_object_vorbiscomment_append_comment(block, entry, NO);
        NSCAssert1(YES == result, NSLocalizedStringFromTable(@"The call to %@ failed.", @"Exceptions", @""), @"FLAC__metadata_object_vorbiscomment_append_comment");
    }
}


auto CopyArtFromMP4fileURL(const TagLib::FileRef& fr,
                           std::vector<FLAC__StreamMetadata *> &metadata) {
    TagLib::MP4::File* file = dynamic_cast<TagLib::MP4::File*>(fr.file());
    if (!file) {
        NSLog(@"tried to read mp4 coverart from a non mp4 file.");
        return metadata.size();
    }

    TagLib::MP4::CoverArtList cover_art_list = file->tag()->itemListMap()["covr"].toCoverArtList();
    FLAC__bool									result;
    
    if(!cover_art_list.isEmpty()) {
        
        TagLib::MP4::CoverArt cover_art = cover_art_list.front();
        
        const char *mime_type = 0;
        switch (cover_art.format()) {
            case TagLib::MP4::CoverArt::Format::PNG:
                mime_type = "image/png";
                break;
            case TagLib::MP4::CoverArt::Format::JPEG:
                mime_type = "image/jpeg";
                break;
            default:
                NSLog(@"%s, unsupported cover art format: %u size %u",
                      file->name(), cover_art.format(), cover_art.data().size());
                return metadata.size();
        }
        
        auto meta_pic = FLAC__metadata_object_new(FLAC__METADATA_TYPE_PICTURE);
        if (!meta_pic) {
            return metadata.size();
        }
        
        meta_pic->data.picture.type = FLAC__STREAM_METADATA_PICTURE_TYPE_FRONT_COVER;
        
        result = FLAC__metadata_object_picture_set_mime_type(meta_pic, const_cast<char *>(mime_type), YES);
        NSCAssert1(YES == result, NSLocalizedStringFromTable(@"The call to %@ failed.", @"Exceptions", @""), @"FLAC__metadata_object_picture_set_mime_type");
        
        result = FLAC__metadata_object_picture_set_data(meta_pic, (unsigned char *) cover_art.data().data(), cover_art.data().size()  , true);
        NSCAssert1(YES == result, NSLocalizedStringFromTable(@"The call to %@ failed.", @"Exceptions", @""), @"FLAC__metadata_object_picture_set_data");
        
        // As per docs at : https://wiki.xiph.org/VorbisComment#Cover_art
        // Image dimension fields
        // The height, width, colour depth and 'number of colours' fields are for purely informational purposes.
        // Applications MUST NOT use them for decoding purposes, but MAY display them to the user and MAY use them
        // to make a decision whether to skip the block (for example if selecting the most appropriate among multiple blocks).
        //
        // Applications writing picture blocks MUST set these fields correctly OR set them all to zero.
        meta_pic->data.picture.width = 0;
        meta_pic->data.picture.height = 0;
        meta_pic->data.picture.depth = 0;
        meta_pic->data.picture.colors = 0;
        const char *errorDescription = 0;
        
        result = FLAC__metadata_object_picture_is_legal(meta_pic, &errorDescription);
        if (!result) {
            // writing it anyway, but leave a msg
            NSLog(@"FLAC__metadata_object_picture_is_legal: %s",errorDescription);
        }
        metadata.push_back(meta_pic);
    }
    
 
    return metadata.size();
    
}

// Read the metadata from the mp4 (Apple Lossless) file, creating FLAC metadata objects and
// storing them in the metadata vector.  Return the number of metadata entries in the vector.
auto FlacMetadataFromMP4fileURL(const NSURL *mp4, std::vector<FLAC__StreamMetadata *> &metadata ){
    TagLib::FileRef f(mp4.fileSystemRepresentation, false);
    TagLib::Tag *t = f.tag();
    if (!t) {
        NSLog(@"Couldn't read tags from \"%s\".", mp4.fileSystemRepresentation);
        return metadata.size();
    }
    auto vorb = FLAC__metadata_object_new(FLAC__METADATA_TYPE_VORBIS_COMMENT);
    if (!vorb) {
        return metadata.size();
    }
    if (!f.file()) {
        NSLog(@"Couldn't read extended tags from \"%s\".", mp4.fileSystemRepresentation);
        return metadata.size();
    }
    
    // TODO FIX the below threw a bad access exception on mp4	NSURL *	@"file:///Volumes/AIRDISK/iTunes%20Lossless/iTunes%20Music/Music/Compilations/Anthology%20Of%20American%20Folk%20Music,%20Vol.%201B_%20%20Ballads/2-01%20Bandit%20Cole%20Younger.m4a"	0x00006080010b7ca0
    // memo to track it down - don't see how it could be happening given the checks above.
    // suspected multithread issue, since couldn't reliably recreate it when stepping through the code, but then
    // stopped seeing it without breakpoints even when running the same data set as first showed the issue.
    // Seems very odd to me.  I don't see how file can be nil, and properties is a class, not a pointer to a class.
    // and I've dug through a lot of the code under properties() and don't see where something in there could be hitting
    // it.
    auto props = f.file()->properties();
    //NSLog(@"Properties in Apple Lossless file %s", mp4.fileSystemRepresentation);
    for (auto p : props) {
        //NSLog(@"Property: \"%s\" (%u) => \"%s\"", p.first.toCString(true), p.second.size(), p.second.toString().toCString(true) );
        if (p.second.size() != 1) {
            NSLog(@"warning: expected one, but found %u values for tag \"%s\".", p.second.size(), p.first.toCString(true));
        }
        if (p.first == "TRACKNUMBER") {
            // taglib seems to format the property as t/n where t is the current track number and n is the number of tracks.
            // if this is the form, then split it up and set both TRACKNUMBER and TRACKTOTAL.  If we can't scan it in the
            // t/n form, then just set TRACKNUMBER to the value and hope for the best.
            unsigned track, total;
            int itemsRead = sscanf(p.second.front().toCString(), "%u/%u", &track, &total);
            if (itemsRead == 2) {
                addVorbisCommentIfExists(vorb, p.first, std::to_string(track) );
                addVorbisCommentIfExists(vorb, "TRACKTOTAL", std::to_string(total) );
            } else {
                addVorbisCommentIfExists(vorb, p.first, p.second.front() );
            }
        } else if (p.first == "DISCNUMBER") {
            // same thing as TRACKNUMBER above.
            unsigned disc, total;
            int itemsRead = sscanf(p.second.front().toCString(), "%u/%u", &disc, &total);
            if (itemsRead == 2) {
                addVorbisCommentIfExists(vorb, p.first, std::to_string(disc) );
                addVorbisCommentIfExists(vorb, "DISCTOTAL", std::to_string(total) );
            } else {
                addVorbisCommentIfExists(vorb, p.first, p.second.front() );
            }
        } else if (p.first == "COMMENT") {
            addVorbisCommentIfExists(vorb, "DESCRIPTION", p.second.front());
            addVorbisCommentIfExists(vorb, p.first, p.second.front() );
        } else {
            addVorbisCommentIfExists(vorb, p.first, p.second.front() );
        }
    }
#if 0
    auto unsupportedData = props.unsupportedData();
    for (auto s : unsupportedData) {
        NSLog(@"Unsupported data item: \"%s\"", s.toCString(true));
    }
#endif

    // done with Vorbis tag
    metadata.push_back(vorb);
    CopyArtFromMP4fileURL(f, metadata);
    return metadata.size();
}


// TODO: FIX: this is actually problematic. I have the AndPartialFiles part here because
// the encoding may throw an error for some reason or the user may cancel the operation
// mid encode.  However, I've seen that the FLAC library will potentially throw an exception
// in it's destructor if (I think) the file is deleted after init is called with the filename
// but before the encoder object is destroyed. Need to figure out how to delete any partial
// files, but not delete a destination file that was already there.  Had considered moving the
// delete to the caller of ConvertAlacToFlac and having it delete if the ConvertAlacToFlac
// function returns false, but that would try to delete an existing destination file in the
// event the conversion failed due to the file already existing, some permission error, etc.
// Perhaps those are empty cases, but seems overreaching to potentially try to delete something
// we didn't just create in the conversion step.  Needs more thought.
void cleanUpMetadataAndPartialFiles(std::vector<FLAC__StreamMetadata*>&metadata, const NSURL *f){
    // clean/free up the metadata
    for (auto entry : metadata) {
        FLAC__metadata_object_delete(entry);
    }
    NSError *e;
    if (![[NSFileManager defaultManager] removeItemAtURL:[f standardizedURL] error:&e]) {
        // check and report potential cleanup failure - note that if f is nil, the operation returns YES
        // TODO: see above
    }
}

// This function used to be specific for converting m4a Apple Lossless files to flac, but since it uses the
// Apple ExtAudion routines, it can theoritically work on other formats too if one wanted to, for some reason,
// convert a m4a AAC file for instance.  While ExtAudio could also handle non m4a contained files, there are
// assumptions made about the metadata being in a m4a container, specifically the album art.  The other metadata
// routines may be good to go with other file types, but I didn't look hard since album art would need to be
// handled first.
//
BOOL ConvertM4AToFlac(const NSURL* a, const NSURL *f, volatile const BOOL *cancelFlag){
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
    unsigned bps = 24; // todo: hack - trying to decode to 24 bit.  
    // if Apple lossless, then need to set the bps to what the source data bps was
    if (inFile_absd.mFormatID == kAudioFormatAppleLossless) {
        switch (inFile_absd.mFormatFlags) {
            case kAppleLosslessFormatFlag_16BitSourceData:
                bps=16;
                break;
            case kAppleLosslessFormatFlag_20BitSourceData:
                bps=20;
                break;
            case kAppleLosslessFormatFlag_24BitSourceData:
                bps=24;
                break;
            case kAppleLosslessFormatFlag_32BitSourceData:
                bps=32;
                NSLog(@"The FLAC reference encoder does not support 32 bits per sample source data.  If you are seeing this and really need support for it, contact me, and ideally, contact the FLAC folks too to get them to add it to their encoder.");
                return NO;
                break;
            default:
                NSLog(@"Unexpected bits per sample (format flag = %u) from source file %s", inFile_absd.mFormatFlags, a.fileSystemRepresentation );
                return NO;
        }
    }
    NSLog(@"m4a conversion: bits per sample = %u", bps);
    // Set up the desired processing format that ExtAudioFile routines will convert into
    // NOTE: upon testing, what actually happens with the below is that the signed int's bits are copied into the 32bit space without sign extension.  For example with a 16bit source,
    //       a 16bit signed int is bitwise placed without sign extension into the 32 bit field, so the top 16 bits will be 0 (it does seem the bits are at least cleared).
    //       So the not packed, low aligned, signed int part sort of works, but without sign extension, the flac encoder makes a file that sounds right (to a first listen) but is nearly 2x the size it should be
    AudioStreamBasicDescription decoded_absd = inFile_absd;
    decoded_absd.mFormatID = kAudioFormatLinearPCM;
    decoded_absd.mFormatFlags = kAudioFormatFlagIsSignedInteger  | kAudioFormatFlagIsNonInterleaved; // also implicitly not packed, low aligned by virtue of not setting the opposite flags
                                                                                                     // not sure about needed the below...
    decoded_absd.mBitsPerChannel = bps;

    decoded_absd.mBytesPerFrame = 4; // for int32... hopefully in conjunction with the format flags indicating non packed and low aligned, will give me a int32 containing the low aligned 16 bit sample in the case of 16 bit alac
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


    // encode the samples
    bool readCompleted = false;
    while (!*cancelFlag) {
        UInt32 numFrames = numFramesToReadPerLoop;
        result=ExtAudioFileRead(inFile, &numFrames, decBuffers.get());
        if (result != noErr) {
            NSLog(@"error reading from %s during conversion to flac: %@ (%i)", a.fileSystemRepresentation,
                  UTCreateStringForOSType(result), result);
            break;
        }
        if (*cancelFlag) break;


        if (numFrames) {
            // sign extend nonsense to satisfy the disconnect between the apple returns and the flac expectations
            signExtendBuffers(inBuffsForFlacEncoder, numFrames, inFile_absd.mChannelsPerFrame, bps);

            //NSLog(@"sample samples, channel 0,1 = %i, %i", inBuffsForFlacEncoder[0][0], inBuffsForFlacEncoder[1][0]);
            if (! encoder.process(inBuffsForFlacEncoder, numFrames)) {
                NSLog(@"flac encoding failed, %s", encoder.get_state().resolved_as_cstring(encoder));
                break;
            }
        } else {
            // we're done
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

#if 0
BOOL ConvertAlacToFlac(const NSURL* a, const NSURL *f, volatile const BOOL *cancelFlag){
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
        case kAppleLosslessFormatFlag_20BitSourceData:
            bps=20;
            break;
        case kAppleLosslessFormatFlag_24BitSourceData:
            bps=24;
            break;
        case kAppleLosslessFormatFlag_32BitSourceData:
            bps=32;
            NSLog(@"The FLAC reference encoder does not support 32 bits per sample source data.  If you are seeing this and really need support for it, contact me, and ideally, contact the FLAC folks too to get them to add it to their encoder.");
            return NO;
            break;
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

    decoded_absd.mBytesPerFrame = 4; // for int32... hopefully in conjunction with the format flags indicating non packed and low aligned, will give me a int32 containing the low aligned 16 bit sample in the case of 16 bit alac
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


    // encode the samples
    bool readCompleted = false;
    while (!*cancelFlag) {
        UInt32 numFrames = numFramesToReadPerLoop;
        result=ExtAudioFileRead(inFile, &numFrames, decBuffers.get());
        if (result != noErr) {
            NSLog(@"error reading from %s during conversion to flac: %@ (%i)", a.fileSystemRepresentation,
                  UTCreateStringForOSType(result), result);
            break;
        }
        if (*cancelFlag) break;


        if (numFrames) {
            // sign extend nonsense to satisfy the disconnect between the apple returns and the flac expectations
            signExtendBuffers(inBuffsForFlacEncoder, numFrames, inFile_absd.mChannelsPerFrame, bps);

            //NSLog(@"sample samples, channel 0,1 = %i, %i", inBuffsForFlacEncoder[0][0], inBuffsForFlacEncoder[1][0]);
            if (! encoder.process(inBuffsForFlacEncoder, numFrames)) {
                NSLog(@"flac encoding failed, %s", encoder.get_state().resolved_as_cstring(encoder));
                break;
            }
        } else {
            // we're done
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
#endif


