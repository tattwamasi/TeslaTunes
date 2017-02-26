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

#include <tag/tag.h>
#include <tag/fileref.h>
#include <tag/tfile.h>
#include <tag/tpropertymap.h>




#include "flac_utils.h"

// NSString *disallowedCharsRegEx=@"[;:,/|!@#$%&*\()^]";
NSString *disallowedCharsRegEx=@"[/|]";

NSString *sanitizeFilename(NSString* f) {
    
    NSString *sanitizedString = [f stringByReplacingOccurrencesOfString:disallowedCharsRegEx withString:@"_"
                                                                options:NSRegularExpressionSearch
                                                                  range: NSMakeRange(0, [f length]) ];
    return sanitizedString;
}


// make the destination filename out of the base path of destination and the relative path of the new item
NSURL* makeDestURL(const NSURL *dstBasePath, const NSURL *basePathToStrip, const NSURL* srcURL) {
    // Need to create the destination file/dir URL to check it's existance.  Use dst and the relative path
    // perhaps via + (NSURL *)fileURLWithPathComponents:(NSArray *)components with and array concat/splice
    // from dst components + relatice slice of src components
    
    
    // May well be a better way.  Till then...
    NSArray *basePathComponents = [basePathToStrip pathComponents];
    NSArray *srcPathComponents = [srcURL pathComponents];
    
    NSRange relPathRange;
    
    // sanity check
    relPathRange.location = 0;
    relPathRange.length = basePathComponents.count; // start the relative path at the end of the base path
    
    if ((srcPathComponents.count <= basePathComponents.count) ||
        ![basePathComponents isEqualToArray: [srcPathComponents subarrayWithRange:relPathRange]]) {
        NSLog(@"When stripping base path from source filename to create destination filename, "
              "detected base path wasn't actually a common path.\nBase path was \"%@\".\nSource path was \"%@\".\n",
              basePathToStrip, srcURL);
        // set NSRange object to take whole srcURL
        relPathRange.location = 0;
        relPathRange.length = srcPathComponents.count;
    } else {
        relPathRange.location = basePathComponents.count; // start the relative path at the end of the base path
        relPathRange.length = srcPathComponents.count - basePathComponents.count;
    }
    NSURL *dstURL = [NSURL fileURLWithPathComponents:
                     [[dstBasePath pathComponents] arrayByAddingObjectsFromArray:
                      [srcPathComponents subarrayWithRange:relPathRange]]];
    
    return dstURL;
}


//AVURLAsset *asset = [[[AVURLAsset alloc] initWithURL:sourceURL options:nil] autorelease];

BOOL isAppleLosslessFile(const NSURL *fileURL){
    if ([[fileURL.pathExtension lowercaseString] isEqualToString:@"m4a"]) {
        NSError *e;
        AVAudioFile *aFile = [[AVAudioFile alloc] initForReading:[fileURL URLByStandardizingPath] error:&e];
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

- (instancetype)initWithSourceURL:(const NSURL *)s DestinationURL:(const NSURL*)d  withPlaylist: (const NSString *) p
{
    self = [super init];
    if (self) {
        sourceURL=s;
        destinationURL=d;
        playlist=p;
    }
    return self;
}
@end

@interface CopyConvertDirs ()
@property (readwrite) BOOL isProcessing;
@property (readwrite) unsigned filesChecked;
@property (readwrite) unsigned filesToCopyConvert;
@property (readwrite) unsigned filesCopyConverted;
@property (readwrite) unsigned filesMarkedForOrDeleted;

@property (readwrite) BOOL scanReady;

@end

@implementation CopyConvertDirs {
    
    NSSet *extensionsToCopy;
    
    NSMutableArray *convertOps;
    NSMutableArray *copyOps;
    NSMutableArray *delOps;
    volatile BOOL isCancelled;
    NSOperationQueue *queue;
    NSOperationQueue *opSubQ; // internal op queue used for individual operations inside the process directory
                              // implementation, vs. the queue used for the whole directory operation
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _skippedExtensions=nil;
        _copiedExtensions=nil;
        _filesChecked=0;
        
        convertOps = nil;
        copyOps = nil;
        delOps = nil;
        queue=[[NSOperationQueue alloc] init];
        queue.name = @"TeslaTunes processing queue";
        opSubQ=[[NSOperationQueue alloc] init];
        // NSOperationQueueDefaultMaxConcurrentOperationCount was default but was creating what seemed to be a large number of threads
        opSubQ.maxConcurrentOperationCount = 4;
        opSubQ.name = @"TeslaTunes subprocessing queue";
        
        
        // file types (types, not extensions) Tesla will play:  mp3, mp4/aac, flac, wma, wma lossless, aiff (16 bit), wav
        // Per an email from Tesla,  .MP3 .OGG .OGA .FLAC .MPC .WV .SPX .TTA .M4A .M4B .M4P .MP4 .3G2 .WMA .ASF .AIF .AIFF .WAV .APE .AAC
        
        extensionsToCopy = [NSSet setWithObjects:@"mp3", @"aac", @"m4a", @"flac", @"wma", @"aiff", @"wav", nil];
        
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
- (void) startOperationOnDir: (DirOperation) opType withPlaylistSelections:(const PlaylistSelections *)playlistSelections
                andSourceDir:(const NSURL *)src toDestDir:(const NSURL *)dst {
    // if there are any operations still going on the queue, then this was an error to call.  Log and return.
    if (!queue || [queue operationCount]) {
        NSLog(@"Error, tried to start directory operations when operation queue was %s", queue? "not created": "not empty");
    }
    isCancelled = NO;
    // if we had a scan ready from before... well we won't after we start whatever we are doing here
    self.scanReady = NO;
    self.filesCopyConverted = 0;
    self.filesMarkedForOrDeleted = 0;
    _skippedExtensions = [[NSCountedSet alloc] init ];
    _copiedExtensions = [[NSCountedSet alloc] init];
    
    
    // if operation is to scan, then clear out any current list of pending operations to do
    switch (opType) {
        case CCScan:
        case CCProcessWhileScanning: {
            [queue addOperationWithBlock:^(void){
                self.isProcessing = YES;
                [self processOpsWithPlaylistSelections: playlistSelections andSourceDirectoryURL:src
                             toDestinationDirectoryURL:dst performScanOnly:(opType==CCScan)];
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


// manipulate the tags on the media item at url taking into account
// current settings of tag options
// Return YES if tags were successfully updated, NO otherwise.
- (BOOL) twiddleTags: (const NSURL *) url withPlaylist: (const NSString *) playlist {
    
    TagLib::FileRef f([url fileSystemRepresentation], false);
    TagLib::Tag *t = f.tag();
    
    if (!t) {
        NSLog(@"Couldn't get tags from %@, so couldn't update them.", url);
        return NO;
    }
    bool needsSaving = false;
    if (playlist) {
        if (self.stripTagsForPlaylists) {
            // note: had originally planned to strip all tags.  Genre will be added back later if hackGenre is true
            // however, the S only has play groupings for album, artist, song, and genre, so instead of removing all tags,
            // let's try just removing these.
            t->setAlbum(TagLib::String::String());
            t->setArtist(TagLib::String::String());
            t->setTitle(TagLib::String::String());
            t->setGenre(TagLib::String::String());
            needsSaving = true;
        }
        if (self.hackGenre) {
            t->setGenre([playlist UTF8String]);
            needsSaving = true;
            //NSLog(@"Set genre of %@ to %s", url, t->genre().toCString(true) );
        }
    }
    
    if (self.embedDiscNumberInTrackNumber) {
        auto props = f.file()->properties();
        auto proplist = props["DISCNUMBER"];
        if (!proplist.isEmpty()) {
            // convert the disc number to an int. If we can and it's > 1, then map it into the track number
            int discNumber = proplist.front().toInt(); // if this fails, it returns 0 - which works fine for us
            if (discNumber>1) {
                t->setTrack(t->track() + discNumber*100);
                needsSaving = true;
            }
            
        }
    }
    
    if (self.remapAlbumArtistToArtistAndTitle && !(playlist && self.stripTagsForPlaylists)) {
        // if there's an album artist, set artist to album artist, and add artist to title
        // auto props = t->properties();
        auto props = f.file()->properties();
#if 0
        NSLog(@"Remap Check for %s", [url fileSystemRepresentation]);
        for (auto p : props) {
            NSLog(@"Property: %s  => %s", p.first.toCString(true), p.second.toString().toCString(true) );
        }
        auto unsupportedData = props.unsupportedData();
        for (auto s : unsupportedData) {
            NSLog(@"Unsupported data item: \"%s\"", s.toCString(true));
        }
#endif
        auto albumArtistList = props["ALBUMARTIST"];
        if (! albumArtistList.isEmpty() ) {
            auto albumArtist = albumArtistList.front();
            auto newTitle = t->title();
            newTitle += " - ";
            newTitle += t->artist();
            t->setTitle(newTitle);
            t->setArtist(albumArtist);
            needsSaving = true;
            //NSLog(@"Remap %s:  Set title to %s, and artist to %s.", url.fileSystemRepresentation, t->title().toCString(true), t->artist().toCString(true));
        }
    }
    // todo:  see if save optimizes for case where nothing changed, or set flag so we don't save if we didn't do anything
    if (needsSaving && !f.save()){
        NSLog(@"warning:  couldn't save file after updating tags of %@", playlist?
              [NSString stringWithFormat:@"%@ in playlist %@", url, playlist] : url);
        return NO;
    }
    return YES;
}

- (void) storeScannedForCopyWithSource:(const NSURL*)s Destination:(const NSURL*)d withPlaylist: (const NSString *) playlist {
    FileOp *newOp = [[FileOp alloc] initWithSourceURL:s DestinationURL: d withPlaylist: playlist];
    [copyOps addObject:newOp];
    [self.copiedExtensions addObject:s.pathExtension];
    
}
- (void) storeScannedForConvertWithSource:(const NSURL*)s Destination:(const NSURL*)d withPlaylist: (const NSString *) playlist  {
    FileOp *newOp = [[FileOp alloc] initWithSourceURL:s DestinationURL: d withPlaylist: playlist];
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

BOOL makeDirsAsNeeded(const NSURL* d) {
    NSError *theError;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (NO ==[fileManager createDirectoryAtURL:[d URLByDeletingLastPathComponent]
                   withIntermediateDirectories:YES attributes:nil error:&theError]) {
        // createDirectory returns YES even if the dir already exists because
        // the "withIntermediateDirectories" flag is set according to the documentation,
        // so if it fails, it's a real issue... BUT turns out the documentation may be wrong.
        // In testing, I sometimes got dir already exists errors presumably when multiple threads
        // were trying this same operation with several songs on a new album.
        // So not sure what I should really do -- added all the code below to try to figure out
        // if it's a real error.
        BOOL isDir;
        if ([theError code] != NSFileWriteFileExistsError) {
            // an error, so let's skip the conversion
            NSLog(@"warning: couldn't make target directory; %@ code (%ld).  Skipping handling of %@",
                  [theError localizedDescription], (long)[theError code], d);
            return NO;
        }
        if ([fileManager fileExistsAtPath:[[d URLByDeletingLastPathComponent] path]
                              isDirectory:&isDir]) {
            if (!isDir) {
                NSLog(@"warning: when handling \"%@\", tried to make the directory to hold it, "
                      "but a file already existed by that name that was not a directory.  Skipping "
                      "conversion.", d);
                return NO;
            }
        } else {
            NSLog(@"warning: beats me what's happening.  Report this.  Tried to create directory to "
                  "hold %@, but got a file exists error, yet I looked and the file doesn't exist.  "
                  "Skipping conversion.)", d);
            return NO;
        }
    }
    
    // if we're here either the directory was made, or it wasn't made this time, but it
    // exists and is a directory.
    return YES;
}

-(void) convertWithSource:(const NSURL*)s Destination:(const NSURL*)d withPlaylist: (const NSString*) playlist {
    [self chillTillQueueLengthIsReasonable:opSubQ];
    // make the parent directory (and all other intermediate directories) if needed, then copy
    if (isCancelled) return;
    [opSubQ addOperationWithBlock:^(void){
        if (makeDirsAsNeeded(d)) {
            //NSLog(@"\nConverting Apple Lossless file->flac, %s, %s", s.fileSystemRepresentation, d.fileSystemRepresentation);
            if (ConvertAlacToFlac([s URLByStandardizingPath], [d URLByStandardizingPath], &(isCancelled))) {
                [self.copiedExtensions addObject:@"m4a->flac (Apple Lossless -> flac)"];
                [self willChangeValueForKey:@"filesCopyConverted"];
                ++_filesCopyConverted;
                [self didChangeValueForKey:@"filesCopyConverted"];
                [self twiddleTags:d withPlaylist:playlist];
            }
        }
    }];
    //NSLog(@"convert queued, current opSubQ depth:%lu", (unsigned long)opSubQ.operationCount);
    
}


-(void) copyWithSource:(const NSURL*)s Destination:(const NSURL*)d withPlaylist: (const NSString*) playlist {
    [self chillTillQueueLengthIsReasonable:opSubQ];
    // make the parent directory (and all other intermediate directories) if needed, then copy
    [opSubQ addOperationWithBlock:^(void){
        if (makeDirsAsNeeded(d)) {
            NSError *theError;
            NSFileManager *fileManager = [NSFileManager defaultManager];
            
            //NSLog(@"\nCopying %s to %s", s.fileSystemRepresentation, d.fileSystemRepresentation);
            if (![fileManager copyItemAtURL:[s URLByStandardizingPath] toURL:[d URLByStandardizingPath] error:&theError]){
                NSLog(@"Couldn't copy file \"%@\" to \"%@\", %@ (%ld)", s, d,
                      [theError localizedDescription], (long)[theError code] );
            } else {
                [self.copiedExtensions addObject:s.pathExtension];
                [self willChangeValueForKey:@"filesCopyConverted"];
                ++_filesCopyConverted;
                [self didChangeValueForKey:@"filesCopyConverted"];
                [self twiddleTags:d withPlaylist:playlist];
            }
        }
    }];
    //NSLog(@"copy queued, current opSubQ depth:%lu", (unsigned long)opSubQ.operationCount);
}


- (void) processScannedItems {
    for (FileOp *f in copyOps) {
        @autoreleasepool {
            if (isCancelled) break;
            [self copyWithSource:f->sourceURL
                     Destination:f->destinationURL withPlaylist: f->playlist];
        }
    }
    for (FileOp *f in convertOps) {
        @autoreleasepool {
            if (isCancelled) break;
            [self convertWithSource:f->sourceURL
                        Destination:f->destinationURL withPlaylist: f->playlist];
        }
    }
    for (NSURL *f in delOps) {
        if (isCancelled) break;
        ++self.filesMarkedForOrDeleted;
        NSError *e;
        if (![[NSFileManager defaultManager] removeItemAtURL:f
                                                       error:&e]) {
            // check and report potential cleanup failure - note that if f is nil, the operation returns YES
            // TODO: see above
            NSLog(@"Couldn't remove from playlist folder item URL \"%@\". %@ (%ld)", f, [e localizedDescription], [e code]);
        }
    }
}

// Returns the URL of the processed file at the destination, or nil in the event of error/cancellation
// or simply that the file is not a handled type.  Note it will also return the filename in
// the event it is a handled filetype and does not need to be copied because it is already there.
// setGenre will, if not nil, set the genre of the destination file, iff copied/converted.
// TODO: check returns of copys/converts and return appropriately
- (NSURL *) processFileURL:(const NSURL *) file toDestination: destinationFile
           performScanOnly: (BOOL) scanOnly withPlaylist: (NSString*) playlist {
    @autoreleasepool {
        if (isCancelled) return nil;
        NSString *filename;
        [file getResourceValue:&filename forKey:NSURLNameKey error:nil];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL *outURL;
        
        [self willChangeValueForKey:@"filesChecked"];
        ++_filesChecked;
        [self didChangeValueForKey:@"filesChecked"];
        
        // figure out if we want to copy this item:  is it a type we want to copy?
        // Does it exist at dest?
        // use  – fileExistsAtPath:isDirectory: for the later
        if (isAppleLosslessFile(file)) {
            // do the conversion iff dest file doesn't exist
            outURL = ReplaceExtensionURL(destinationFile, @"flac");
            if ([fileManager fileExistsAtPath:[outURL path] isDirectory:nil]) {
                //printf("*");
                return outURL;
            }
            [self willChangeValueForKey:@"filesToCopyConvert"];
            ++_filesToCopyConvert;
            [self didChangeValueForKey:@"filesToCopyConvert"];
            
            if (scanOnly){
                [self storeScannedForConvertWithSource:file Destination:outURL withPlaylist: playlist];
            } else {
                [self convertWithSource:file Destination:outURL  withPlaylist: playlist];
            }
        } else if ([extensionsToCopy containsObject:[file.pathExtension lowercaseString]]) {
            // NSLog(@"checking to see if %@ exists at dest path %@", fileURL, destFileURL);
            // skip out if the file already exists (no need to copy)
            if ([fileManager fileExistsAtPath:[destinationFile path] isDirectory:nil]) {
                //printf(".");
                return destinationFile;
            }
            [self willChangeValueForKey:@"filesToCopyConvert"];
            ++_filesToCopyConvert;
            [self didChangeValueForKey:@"filesToCopyConvert"];
            if (scanOnly) {
                [self storeScannedForCopyWithSource:file Destination:destinationFile  withPlaylist: playlist];
            } else {
                [self copyWithSource:file Destination:destinationFile withPlaylist: playlist];
            }
            outURL = destinationFile;
        } else {
            NSLog(@"don't know what extension \"%@\" is.  Skipping", file.pathExtension? file.pathExtension: @"<no extension>");
            // save extension to skipped set for stat purposes
            [self.skippedExtensions addObject:file.pathExtension? file.pathExtension : @"no extension"];
            return nil;
        }
        
        return outURL;
    }
    
}



// Used to delete media from playlist folders while syncing a playlist.  Also used to delete playlist folders
// from the Playlist top level folder on the destination, for playlists that are no longer selected.
// NOTE: We use fileSystemRepresentation NSStrings instead of URLs when comparing files from the directory
// enumerator to ones in the fileset.  This is because a URL will end in a / if it already exists,
// but will not if it doesn't exist yet -  makes sense, but would mess up simple string matching of URLs
// and was causing a bug.
// The fileSystemRepresentation is the same whether it exists yet or not, and when read back
// from the dir enumerator

- (BOOL) pruneFilesNotInSet: (const NSSet*) fileSet inDirectory: (const NSURL*) dir
            performScanOnly: (BOOL) scanOnly {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:(NSURL*)dir
                                          includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
                                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                                        errorHandler:^BOOL(NSURL *url, NSError *error)
         {
             // this could happen without it being an error in the event the
             // destination playlist doesn't exist yet, for example when doing
             // a scan only for the first time on a playlist, or simply getting the operations to copy
             // a playlist queued up behind other ops in the queue, then hitting the prune code before
             // any of them had gotten to execute yet. Regardless, if that's the case,
             // it isn't an error, and there obviously won't be anything to remove.
             if (error  && (error.code != NSFileReadNoSuchFileError)) {
                 NSLog(@"Error when looking for destination playlist folder \"%@\" to prune. %@ (%ld)%@",
                       dir, [error localizedDescription],
                       [error code], url? [NSString stringWithFormat:@" Happened when looking at \"%@\"",url] : @"");
                 return NO;
             }
             // either no error?!? or error code is no such file which probably means the scenario in the above comment happened
             return YES;
         }];
    
    for (NSURL *fileURL in enumerator) {
        if (isCancelled) {
            return NO;
        }
        
        
        // If the URL is a directory and it's in our fileSet, then we'll call it good.  We don't want to recurse into it
        // and end up deleting things we shouldn't, due to this being called with only playlist folders in the fileSet, as
        // part of the playlist cleanup of playlists no longer selected.
        // If the URL is a directory, and it's not in our fileSet, then the delete will recursively remove any files/dirs in it,
        // so either way we tell the enumerator to skip descendents so we don't work harder than needed.
        NSNumber *isDirectory;
        [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        if ([isDirectory boolValue]) {
            [enumerator skipDescendants];
        }
        
        // TODO: not sure if containsObject works the way I expect here - seems like I'm asking if a new NSString object
        //  which happens to have the same data in it as another object in the set, is contained in the set.
        //  I'd expect that to never work since they are different objects, but ObjC surprises me at times - not
        //  sure how the equality is checked.
        if (![fileSet containsObject:[NSString stringWithUTF8String:fileURL.fileSystemRepresentation]]) {
            // if scan only, queue the delete, if not then do the delete
            ++self.filesMarkedForOrDeleted;
            
            if (scanOnly) {
                //NSLog(@"adding op to remove \"%@\"", fileURL);
                [delOps addObject:fileURL];
            } else {
                //NSLog(@"pruning %s", fileURL.fileSystemRepresentation);
                NSError *e;
                if (![[NSFileManager defaultManager] removeItemAtURL:fileURL error:&e]) {
                    // check and report potential cleanup failure - note that if f is nil, the operation returns YES
                    // TODO: see above
                    NSLog(@"Couldn't remove from playlist folder item URL \"%@\". %@ (%ld)",
                          fileURL, [e localizedDescription], [e code]);
                }
                
            }
        }
    }
    return YES;
}




// process a playlist by creating (if needed) the destination folder, copy/convert all
// files in the playlist to the folder, mapping to a filename pattern that preserves
// playlist order and eliminates collisions.  Also, delete any other files in the folder
// that weren't in the playlist.
// Return NO if processing was interrupted, either by error, or by cancel flag being set, YES otherwise
- (BOOL) processPlaylistNode:(PlaylistNode *) node toDestinationDirectoryURL: destinationFolderForPlaylist
             performScanOnly: (BOOL) scanOnly {
    //NSLog(@"playlist %@ was selected and will be copied to %s", node.playlist.name, destinationFolderForPlaylist.fileSystemRepresentation);
    NSMutableSet *playlistFilenames = [[NSMutableSet alloc] init];
    
    int idx = 0;
    NSUInteger number = node.playlist.items.count;
    int digits = 0; do { number /= 10; digits++; } while (number != 0);
    
    for (id item in node.playlist.items) {
        
        if (isCancelled) break;
        ITLibMediaItem *track = item;
        ++idx;
        
        // TODO:
        // we need to validate that the location is legit and in some way warn the user or otherwise deal with it
        // if it is not.
        if (!track.location) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = [NSString stringWithFormat:
                                 @"The track \"%@\" in playlist \"%@\" has no location specified.  Do you want to skip this track, "
                                 "or stop processing altogether so you can try to fix the issue and start over?",
                                 track.title, node.playlist.name];
            alert.informativeText = @"This can happen, for example, when you have your library stored on a networked or external "
                "drive and the drive isn't currently available.  Make sure it is, and check that iTunes can play the track(s).";
            [alert addButtonWithTitle:@"Stop processing"];
            [alert addButtonWithTitle:@"Skip track"];
            
            __block NSModalResponse response;
            dispatch_sync(dispatch_get_main_queue(), ^(){
                response = [alert runModal];
            });
            
            if (response == NSAlertFirstButtonReturn) {
                return NO;
            }
            continue;
            
        }
        
        @autoreleasepool {
            // Had planned to match majorlance's applescript and keep same name format,
            // but not sure why it really makes sense to keep playlist name in it if we are putting this in
            // it's own folder.  Also it seems like we need to put the playlist order in the filename,
            // in order to preserve the ability to have duplicates in the playlist and play in order.
            
            // so given that, example filename is index-trackname-trackartist-trackalbum.extension
            NSString *filename = sanitizeFilename([NSString stringWithFormat:@"%0*d-%@-%@-%@.%@", digits,
                                                   idx, track.title, track.artist.name, track.album.title,
                                                   [track.location pathExtension] ]);

            NSURL *destFileURL = [[destinationFolderForPlaylist URLByAppendingPathComponent: filename] URLByStandardizingPath];
            
#if 0
            NSLog(@"Copying track %@ from location type %lu, locations %s to %s", track.title,
                  (unsigned long)track.locationType,
                  track.location.fileSystemRepresentation, destFileURL.fileSystemRepresentation);
#endif
            
            if (track.location) {
                NSURL *result = [self processFileURL:track.location toDestination: destFileURL performScanOnly:scanOnly
                                            withPlaylist: node.playlist.name];
                if (result) {
                    [playlistFilenames addObject:[NSString stringWithUTF8String:result.fileSystemRepresentation]];
                    //NSLog(@"adding to playlistFilename %s", result.fileSystemRepresentation);
                }
            }
        }
    }
    
    if (isCancelled)
        return NO;
    // now go through the destination playlist folder and delete any files not in the playlistFilenames set
    return [self pruneFilesNotInSet: playlistFilenames inDirectory: destinationFolderForPlaylist performScanOnly: scanOnly];
    
}


- (void) processOpsWithPlaylistSelections: (const PlaylistSelections *)playlistSelections
                    andSourceDirectoryURL: (const NSURL *) sourceDir
                toDestinationDirectoryURL: (const NSURL *) destinationDir
                          performScanOnly: (BOOL) scanOnly {
    self.filesChecked = 0;
    self.filesToCopyConvert=0;
    
    
    // if we're doing a scan only, make new mutable arrays for the convert and copy ops, otherwise make sure they are nil
    if (scanOnly) {
        convertOps = [[NSMutableArray alloc] init];
        copyOps = [[NSMutableArray alloc] init];
        delOps = [[NSMutableArray alloc] init];
        
    } else {
        convertOps = nil;
        copyOps = nil;
        delOps = nil;
    }
    
    NSURL *musicFolderURL = [destinationDir URLByAppendingPathComponent:@"Music"];
    NSURL *playlistFolderURL = [destinationDir URLByAppendingPathComponent:@"Playlists"];
    
    
    if (sourceDir) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        // TODO: verify cast below is ok - getting a warning, think due to const on the enumerator param, but we're not changing srcURL...
        NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:(NSURL*)sourceDir
                                              includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
                                                                 options:NSDirectoryEnumerationSkipsHiddenFiles
                                                            errorHandler:^BOOL(NSURL *url, NSError *error)
                                             {
                                                 if (error) {
                                                     NSLog(@"warning: error trying to scan source directory %@. %@ (%@)",
                                                           sourceDir, error, url);
                                                     return NO;
                                                 }
                                                 
                                                 return YES;
                                             }];
        
        for (NSURL *fileURL in enumerator) {
            if (isCancelled) break;
            @autoreleasepool {
                NSString *filename;
                [fileURL getResourceValue:&filename forKey:NSURLNameKey error:nil];
                
                NSNumber *isDirectory;
                [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
                
                NSURL* destFileURL = makeDestURL(musicFolderURL, sourceDir, fileURL);
                
                // PLACEHOLDER - todo  make a map of extensions/filetypes to handler operations
                
                if ([isDirectory boolValue]) {
                    // check dest - it's ok if the dir doesn't exist at destination because we'll make it later
                    // if needed due to having to copy a file in it.  But check to see if it exists and is a file
                    // rather than directory to give early warning and avoid a cascade of errors.
                    BOOL isDir;
                    if ([fileManager fileExistsAtPath:[destFileURL path] isDirectory:&isDir] && !isDir) {
                        NSLog(@"Target directory \"%@\" exists but is a file - skipping subtree", [destFileURL path]);
                        [enumerator skipDescendants];
                    } else if ([filename hasPrefix:@"."] ) {
                        [enumerator skipDescendants];
                    }
                    continue;
                }
                [self processFileURL:fileURL toDestination: destFileURL performScanOnly:scanOnly withPlaylist:nil];
            }
        }
        
    }
    if (playlistSelections && !isCancelled) {
        PlaylistNode *playlistTree = [playlistSelections getTree];
        NSMutableSet *playlistFolders = [[NSMutableSet alloc] init];
        
        [playlistTree enumerateTreeUsingBlock:^(PlaylistNode* node, BOOL* stop) {
            if (node.playlist && ([node.selectedState integerValue] == NSOnState) && node.playlist.items) {
                NSURL* destinationFolderForPlaylist = [[playlistFolderURL
                                                        URLByAppendingPathComponent:sanitizeFilename(node.playlist.name)] URLByStandardizingPath];
                // NOTE: path will end in a / if it already exists, but will not if it doesn't exist yet -
                // makes sense, but would mess up simple string matching of URLs in the prunefiles step, so use
                // the fileSystemRepresentation, which will be the same whether it exists yet or not, and when read back
                // from the dir enumerator
                [playlistFolders addObject:[NSString stringWithUTF8String:destinationFolderForPlaylist.fileSystemRepresentation]];
                //NSLog(@"adding playlist folder to avoid pruning list, %s", destinationFolderForPlaylist.fileSystemRepresentation);
                if (![self processPlaylistNode:node toDestinationDirectoryURL: destinationFolderForPlaylist performScanOnly:scanOnly]) {
                    *stop = YES;
                }
                
            }
        }];
        if (!isCancelled) {
            [self pruneFilesNotInSet:playlistFolders inDirectory:playlistFolderURL performScanOnly:scanOnly];
        }
    }

    self.scanReady = (scanOnly && (convertOps.count || copyOps.count || delOps.count) );
}

@end




