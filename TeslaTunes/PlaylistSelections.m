//
//  PlaylistSelections.m
//  TeslaTunes
//
//  Created by Rob Arnold on 3/29/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import "PlaylistSelections.h"

#import <iTunesLibrary/ITLibrary.h>
#import <iTunesLibrary/ITLibMediaItem.h>
#import <iTunesLibrary/ITLibPlaylist.h>
#import <iTunesLibrary/ITLibArtist.h>
#import <iTunesLibrary/ITLibAlbum.h>


// First thought of using the iTunes data structures directly along with an auxilliary selected dictionary, but since we only
// wanted to display playlists, and of those only playlists marked visible, it became too complex and seemed like a lot
// of extra computation every outline refresh, re-iterating through all the data structure many times just to refresh the outline.



@interface PlaylistNode : NSObject
@property ITLibPlaylist *playlist;
@property NSArray *children;
@property NSNumber *selectedState;
@end

@implementation PlaylistNode
- (instancetype)initWithPlaylist:(ITLibPlaylist*) itemPlaylist andStateFromDict: (NSDictionary *) state
{
    self = [super init];
    if (self) {
        NSArray *childArray;
        self.playlist = itemPlaylist;
        self.children = nil;
        if (itemPlaylist) {
            if (![itemPlaylist isKindOfClass: [ITLibPlaylist class]]) {
                NSLog(@"PlaylistNode tried to init with a invalid playlist.");
                return nil;
            }
            NSNumber *savedState = [state objectForKey:itemPlaylist.persistentID];
            self.selectedState =  savedState? savedState: [NSNumber numberWithInteger:NSOffState];
            childArray = itemPlaylist.items;
            NSLog(@"Creating node with playlist %@", itemPlaylist.name);
        } else { // it's the root node, so load from library
            self.selectedState = [NSNumber numberWithInteger:NSOffState];
            NSLog(@"Making root playlist tree node.  Getting iTunes library info...");
            NSError *error = nil;
            ITLibrary *library = [ITLibrary libraryWithAPIVersion:@"1.0" error:&error];
            if (!library) {
                NSLog(@"error: %@", error);
                return nil;
            } else {
                NSLog(@"Got iTunes library info.");
                childArray = library.allPlaylists;
                
            }
        }
        // if we're here, then state and playlist have been set, and childArray is an array of potential children for this node.
        // go through them building child nodes and saving them in our children array if they are visible and playlists.
        
        NSMutableArray *tmp = [[NSMutableArray alloc] init];
        for (ITLibPlaylist* i in childArray) {
            //NSLog(@"inspecting %@ - %@, visible=%i, children = %@, count %lu", i, i.name, i.visible, i.items, (unsigned long)i.items.count);
            if (([i isKindOfClass: [ITLibPlaylist class]]) && i.visible && !i.master ) {
                NSLog(@"Adding node in %@ for %@", (itemPlaylist? itemPlaylist.name:@"root node"),  i.name);
                [tmp addObject:[[PlaylistNode alloc] initWithPlaylist:i andStateFromDict: state]];
            }
        }
        NSLog(@"...tree built.");
        if (tmp.count) {
            self.children = tmp;
        }
    }
    return self;
}

@end

@implementation PlaylistSelections {
    NSMutableDictionary *selected;
    PlaylistNode *playlistTree;
    
}
- (instancetype)init
{
    self = [super init];
    if (self) {
        NSLog(@"******** PlaylistSelections init called **********");
        selected = [[NSMutableDictionary alloc] init];
        // todo: use user defaults to persist the selected dict
        playlistTree = [[PlaylistNode alloc] initWithPlaylist:nil andStateFromDict:selected];
    }
    return self;
}


#pragma mark - Data Source methods

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    PlaylistNode *node = item;
    return (node?node:playlistTree).children.count;
}


- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    PlaylistNode *node = item? item:playlistTree;
    return node.children? YES: NO;
}


- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    PlaylistNode *node = item? item: playlistTree;
   return [node.children objectAtIndex:index];
}


- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    // if column is the checkmark, return state for the persistant ID, if column is name, return name
    //NSLog(@"Treeview requested value for column %@ and item %@", tableColumn.identifier, item);
    PlaylistNode *node = item? item : playlistTree;
    if ([tableColumn.identifier isEqualToString:@"selected"]) {
        NSLog(@"node selectedState get - %@", node.selectedState);
        return node.selectedState;
    } else if  ([tableColumn.identifier isEqualToString:@"playlist"]) {
        NSLog(@"node playlist name get - %@",  node.playlist? node.playlist.name : @"Playlist Name");
        return node.playlist? node.playlist.name : @"Playlist Name";
    } else {
        NSLog(@"Treeview requested value for unknown column %@", tableColumn.identifier);
        return nil;
    }
    
}

- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id) object ForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    PlaylistNode *node = item;
    if (!node) {
        NSLog(@"set value for column %@ for root obj - skipping", tableColumn.identifier);
        return;
    }
    if ([tableColumn.identifier isEqualToString:@"selected"]) {
        NSLog(@"setting selected state %@ for item id %@", object, node.playlist.persistentID);
        
        // All changes below discussed as repurcussions of the initial change need to be reflected in the selected dict too.
        // if state is mixed - well frankly don't think that should be able to happen via this call, only as a side effect? --log it
        // if state is off then erase entry from selected, but also rescan parent to set it's state... recurse/iterate up
        // if state is on, then add entry to selected,  rescan parent to set it's state... recurse/iterate up
        
        [selected setObject:object forKey:node.playlist.persistentID];
        node.selectedState = object;
    } else {
        NSLog(@"Treeview asked to set column %@ value %@ for item %@. Ignoring.", tableColumn.identifier, object, item);
    }
    
}


/*
 

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {

    return nil;
}



NSInteger selectedState  NSOffState NSOnState NSMixedState
 
 NSNumber *persistentID
 
 if ITLibPlaylist
    name
    visible
    items
 
 
 save list:
 persistentID selectedState if not off
 
 
 */

@end