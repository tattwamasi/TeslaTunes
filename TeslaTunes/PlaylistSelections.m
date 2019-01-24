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

bool isPlaylistToDisplay(const ITLibPlaylist* p){
    if (p.visible && !p.master) { //might be interesting
                                  // certain playlist distinguished kinds we know we don't want though
        switch (p.distinguishedKind) {
            case ITLibDistinguishedPlaylistKindMovies:
            case ITLibDistinguishedPlaylistKindTVShows:
            case ITLibDistinguishedPlaylistKindRingtones:
            case ITLibDistinguishedPlaylistKindVoiceMemos:
            case ITLibDistinguishedPlaylistKindMusicVideos:
            case ITLibDistinguishedPlaylistKindLibraryMusicVideos:
            case ITLibDistinguishedPlaylistKindHomeVideos:
            case ITLibDistinguishedPlaylistKindApplications:
                return false;
                break;
            default:
                return true;
                break;
        }
    }
    return false;
}
// while kind is just an enum, it's not in the right order according to how the iTunes UI actually
// displays them.
// Though we can see from the header that the enum is small and the values are small, and therefore
// could just load up an array with sort order values, I'm hesitant since the header could change the
// values assigned to the enums and blow that up
int sortOrderOfPlaylistKind(ITLibPlaylistKind kind) {
    switch (kind) {
        case ITLibPlaylistKindGeniusMix:
            return 1;
        case ITLibPlaylistKindGenius:
            return 2;
        case ITLibPlaylistKindFolder:
            return 3;
        case ITLibPlaylistKindSmart:
            return 4;
        case ITLibPlaylistKindRegular:
            return 5;
        default:
            return 6;
    }
}

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
    NSMutableDictionary *selectedDefaults = [[NSMutableDictionary alloc] init];
    // go through the tree, creating the SelectedPlaylists dictionary, then put it into defaults
    [playlistTree enumerateTreeUsingBlock:^(PlaylistNode *node, BOOL *stop){
        if (node.playlist && ([node.selectedState integerValue] != NSOffState)) {
            [selectedDefaults setObject:node.selectedState
                forKey:[node.playlist.persistentID stringValue]];
        }
    }];
    [[NSUserDefaults standardUserDefaults] setObject:selectedDefaults forKey:@"SelectedPlaylists"];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        NSMutableDictionary *selected = [NSMutableDictionary dictionaryWithDictionary:[defaults objectForKey:@"SelectedPlaylists"]];
        if (nil == selected ) {
            selected = [[NSMutableDictionary alloc] init];
        }
        NSMutableDictionary *playlistNodes = [[NSMutableDictionary alloc] init];
        
        NSError *error = nil;
        library = [ITLibrary libraryWithAPIVersion:@"1.0" error:&error];
        if (!library) {
            NSLog(@"error getting iTunes library: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^(){
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = [NSString stringWithFormat:@"Unable to get iTunes library information"];
                alert.informativeText = @"You can still use the utility to copy folders, but playlist functionality will be disabled.";
                [alert runModal];
            });
            return nil;
        }

        for (ITLibPlaylist *i in library.allPlaylists) {
            if (([i isKindOfClass: [ITLibPlaylist class]]) && isPlaylistToDisplay(i)) {
                NSNumber *savedState = [selected objectForKey:[i.persistentID stringValue]];
                
                PlaylistNode *node = [[PlaylistNode alloc] initWithPlaylist:i
                                        andState: savedState];
                [playlistNodes setObject:node forKey:i.persistentID];
                
            }
        }

        // We do the scan through the playlists twice because I'm not sure if we're guaranteed
        // proper ordering such that a parent would always have been listed before it's children
        // Also, in the event that somehow a parent is not found, or was perhaps marked not visible,
        // marked as master, etc. we'll just root the node at the top level
        //
        // We do however sort the keys such that the playlists are ordered the same way as (as best I can tell)
        // iTunes displays them, which seems to be by kind of playlist (not distiguished kind), and then
        // alphabetical within the type.  Within the section labeled Playlists in the iTunes UI, the kind order
        // seems to be:
        // Genius, Folder, Smart, Regular.  I can't find an example of GeniusMix - I think it is for the ones under
        // the Library section of the list. Note, there are a few distinguished kind != 0 (which is
        // ITLibDistinguishedPlaylistKindNone) playlists that the iTunes UI pulls into the library section, for
        // example the one named Music (which is ITLibDistinguishedPlaylistKindMusic)
        // I don't know algorithmically how to know whether to drop those or not - many of the !=0 ones are sorted
        // into the playlist section, for example the My Top Rated, etc. smart playlists.  So for now, just going to
        // sort them all in.
        //
        
        playlistTree = [[PlaylistNode alloc] initWithPlaylist:nil andState:[NSNumber numberWithInteger:NSOffState]];
        [playlistNodes setObject:playlistTree forKey:[NSNull null]];
        
        NSArray *sortedPlaylistNodes = [playlistNodes keysSortedByValueUsingComparator: ^(PlaylistNode *node1, PlaylistNode *node2) {
            NSAssert( (node1 && node2), @"Sort comparator for playlists was passed a nil node");
            
            // By definition there won't more than one entry with no playlist, and it will be the root node.
            if (!node1.playlist) {
                return (NSComparisonResult)NSOrderedAscending;
            }
            if (!node2.playlist) {
                return (NSComparisonResult)NSOrderedDescending;
            }
            if (sortOrderOfPlaylistKind(node1.playlist.kind) > sortOrderOfPlaylistKind(node2.playlist.kind)) {
                return (NSComparisonResult)NSOrderedDescending;
            }
            if (sortOrderOfPlaylistKind(node1.playlist.kind) < sortOrderOfPlaylistKind(node2.playlist.kind)) {
                return (NSComparisonResult)NSOrderedAscending;
            }
            
            // the playlists are of the same kind, so sort case insensitively alphabetically by name of the playlist
            
            return [node1.playlist.name localizedCaseInsensitiveCompare:node2.playlist.name];
            
        }];
        for (id key in sortedPlaylistNodes) {
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
#if 0
            NSLog(@"Added child playlist %@ parentID %@ to parent %@ id %@",
                  node.playlist.name, node.playlist.parentID,
                  parent.playlist? parent.playlist.name:@"root",
                  parent.playlist?parent.playlist.persistentID:@"Null");
#endif
        }

    }
    return self;
}

- (void) setNode:(PlaylistNode*) node toSelectedState: (NSInteger) state {
    NSNumber *newState = [NSNumber numberWithInteger:state];
    node.selectedState = newState;
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
    //NSLog(@"viewForTableColumn called, tableColumn %@, item = %@", tableColumn.identifier, item);
    
    if (item) {
        PlaylistNode *node = item;
        if (node.children) { // it's a folder containing other playlists and/or folders - let's make the header view

            NSTableCellView *v = [outlineView makeViewWithIdentifier:@"header" owner:self];
            if (!v) {
                NSLog(@"makeView for header failed");
            }
            v.textField.stringValue = node.playlist.name;
            return v;
        } else {
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
