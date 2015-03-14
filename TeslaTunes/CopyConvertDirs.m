//
//  CopyConvertDirs.m
//  TeslaTunes
//
//  Created by Rob Arnold on 3/7/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import "CopyConvertDirs.h"

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>


#include "flac_utils.h"

// make the destination filename out of the base path of destination and the relative path of the new item
NSURL* makeDestURL(const NSURL *dstBasePath, const NSURL *basePathToStrip, const NSURL* srcURL) {
    // Need to create the destination file/dir URL to check it's existance.  Use dst and the relative path
    // perhaps via + (NSURL *)fileURLWithPathComponents:(NSArray *)components with and array concat/splice
    // from dst components + relatice slice of src components
    
    
    // May well be a better way.  Till then...
    NSArray *basePathComponents = [basePathToStrip pathComponents];
    NSArray *srcPathComponents = [srcURL pathComponents];
    NSRange relPathRange;
    relPathRange.location = basePathComponents.count; // start the relative path at the end of the base path
    relPathRange.length = srcPathComponents.count - basePathComponents.count;
    
    
    NSURL *dstURL = [NSURL fileURLWithPathComponents:[[dstBasePath pathComponents] arrayByAddingObjectsFromArray:[srcPathComponents subarrayWithRange:relPathRange]]];
    
    return dstURL;
}


//AVURLAsset *asset = [[[AVURLAsset alloc] initWithURL:sourceURL options:nil] autorelease];

BOOL isAppleLosslessFile(NSURL *fileURL){
    if ([[fileURL.pathExtension lowercaseString] isEqualToString:@"m4a"]) {
        NSError *e;
        AVAudioFile *aFile = [[AVAudioFile alloc] initForReading:fileURL error:&e];
        AVAudioFormat *fileFormat = aFile.fileFormat;
        const AudioStreamBasicDescription *absd = [fileFormat streamDescription];
        if (absd) {
            AudioFormatID format = absd->mFormatID;
            if (format == kAudioFormatAppleLossless) {
                return YES;
            }
        }
    }
    return NO;
}

NSURL* ReplaceExtensionURL(const NSURL* u, NSString* ext){
    return [[u URLByDeletingPathExtension] URLByAppendingPathExtension:ext];
}


@interface NSOperationQueue (BlockAdditions)
- (void)addOperationWithClosure:(void (^)(NSBlockOperation *operation))block;
@end

@implementation NSOperationQueue (BlockAdditions)
- (void)addOperationWithClosure:(void (^)(NSBlockOperation *operation))block
{
    __block NSBlockOperation *operation = [[NSBlockOperation alloc] init];
    __weak NSBlockOperation *weakOperation = operation;
    [operation addExecutionBlock:^{
        block(weakOperation);
    }];
    
    [self addOperation:operation];
}
@end


@implementation FileOp

- (instancetype)initWithSourceURL:(NSURL *)s DestinationURL:(NSURL*)d
{
    self = [super init];
    if (self) {
        sourceURL=s;
        destinationURL=d;
    }
    return self;
}
@end

@interface CopyConvertDirs ()
@property (readwrite) BOOL isProcessing;
@property (readwrite) unsigned filesChecked;
@property (readwrite) unsigned filesToCopyConvert;
@property (readwrite) unsigned filesCopyConverted;

@property (readwrite) BOOL scanReady;

@end

@implementation CopyConvertDirs {
    NSMutableArray *convertOps;
    NSMutableArray *copyOps;
    volatile BOOL isCancelled;
    NSOperationQueue *queue;
    NSOperationQueue *opSubQ; // internal op queue used for individual operations inside the process directory
                              // implementation, vs. the queue used for the whole directory operation
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _skippedExtensions=nil;
        _copiedExtensions=nil;
        _filesChecked=0;

        convertOps = nil;
        copyOps = nil;
        queue=[[NSOperationQueue alloc] init];
        queue.name = @"TeslaTunes processing queue";
        opSubQ=[[NSOperationQueue alloc] init];
        // NSOperationQueueDefaultMaxConcurrentOperationCount was default but was creating what seemed to be a large number of threads
        opSubQ.maxConcurrentOperationCount = 4;
        opSubQ.name = @"TeslaTunes subprocessing queue";
        NSLog(@"Op Queue depth: %li", (long)opSubQ.maxConcurrentOperationCount);

    }
    return self;
}

- (void) cancelOngoingOperations {
    isCancelled = YES;
    self.scanReady = NO;

    NSLog(@"Cancelling all ongoing operations");
    [opSubQ cancelAllOperations];
    [queue cancelAllOperations];
    //[opSubQ waitUntilAllOperationsAreFinished];
    //[queue waitUntilAllOperationsAreFinished];
    //   NSLog(@"OpQueue says all operations are cancelled. And isProcessing is %hhd", self.isProcessing);
}
// Uses NSOperationQueue and NSOperation to concurrently run.  TODO: delegate or something to indicate when finished,etc.
- (void) startOperationOnDir: (DirOperation) opType withSourceDir: (const NSURL *)src andDestDir: (const NSURL *)dst {
    // if there are any operations still going on the queue, then this was an error to call.  Log and return.
    if (!queue || [queue operationCount]) {
        NSLog(@"Error, tried to start directory operations when operation queue was %s", queue? "not created": "not empty");
    }
    isCancelled = NO;
    // if we had a scan ready from before... well we won't after we start whatever we are doing here
    self.scanReady = NO;
    self.filesCopyConverted = 0;
    _skippedExtensions = [[NSCountedSet alloc] init ];
    _copiedExtensions = [[NSCountedSet alloc] init];
    

    // if operation is to scan, then clear out any current list of pending operations to do
    switch (opType) {
        case CCScan:
        case CCProcessWhileScanning: {
            [queue addOperationWithBlock:^(void){
                self.isProcessing = YES;
                [self processDirsSource:src Destination:dst ScanOnly:(opType==CCScan)];
                [opSubQ waitUntilAllOperationsAreFinished];
                self.isProcessing = NO;
            }];
        }
            break;
        case CCProcessScanned: {
            [queue addOperationWithBlock:^(void){
                self.isProcessing = YES;
                [self processScannedItems];
                [opSubQ waitUntilAllOperationsAreFinished];
                self.isProcessing = NO;
            }];
        }
            break;
        default:
            NSLog(@"Unknown directory operation type");
            break;
    }
    

    
}


- (void) storeScannedForCopyWithSource:(NSURL*)s Destination:(NSURL*)d {
    FileOp *newOp = [[FileOp alloc] initWithSourceURL:s DestinationURL: d];
    [copyOps addObject:newOp];
    [self.copiedExtensions addObject:s.pathExtension];
    
}
- (void) storeScannedForConvertWithSource:(NSURL*)s Destination:(NSURL*)d {
    FileOp *newOp = [[FileOp alloc] initWithSourceURL:s DestinationURL: d];
    [convertOps addObject:newOp];
    [self.copiedExtensions addObject:@"m4a->flac (Apple Lossless -> flac)"];
}

// We'll arbitrarily define reasonable as a small multiple of maxConcurrentOperationCount if
// max isn't set to default. If it is set to default, then we'll arbitrarily take a guess at max concurrent
-(void) chillTillQueueLengthIsReasonable:(NSOperationQueue*)q{
    NSInteger max = q.maxConcurrentOperationCount;
    if (max == NSOperationQueueDefaultMaxConcurrentOperationCount) max = 128;
    max *= 2;
    while (q.operationCount > max) {
        if (isCancelled) break;
        sleep(1);
    }
}

-(void) convertWithSource:(NSURL*)s Destination:(NSURL*)d {
    [self chillTillQueueLengthIsReasonable:opSubQ];
    // make the parent directory (and all other intermediate directories) if needed, then copy
    if (isCancelled) return;
    [opSubQ addOperationWithBlock:^(void){
        NSError *theError;
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (NO ==[fileManager createDirectoryAtURL:[d URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&theError]) {
            // createDirectory returns YES even if the dir already exists because
            // the "withIntermediateDirectories" flag is set, so if it fails, it's a real issue
            NSLog(@"Couldn't make target directory, error was domain %@, desc %@ - fail reason %@, code (%ld)",
                  [theError domain], [theError localizedDescription], [theError localizedFailureReason], (long)[theError code]);
            return;
        }
        
        NSLog(@"\nConverting Apple Lossless file->flac, %s, %s", s.fileSystemRepresentation, d.fileSystemRepresentation);
        if (ConvertAlacToFlac(s, d, &(isCancelled))) {
            [self.copiedExtensions addObject:@"m4a->flac (Apple Lossless -> flac)"];
            [self willChangeValueForKey:@"filesCopyConverted"];
            ++_filesCopyConverted;
            [self didChangeValueForKey:@"filesCopyConverted"];
        }
    }];
    NSLog(@"convert queued, current opSubQ depth:%lu", (unsigned long)opSubQ.operationCount);

}


-(void) copyWithSource:(NSURL*)s Destination:(NSURL*)d {
    [self chillTillQueueLengthIsReasonable:opSubQ];
    // make the parent directory (and all other intermediate directories) if needed, then copy
    [opSubQ addOperationWithBlock:^(void){
        NSError *theError;
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (NO ==[fileManager createDirectoryAtURL:[d URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&theError]) {
            // createDirectory returns YES even if the dir already exists because
            // the "withIntermediateDirectories" flag is set, so if it fails, it's a real issue
            // TODO: in one run early in development, the above statement was not true - got
            // dir already exists errors presumably when multiple threads were trying this same operation
            // with several songs on a new album.  So not sure what I should really do -- for now trying to
            // continue rather than return - the copy should fail too if it's an issue.
            NSLog(@"Couldn't make target directory, error was domain %@, desc %@ - fail reason %@, code (%ld)",
                  [theError domain], [theError localizedDescription], [theError localizedFailureReason], (long)[theError code]);
            // return;
        }
        
        NSLog(@"\nCopying %s to %s", s.fileSystemRepresentation, d.fileSystemRepresentation);
        if (![fileManager copyItemAtURL:s toURL:d error:&theError]){
            NSLog(@"Couldn't copy file \"%@\" to \"%@\", %@ - %@, (%ld)", s, d,
                  [theError localizedDescription], [theError localizedFailureReason], (long)[theError code] );
        } else {
            [self.copiedExtensions addObject:s.pathExtension];
            [self willChangeValueForKey:@"filesCopyConverted"];
            ++_filesCopyConverted;
            [self didChangeValueForKey:@"filesCopyConverted"];
        }
    }];
    NSLog(@"copy queued, current opSubQ depth:%lu", (unsigned long)opSubQ.operationCount);
}


- (void) processScannedItems {
    for (FileOp *f in copyOps) {
        @autoreleasepool {
            if (isCancelled) break;
            [self copyWithSource:f->sourceURL Destination:f->destinationURL];
        } }
    for (FileOp *f in convertOps) {
        @autoreleasepool {
            if (isCancelled) break;
            [self convertWithSource:f->sourceURL Destination:f->destinationURL];
        }
    }
}

- (void) processDirsSource:(const NSURL*)srcURL Destination: (const NSURL*)dstURL ScanOnly:(BOOL)scanOnly {
    
    // file types (types, not extensions) Tesla will play:  mp3, mp4/aac, flac, wma, wma lossless, aiff (16 bit), wav
    // Per an email from Tesla,  .MP3 .OGG .OGA .FLAC .MPC .WV .SPX .TTA .M4A .M4B .M4P .MP4 .3G2 .WMA .ASF .AIF .AIFF .WAV .APE .AAC
    
    NSSet *extensionsToCopy = [NSSet setWithObjects:@"mp3", @"aac", @"m4a", @"flac", @"wma", @"aiff", @"wav", nil];
    self.filesChecked = 0;
    self.filesToCopyConvert=0;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // TODO: verify cast below is ok - getting a warning, think due to const on the enumerator param, but we're not changing srcURL...
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:(NSURL*)srcURL
                                          includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
                                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                                        errorHandler:^BOOL(NSURL *url, NSError *error)
                                         {
                                             if (error) {
                                                 NSLog(@"[Error] %@ (%@)", error, url);
                                                 return NO;
                                             }
                                             
                                             return YES;
                                         }];
    // if we're doing a scan only, make new mutable arrays for the convert and copy ops, otherwise make sure they are nil
    if (scanOnly) {
        convertOps = [[NSMutableArray alloc] init];
        copyOps = [[NSMutableArray alloc] init];
        
    } else {
        convertOps = nil;
        copyOps = nil;
    }
    
    for (NSURL *fileURL in enumerator) {
        @autoreleasepool {
            if (isCancelled) break;
            NSString *filename;
            [fileURL getResourceValue:&filename forKey:NSURLNameKey error:nil];
            
            NSNumber *isDirectory;
            [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
            
            
            // Skip directories with '_' prefix, for example
            if ([filename hasPrefix:@"_"] && [isDirectory boolValue]) {
                [enumerator skipDescendants];
                continue;
            }
            
            NSURL* destFileURL = makeDestURL(dstURL, srcURL, fileURL);
            
            // PLACEHOLDER - todo  make a map of extensions/filetypes to handler operations
            
            if ([isDirectory boolValue]) {
                // check dest - it's ok if the dir doesn't exist at destination because we'll make it later
                // if needed due to having to copy a file in it.  But check to see if it exists and is a file
                // rather than directory to give early warning and avoid a cascade of errors.
                BOOL isDir;
                if ([fileManager fileExistsAtPath:[destFileURL path] isDirectory:&isDir] && !isDir) {
                    NSLog(@"Target directory \"%@\" exists but is a file - skipping subtree", [destFileURL path]);
                    [enumerator skipDescendants];
                }
            } else {
                [self willChangeValueForKey:@"filesChecked"];
                ++_filesChecked;
                [self didChangeValueForKey:@"filesChecked"];
                
                // figure out if we want to copy this item:  is it a type we want to copy?  Does it exist at dest?
                // use     – fileExistsAtPath:isDirectory: for the later
                if (isAppleLosslessFile(fileURL)) {
                    // do the conversion iff dest file doesn't exist
                    NSURL *transformedURL = ReplaceExtensionURL(destFileURL, @"flac");
                    if ([fileManager fileExistsAtPath:[transformedURL path] isDirectory:nil]) {
                        //printf("*");
                        continue;
                    }
                    [self willChangeValueForKey:@"filesToCopyConvert"];
                    ++_filesToCopyConvert;
                    [self didChangeValueForKey:@"filesToCopyConvert"];

                    if (scanOnly){
                        [self storeScannedForConvertWithSource:fileURL Destination:transformedURL];
                    } else {
                        [self convertWithSource:fileURL Destination:transformedURL];
                    }
                } else if ([extensionsToCopy containsObject:[fileURL.pathExtension lowercaseString]]) {
                    // NSLog(@"checking to see if %@ exists at dest path %@", fileURL, destFileURL);
                    // skip out if the file already exists (no need to copy)
                    if ([fileManager fileExistsAtPath:[destFileURL path] isDirectory:nil]) {
                        //printf(".");
                        continue;
                    }
                    [self willChangeValueForKey:@"filesToCopyConvert"];
                    ++_filesToCopyConvert;
                    [self didChangeValueForKey:@"filesToCopyConvert"];
                    if (scanOnly) {
                        [self storeScannedForCopyWithSource:fileURL Destination:destFileURL];
                    } else {
                        [self copyWithSource:fileURL Destination:destFileURL];
                    }
                } else {
                    // NSLog(@"don't know what extension %@ is.  Skipping", fileURL.pathExtension);
                    // save extension to skipped set for stat purposes
                    [self.skippedExtensions addObject:fileURL.pathExtension];
                }
            }
        }
    }
#if 0
    NSString *ext;
    NSLog(@"\nFiles checked: %u, Files to copy/convert: %u", _filesChecked, _filesToCopyConvert);
    for (ext in _copiedExtensions) {
        NSLog(@"%@ files copied: %lu", ext,[_copiedExtensions countForObject:ext]);
    }
    NSLog(@"\nExtensions skipped:");
    for (ext in _skippedExtensions) {
        NSLog(@"%@ files skipped: %lu", ext,[_skippedExtensions countForObject:ext]);
    }
#endif
    self.scanReady = (scanOnly && (convertOps.count || copyOps.count) );
}

@end




