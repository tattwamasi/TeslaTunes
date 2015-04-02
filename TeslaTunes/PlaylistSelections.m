//
//  PlaylistSelections.m
//  TeslaTunes
//
//  Created by Rob Arnold on 3/29/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import "PlaylistSelections.h"
#import "TableCellViewCheckmark.h"

#import <iTunesLibrary/ITLibrary.h>
#import <iTunesLibrary/ITLibMediaItem.h>
#import <iTunesLibrary/ITLibPlaylist.h>
#import <iTunesLibrary/ITLibArtist.h>
#import <iTunesLibrary/ITLibAlbum.h>


// First thought of using the iTunes data structures directly along with an auxilliary selected dictionary, but since we only
// wanted to display playlists, and of those only playlists marked visible, it became too complex and seemed like a lot
// of extra computation every outline refresh, re-iterating through all the data structure many times just to refresh the outline.



// Seems that playlists can conceptually contain other playlists, but it's not stored as a tree structure when we retrieve them.
// instead, from experimentation it seems like the items array is only filled with media items, never other playlists.  The only way to
// build the tree is to look at the parentID of a playlist.  A playlist itself has no concept of it's children, only the child knows it's parent.
// Furthermore, in iTunes you actually create either playlists or playlist folders.  A playlist folder can only contain other playlists, and
// appears to be represented as a playlist with a nil items array.




@interface PlaylistNode : NSObject
@property ITLibPlaylist *playlist;
@property NSMutableArray *children;
@property NSNumber *selectedState;
@end

@implementation PlaylistNode


- (instancetype) initWithPlaylist: (ITLibPlaylist*) playlist andState:(NSNumber*)state
{
    self = [super init];
    if (self) {
        self.playlist = playlist;
        self.children = nil;
        self.selectedState = state;
    }
    return self;
}
@end

@implementation PlaylistSelections {
    NSMutableDictionary *selected;
    NSMutableDictionary *playlistNodes;
    PlaylistNode *playlistTree;
}


- (instancetype)init
{
    self = [super init];
    if (self) {
        NSLog(@"******** PlaylistSelections init called **********");
        selected = [[NSMutableDictionary alloc] init];
        playlistNodes = [[NSMutableDictionary alloc] init];
        
        NSLog(@"Getting iTunes library info...");
        NSError *error = nil;
        ITLibrary *library = [ITLibrary libraryWithAPIVersion:@"1.0" error:&error];
        if (!library) {
            NSLog(@"error: %@", error);
            return nil;
        }
        NSLog(@"Got iTunes library info.  Reading playlists...");
        for (ITLibPlaylist *i in library.allPlaylists) {
            BOOL isPlaylist =[i isKindOfClass: [ITLibPlaylist class]];
            NSLog(@"inspecting %@.  item is class type %@.", i, [i  className]);
            if (isPlaylist)
                NSLog(@"\t item is playlist - name %@, visible=%i, master=%i children = %@, count %lu",
                      i.name, i.visible, i.master, i.items? @"<an array>":@"nil",
                      (unsigned long)i.items.count);
            
            if (([i isKindOfClass: [ITLibPlaylist class]]) && i.visible && !i.master ) {
                NSLog(@"Adding node for %@", i.name);
                NSNumber *savedState = [selected objectForKey:i.persistentID];
                
                PlaylistNode *node = [[PlaylistNode alloc] initWithPlaylist:i
                                        andState: savedState];
                [playlistNodes setObject:node forKey:i.persistentID];
                
            }
        }
        NSLog(@"Building playlist tree");
        // We do the scan through the playlists twice because I'm not sure if we're guaranteed
        // proper ordering such that a parent would always have been listed before it's children
        // Also, in the event that somehow a parent is not found, or was perhaps marked not visible,
        // marked as master, etc. we'll just root the node at the top level
        playlistTree = [[PlaylistNode alloc] initWithPlaylist:nil andState:[NSNumber numberWithInteger:NSOffState]];
        
        [playlistNodes setObject:playlistTree forKey:[NSNull null]];
        for (id key in playlistNodes) {
            if (key == [NSNull null]) {
                continue; // skip root node
            }
            PlaylistNode *node = playlistNodes[key];
            NSNumber *parentID = node.playlist.parentID;
            PlaylistNode* parent=[playlistNodes objectForKey:parentID?parentID:[NSNull null]];
            if (!parent) {
                NSLog(@"Can't find parent %@ for playlist %@ - listing in root",
                      node.playlist.parentID, node.playlist.name);
                parent = playlistTree;
            }
            if (!parent.children) {
                parent.children = [[NSMutableArray alloc] init];
            }
            [parent.children addObject:node];
            NSLog(@"Added child playlist %@ parentID %@ to parent %@ id %@",
                  node.playlist.name, node.playlist.parentID,
                  parent.playlist? parent.playlist.name:@"root",
                  parent.playlist?parent.playlist.persistentID:@"Null");
        }
    }
    return self;
}

- (void) setNode:(PlaylistNode*) node toSelectedState: (NSInteger) state {
    NSNumber *newState = [NSNumber numberWithInteger:state];
    node.selectedState = newState;
    // also copy it to our dictionary we'll persist, but if the state is NSOffState then
    // instead remove it from the dictionary so that we only store selected entries.
    if (state == NSOffState) {
        [selected removeObjectForKey:node.playlist.persistentID];
    } else {
        selected[node.playlist.persistentID] = newState;
    }
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
   
#if 0
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
#endif
    return item;
}


- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id) object ForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    NSLog(@"Treeview asked to set column %@ value %@ for item %@. Ignoring.", tableColumn.identifier, object, item);
#if 0
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
#endif
}

- (BOOL) outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item {
    PlaylistNode *node = item;
    return (nil != node.children);

}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    NSLog(@"viewForTableColumn called, tableColumn %@, item = %@", tableColumn.identifier, item);
    
    if (item) {
        PlaylistNode *node = item;
        if (node.children) { // it's a folder containing other playlists and/or folders - let's make the header view
            NSLog(@"Making header view");
            NSTableCellView *v = [outlineView makeViewWithIdentifier:@"header" owner:self];
            if (!v) {
                NSLog(@"makeView for header failed");
            }
            v.textField.stringValue = node.playlist.name;
            return v;
        } else {
            NSLog(@"Making playlist view for %@, checked=%@", node.playlist.name, node.selectedState);
            TableCellViewCheckmark *v =[outlineView makeViewWithIdentifier:@"data" owner:self];
            if (!v) {
                NSLog(@"makeView for playlist failed");
            }
            v.button.title = node.playlist.name;
            v.button.alternateTitle = node.playlist.name;
            v.button.state = [node.selectedState integerValue];
            return v;
            
        }
    } else {
        return nil;
    }
}


/*
 
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