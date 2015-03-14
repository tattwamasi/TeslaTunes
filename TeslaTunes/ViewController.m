//
//  ViewController.m
//  TeslaTunes
//
//  Created by Rob Arnold on 1/24/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import "ViewController.h"
#import "Receptionist.h"
@implementation ViewController {
    Receptionist *ccDirReceptionist;
    NSTimer *progressUpdateTimer;
    NSDate *startTime;
    NSDate *stopTime;
    NSDateFormatter *timeFormatter;
}

// when either source or destination changes, disable popup menu item copy already scanned

- (IBAction)StartSelectedAction:(NSButton *)sender {
    NSLog(@"sender.state = %ld", (long)sender.state);
    NSLog(@"popup btn value: %@ and tag %ld.", self.opTypeButton, self.opTypeButton.selectedTag);
    if (sender.state) { // it was "do it" when pressed, rather than stop
        [self.ccDirs startOperationOnDir:self.opTypeButton.selectedTag
                           withSourceDir:self.sourcePath.URL
                              andDestDir:self.destinationPath.URL];
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
        
    } else {
        stopTime = [NSDate date];
        NSLog(@"Processing stopped at %@", [timeFormatter stringFromDate: stopTime]);
        [self.progressIndicator stopAnimation:self];
        [progressUpdateTimer invalidate];
        [self updateProgress];
        [self writeReport];
        self.doItButton.state = 0;
        self.doItButton.enabled=1;
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
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
    timeFormatter = [[NSDateFormatter alloc] init];
    [timeFormatter setDateStyle:NSDateFormatterMediumStyle];
    [timeFormatter setTimeStyle:NSDateFormatterMediumStyle];
    
    self.ccDirs = [[CopyConvertDirs alloc] init];
    //[self.ccDirs addObserver:self forKeyPath:@"isProcessing" options:NSKeyValueObservingOptionNew context:nil];
    self.CCScanResultsPopupItem.enabled=NO;
    ccDirReceptionist = [Receptionist receptionistForKeyPath:@"isProcessing" object:self.ccDirs queue:[NSOperationQueue mainQueue] task:^(NSString *keyPath, id object, NSDictionary *change) {
        if ([change objectForKey:NSKeyValueChangeNewKey] == nil || [change objectForKey:NSKeyValueChangeNewKey] == (id)[NSNull null]) {
            NSLog(@"Receptionist got unexpected change:%@",[change description]);
        }
        else {
            BOOL pFlag =  [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
            NSLog(@"Receptionist got new value description:%@, type %s, value %i",[[change objectForKey:NSKeyValueChangeNewKey] description],
              [[change objectForKey:NSKeyValueChangeNewKey] objCType], pFlag);
            [self isProcessing:pFlag];
        }
    }];

    
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

@end
