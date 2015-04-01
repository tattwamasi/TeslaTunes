//
//  AppDelegate.m
//  TeslaTunes
//
//  Created by Rob Arnold on 1/24/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import "AppDelegate.h"


#import <IOKit/pwr_mgt/IOPMLib.h>



@interface AppDelegate ()

@end

@implementation AppDelegate {
    IOPMAssertionID assertionID;
    BOOL idleDisabled;

    
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    self.playlists = [[PlaylistSelections alloc] init];
    
    //[[NSUserDefaultsController sharedUserDefaultsController] setInitialValues:defaults];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
    [self setIdleSleepEnabled:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}


- (BOOL)setIdleSleepEnabled:(BOOL) enable {
    if (enable) {
        if (idleDisabled) {
            IOReturn success = IOPMAssertionRelease(assertionID);
            if (success == kIOReturnSuccess) {
                idleDisabled=NO;
            } else {
                NSLog(@"warning, could not renable system sleep when idle.");
            }
        }
    } else {
        if (!idleDisabled) {
            // kIOPMAssertionTypeNoIdleSleep prevents idle sleep
            //  NOTE: IOPMAssertionCreateWithName limits the string to 128 characters.
            CFStringRef reasonForActivity= CFSTR("Scanning, Copying, and converting songs");
            IOReturn success = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep,
                                                           kIOPMAssertionLevelOn, reasonForActivity, &assertionID);
            idleDisabled = (kIOReturnSuccess == success);
            if (!idleDisabled) {
                NSLog(@"warning, couldn't disable system idle sleep, so system could go to sleep while still processing.");
            }
        }
    }
    return (idleDisabled == !enable);
}


@end
