//
//  PlaylistSelections.h
//  TeslaTunes
//
//  Created by Rob Arnold on 3/29/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PlaylistNode;
@interface PlaylistSelections : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>
- (void) setNode:(PlaylistNode*) node toSelectedState: (NSInteger) state;

@end
