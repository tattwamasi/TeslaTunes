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
    const NSString *genre;
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

@property BOOL hackGenre;

- (CopyConvertDirs*) init;

// Uses NSOperationQueue and NSOperation to concurrently run.  TODO: delegate or something to indicate when finished,etc.
- (void) startOperationOnDir: (DirOperation) opType
      withPlaylistSelections: (const PlaylistSelections*) playlistSelections
                andSourceDir: (const NSURL *)src toDestDir: (const NSURL *)dst;
- (void) cancelOngoingOperations;

@end
