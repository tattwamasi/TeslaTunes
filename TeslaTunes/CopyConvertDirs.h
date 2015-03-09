//
//  CopyConvertDirs.h
//  TeslaTunes
//
//  Created by Rob Arnold on 3/7/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import <Foundation/Foundation.h>



typedef NS_ENUM(NSUInteger, DirOperation) {
    CCScan=0,
    CCProcessWhileScanning=1,
    CCProcessScanned=2,
};


@interface FileOp : NSObject{
    @public
    NSURL *sourceURL;
    NSURL *destinationURL;
}
@end


@interface CopyConvertDirs : NSObject
@property (readonly) NSCountedSet *skippedExtensions;
@property (readonly) NSCountedSet *copiedExtensions;
@property (readonly) unsigned filesChecked;
@property (readonly) unsigned filesToCopyConvert;
@property (readonly) unsigned filesCopyConverted;
@property (readonly) BOOL isProcessing;
@property (readonly) BOOL scanReady;
- (CopyConvertDirs*) init;

// Uses NSOperationQueue and NSOperation to concurrently run.  TODO: delegate or something to indicate when finished,etc.
- (void) startOperationOnDir: (DirOperation) opType withSourceDir: (const NSURL *)src andDestDir: (const NSURL *)dst;
- (void) cancelOngoingOperations;

@end
