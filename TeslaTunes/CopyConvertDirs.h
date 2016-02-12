//
//  CopyConvertDirs.h
//  TeslaTunes
//
//  Created by Rob Arnold on 3/7/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import <Foundation/Foundation.h>

#include "PlaylistSelections.h"




typedef NS_ENUM(NSUInteger, DirOperation) {
    CCScan=0,
    CCProcessWhileScanning=1,
    CCProcessScanned=2,
};


@interface FileOp : NSObject{
    @public
    const NSURL *sourceURL;
    const NSURL *destinationURL;
    const NSString *playlist; // if file is a member of a playlist, the playlist name (nil otherwise)
}
@end


@interface CopyConvertDirs : NSObject
@property (readonly) NSCountedSet *skippedExtensions;
@property (readonly) NSCountedSet *copiedExtensions;
@property (readonly) unsigned filesChecked;
@property (readonly) unsigned filesToCopyConvert;
@property (readonly) unsigned filesCopyConverted;
@property (readonly) unsigned filesMarkedForOrDeleted;
@property (readonly) BOOL isProcessing;
@property (readonly) BOOL scanReady;

// Option for working around "album fragmentation"
@property BOOL remapAlbumArtistToArtistAndTitle;
// Options for playlist manipulation
@property BOOL hackGenre; // set genre tag to playlist name
@property BOOL stripTagsForPlaylists; // strip all tags from playlist items (except genre, if hackGenre is set) in order
                                      // to not clutter the album/song/artist play modes with duplicates

// Remap disc number into the track number similar to (but different than) Doug's Applescript,
// "Embed Disc Number in Track Number v1.0"
// if disc number > 1 then New track number = disc number*100 + old track number
@property BOOL embedDiscNumberInTrackNumber;

- (CopyConvertDirs*) init;

// Uses NSOperationQueue and NSOperation to concurrently run.  TODO: delegate or something to indicate when finished,etc.
- (void) startOperationOnDir: (DirOperation) opType
      withPlaylistSelections: (const PlaylistSelections*) playlistSelections
                andSourceDir: (const NSURL *)src toDestDir: (const NSURL *)dst;
- (void) cancelOngoingOperations;

@end
