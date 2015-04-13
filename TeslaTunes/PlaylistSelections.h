//
//  PlaylistSelections.h
//  TeslaTunes
//
//  Created by Rob Arnold on 3/29/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import <iTunesLibrary/ITLibrary.h>
#import <iTunesLibrary/ITLibMediaItem.h>
#import <iTunesLibrary/ITLibPlaylist.h>
#import <iTunesLibrary/ITLibArtist.h>
#import <iTunesLibrary/ITLibAlbum.h>


@interface PlaylistNode : NSObject
@property ITLibPlaylist *playlist;
@property NSMutableArray *children;
@property NSNumber *selectedState;
- (BOOL) enumerateTreeUsingBlock: (void(^)(PlaylistNode* node, BOOL *stop)) block;
@end


@interface PlaylistSelections : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>
- (void) setNode:(PlaylistNode*) node toSelectedState: (NSInteger) state;
- (void) saveSelected;
- (PlaylistNode*) getTree;
- (ITLibrary*) getLibrary;
@end
