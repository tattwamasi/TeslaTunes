//
//  ViewController.m
//  TeslaTunes
//
//  Created by Rob Arnold on 1/24/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import "ViewController.h"
#import "Receptionist.h"

#import "AppDelegate.h"



@implementation ViewController {
    Receptionist *ccDirReceptionist;
    NSTimer *progressUpdateTimer;
    NSDate *startTime;
    NSDate *stopTime;
    NSDateFormatter *timeFormatter;
    AppDelegate *theApp;
    PlaylistSelections *playlists;
    
}
- (IBAction)checkmarkClicked:(id)sender {
    [self validateControls];
}

- (void) validateControls {
    NSError *theError=nil;
    
    self.doItButton.enabled = self.destinationPath.URL && ((self.copyPlaylists && playlists)
                                                           || (self.copyFolder && [self.sourcePath.URL checkResourceIsReachableAndReturnError:&theError]));
    
    
    // if for some reason we couldn't read the iTunes stuff, then don't enable the copy playlist functionality
    if (! playlists) {
        self.cpPlaylistsButton.enabled = NO;
        self.selectPlaylistsButton.enabled = NO;
    }
    
}

- (IBAction)sourcePathSelected:(NSPathControl *)sender {
    if (!self.ccDirs.isProcessing)
        [self validateControls];
}
- (IBAction)destinationPathSelected:(NSPathControl *)sender {
    if (!self.ccDirs.isProcessing)
        [self validateControls];
}

- (IBAction)StartSelectedAction:(NSButton *)sender {
    if (sender.state) { // it was "do it" when pressed, rather than stop
        [self.ccDirs startOperationOnDir:self.opTypeButton.selectedTag
                  withPlaylistSelections:(self.copyPlaylists? playlists :nil)
                            andSourceDir:(self.copyFolder? self.sourcePath.URL : nil)
                               toDestDir:self.destinationPath.URL];
    } else {
        // stop the operation
        // could take a while to cancel operations, so keep state at stop and disable the button.
        // it'll be reenabled by the isProcesing handler when processing is complete.
        sender.enabled = NO;
        sender.title = @"Stopping";
        //sender.state = NSOnState;
        [self.ccDirs cancelOngoingOperations];
    }
}

-(void) writeReport {
    NSString *ext;
    NSMutableString *report = [[NSMutableString alloc]
        initWithFormat:@"Processing started: %@\nstopped: %@\nduration: %.1f seconds\nExtensions copied/converted:\n", [timeFormatter stringFromDate: startTime], [timeFormatter stringFromDate: stopTime],
            [stopTime timeIntervalSinceDate:startTime]];
    for (ext in self.ccDirs.copiedExtensions) {
        [report appendFormat: @"%@ files copied: %lu\n", ext,[self.ccDirs.copiedExtensions countForObject:ext]];
    }
    [report appendString: @"\nExtensions skipped:\n"];
    for (ext in self.ccDirs.skippedExtensions) {
        [report appendFormat:@"%@ files skipped: %lu\n", ext? ext: @"(no extension)",[self.ccDirs.skippedExtensions countForObject:ext]];
    }
    self.report = report;
    
}

-(void) updateProgress {
    [self.numberOfFilesScannedLabel setIntegerValue: self.ccDirs.filesChecked];
    [self.numberOfFilesToCopyOrConvertLabel setIntegerValue: self.ccDirs.filesToCopyConvert];
    [self.numberOfFilesCopiedOrConvertedLabel setIntegerValue: self.ccDirs.filesCopyConverted];
    [self.numberOfFilesForDeletionLabel setIntegerValue: self.ccDirs.filesMarkedForOrDeleted];
}
-(void) updateProgressTimerFired:(NSTimer *)t {
    [self updateProgress];
}

- (void) isProcessing: (BOOL)flag {
    if (flag) {
        startTime = [NSDate date];
        NSLog(@"Processing started at %@", [timeFormatter stringFromDate: startTime]);
        [self.progressIndicator startAnimation:self];
        self.report = nil;
        self.CCScanResultsPopupItem.enabled=NO;
        [progressUpdateTimer invalidate];
        progressUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                               target:self selector:@selector(updateProgressTimerFired:)
                                                             userInfo:nil repeats:YES];
        // turn off the system's sleep when idle till we're done with the processing
        [theApp setIdleSleepEnabled:NO];
        
        
    } else {
        stopTime = [NSDate date];
        NSLog(@"Processing stopped at %@", [timeFormatter stringFromDate: stopTime]);
        [self.progressIndicator stopAnimation:self];
        [progressUpdateTimer invalidate];
        [self updateProgress];
        [self writeReport];
        self.doItButton.state = 0;
        [self validateControls];
        self.doItButton.title=@"Do it";
        // finally, if there is a scan ready, enable the process already scanned popup item
        // and set the popup to it as the default for the next action
        if (self.ccDirs.scanReady) {
            self.CCScanResultsPopupItem.enabled=YES;
            if (![self.opTypeButton selectItemWithTag:2]) {
                NSLog(@"Couldn't select Process scanned items popup menu item.");
            }
        } else {
            // scan isn't ready, so make sure popup doesn't have "copy/convert the scan results" selected
            if (self.opTypeButton.selectedTag == 2) {
                [self.opTypeButton selectItemWithTag:0];
            }
            self.CCScanResultsPopupItem.enabled=NO;
        }

        [theApp setIdleSleepEnabled:YES];
    }
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    NSLog(@"library changed: %@", change);
}



- (void) viewDidDisappear {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:self.copyFolder forKey:@"copyFolder"];
    [defaults setBool:self.copyPlaylists forKey:@"copyPlaylists"];
    NSInteger defaultTag = self.opTypeButton.selectedTag;
    if (defaultTag == 2) {
        defaultTag = 0; // if we were processing scanned items when quit, set to scan next
    }
    [defaults setInteger:defaultTag forKey:@"opTypeButtonSelection"];
    [defaults setBool:self.ccDirs.hackGenre forKey:@"setPlaylistItemGenreToPlaylistName"];

}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    theApp = [[NSApplication sharedApplication] delegate];
    
    timeFormatter = [[NSDateFormatter alloc] init];
    [timeFormatter setDateStyle:NSDateFormatterMediumStyle];
    [timeFormatter setTimeStyle:NSDateFormatterMediumStyle];
    
    self.ccDirs = [[CopyConvertDirs alloc] init];
    self.ccDirs.hackGenre = [defaults boolForKey:@"setPlaylistItemGenreToPlaylistName"];
    
    self.CCScanResultsPopupItem.enabled=NO;
    ccDirReceptionist = [Receptionist receptionistForKeyPath:@"isProcessing" object:self.ccDirs queue:[NSOperationQueue mainQueue] task:^(NSString *keyPath, id object, NSDictionary *change) {
        if ([change objectForKey:NSKeyValueChangeNewKey] == nil || [change objectForKey:NSKeyValueChangeNewKey] == (id)[NSNull null]) {
            NSLog(@"Receptionist got unexpected change:%@",[change description]);
        }
        else {
            BOOL pFlag =  [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
            [self isProcessing:pFlag];
        }
    }];

    playlists = [[PlaylistSelections alloc] init];
    theApp.playlists = playlists;

    self.copyFolder     = [defaults boolForKey:@"copyFolder"];
    self.copyPlaylists  = [defaults boolForKey:@"copyPlaylists"];
    [self.opTypeButton selectItemWithTag:[defaults integerForKey:@"opTypeButtonSelection"]];
    if (nil == self.sourcePath.URL) {
        self.sourcePath.URL = [playlists getLibrary].musicFolderLocation;
    }
    [self validateControls];
    // TODO:  the below was an attempt at gracefully discovering changes made in iTunes while the
    // app was running.  Alas, seems to not actually do KVO.
    //[[playlists getLibrary] addObserver:self forKeyPath:@"allPlaylists" options:0 context:nil];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

@end
