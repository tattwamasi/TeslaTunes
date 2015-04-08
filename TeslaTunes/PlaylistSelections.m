//
//  PlaylistSelections.m
//  TeslaTunes
//
//  Created by Rob Arnold on 3/29/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import "PlaylistSelections.h"
#import "TableCellViewCheckmark.h"


// First thought of using the iTunes data structures directly along with an auxilliary selected dictionary, but since we only
// wanted to display playlists, and of those only playlists marked visible, it became too complex and seemed like a lot
// of extra computation every outline refresh, re-iterating through all the data structure many times just to refresh the outline.



// Seems that playlists can conceptually contain other playlists, but it's not stored as a tree structure when we retrieve them.
// instead, from experimentation it seems like the items array is only filled with media items, never other playlists.  The only way to
// build the tree is to look at the parentID of a playlist.  A playlist itself has no concept of it's children, only the child knows it's parent.
// Furthermore, in iTunes you actually create either playlists or playlist folders.  A playlist folder can only contain other playlists, and
// appears to be represented as a playlist with a nil items array.


//  TODO:  At first thought this should be broken apart into the reusable data model portion(s) for both a generic treeview
//  which would then be used by the iTunes playlists specific data model, and then also a seperate view controller.  However,
//  since I didn't use bindings (after having trouble with them originally - I think they'd actually work fine now), and since
//  each of the individual parts is simple, but involves the others, kind of seems like I should just put all this in the view controller.
//
//  Also, make it so the selected dictionary is read from user defaults and used when the tree is built to pre-select previous selections,
//  if still existing, then don't use the dict anymore. Make a new dict when the selection window goes away and save that to user defaults.
//
//  Make methods to get data required out of the tree - probably just an enumerator returning the media entries and playlist names - or
//  maybe just the playlist name and path to file
//
//  Other todo - fix UI constraints.  Make playlist tree look better - how?  consider side/detail windows(s) as alternate design, with
//  playlist selections, etc. on left, and operations details/status/progress right.
//  Integrate playlist operations into what happens when you click do it.

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

// return YES if enumeration went through entire tree structure, NO if terminated early due to block
// setting stop flag
- (BOOL) enumerateTreeUsingBlock: (void(^)(PlaylistNode* node, BOOL *stop)) block {
    BOOL stopFlag = NO;
    block(self, &stopFlag);
    if (stopFlag)
        return NO;
    
    PlaylistNode *node;
    for (node in self.children) {
        if (![node enumerateTreeUsingBlock: block])
            return NO;
    }
    return YES;
}


#if 0
// For fast enumeration - todo if needed
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackbuf count:(NSUInteger)len {
    return 0;
}
#endif

@end

@implementation PlaylistSelections {
     PlaylistNode *playlistTree;
    ITLibrary *library;
    
}

- (PlaylistNode*) getTree {
    return playlistTree;
}
- (ITLibrary*) getLibrary {
    return library;
}
- (void) saveSelected {
    NSLog(@"saving selected playlist preferences");
    NSMutableDictionary *selectedDefaults = [[NSMutableDictionary alloc] init];
    // go through the tree, creating the SelectedPlaylists dictionary, then put it into defaults
    [playlistTree enumerateTreeUsingBlock:^(PlaylistNode *node, BOOL *stop){
        if (node.playlist && ([node.selectedState integerValue] != NSOffState)) {
            [selectedDefaults setObject:node.selectedState
                forKey:[node.playlist.persistentID stringValue]];
            NSLog(@"saving selected playlist %@ to defaults.  Contains tracks:", node.playlist.name);
            for (ITLibMediaItem *track in node.playlist.items) {
                NSLog(@"track title \"%@\", location \"%@\"", track.title, track.location );
            }
        }
    }];
    [[NSUserDefaults standardUserDefaults] setObject:selectedDefaults forKey:@"SelectedPlaylists"];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSLog(@"******** PlaylistSelections init called **********");
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        NSMutableDictionary *selected = [NSMutableDictionary dictionaryWithDictionary:[defaults objectForKey:@"SelectedPlaylists"]];
        if (nil == selected ) {
            selected = [[NSMutableDictionary alloc] init];
        }
        NSMutableDictionary *playlistNodes = [[NSMutableDictionary alloc] init];
        
        NSLog(@"Getting iTunes library info...");
        NSError *error = nil;
        library = [ITLibrary libraryWithAPIVersion:@"1.0" error:&error];
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
                NSNumber *savedState = [selected objectForKey:[i.persistentID stringValue]];
                
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
            if ([node.playlist.name isEqualTo:@"Across The Great Divide"])
                for (ITLibMediaItem *track in node.playlist.items) {
                    NSLog(@"Track %@ at location %@", track.title, track.location);
                }

        }
        
        [playlistTree enumerateTreeUsingBlock:^(PlaylistNode *node, BOOL *stop) {
            if (node.playlist && ([node.selectedState integerValue] != NSOffState)) {
                NSLog(@"selected playlist %@ from defaults.  Contains tracks:", node.playlist.name);
                for (ITLibMediaItem *track in node.playlist.items) {
                    NSLog(@"track title \"%@\", location \"%@\"", track.title, track.location );
                }
            }
            
        }];

    }
    return self;
}

- (void) setNode:(PlaylistNode*) node toSelectedState: (NSInteger) state {
    NSNumber *newState = [NSNumber numberWithInteger:state];
    node.selectedState = newState;
    NSLog(@"selected playlist %@.  Contains tracks:", node.playlist.name);
    for (ITLibMediaItem *track in node.playlist.items) {
        NSLog(@"track title \"%@\", location \"%@\"", track.title, track.location );
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
    return item;
}


- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id) object ForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    NSLog(@"Treeview asked to set column %@ value %@ for item %@. Ignoring.", tableColumn.identifier, object, item);
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
            v.textField.stringValue = [NSString stringWithFormat:@"%@ (%lu tracks)", node.playlist.name, (unsigned long)node.playlist.items.count];
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