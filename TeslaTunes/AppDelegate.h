//
//  AppDelegate.h
//  TeslaTunes
//
//  Created by Rob Arnold on 1/24/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PlaylistSelections.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property PlaylistSelections *playlists;
- (BOOL)setIdleSleepEnabled:(BOOL) enable;


@end

