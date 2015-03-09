//
//  ViewController.m
//  TeslaTunes
//
//  Created by Rob Arnold on 1/24/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import "ViewController.h"

@implementation ViewController

// when either source or destination changes, disable popup menu item copy already scanned

- (IBAction)sourceSelected:(NSPathControl *)sender {
    NSLog(@"source selected: src %@ ; dest %@", _sourceDirURL, _destinationDirURL);
}
- (IBAction)destinationSeleted:(NSPathControl *)sender {
    NSLog(@"dest selected: src %@ ; dest %@", _sourceDirURL, _destinationDirURL);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    NSLog(@"Keypath = %@", keyPath);
    if ([keyPath isEqual: @"isProcessing"]) {
        // if value is true then clear extensions handled/skipped because we're still collecting them,
        // if false, then format the extension reports, set the Do it button state to 0 ("Do it" rather than stop)
        if (self.ccDirs.isProcessing) {
            self.report = nil;
        } else {
            NSString *ext;
            NSMutableString *report = [[NSMutableString alloc] initWithString:@"Extensions copied/converted:\n"];
            for (ext in self.ccDirs.copiedExtensions) {
                [report appendFormat: @"%@ files copied: %lu\n", ext,[self.ccDirs.copiedExtensions countForObject:ext]];
            }
            [report appendString: @"\nExtensions skipped:\n"];
            for (ext in self.ccDirs.skippedExtensions) {
                [report appendFormat:@"%@ files skipped: %lu\n", ext? ext: @"(no extension)",[self.ccDirs.skippedExtensions countForObject:ext]];
            }
            self.report = report;
            self.doItButton.state = 0;
            // finally, if the operations was a scan operation set the popup to ProcessScanned as the default for the next action.  It should be marked enabled via databinding to scanReady.
            if (self.ccDirs.scanReady) {
                if (![self.opTypeButton selectItemWithTag:2]) {
                    NSLog(@"Couldn't select Process scanned items popup menu item.");
                }
            } else {
                NSLog(@"turning off copy/convert already selected button.");
                // scan isn't ready, so make sure popup doesn't have "copy/convert the scan results" selected
                if (self.opTypeButton.selectedTag == 2) {
                    [self.opTypeButton selectItemWithTag:0];
                }
            }
        }
    }

    //[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}
- (IBAction)StartSelectedAction:(NSButton *)sender {
    NSLog(@"sender.state = %ld", (long)sender.state);
    NSLog(@"popup btn value: %@ and tag %ld.", self.opTypeButton, self.opTypeButton.selectedTag);
    if (sender.state) { // it was "do it" when pressed, rather than stop
        [self.ccDirs startOperationOnDir:self.opTypeButton.selectedTag withSourceDir:_sourceDirURL andDestDir:_destinationDirURL];
    } else {// stop the operation
        [self.ccDirs cancelOngoingOperations];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
    self.ccDirs = [[CopyConvertDirs alloc] init];
    [self.ccDirs addObserver:self forKeyPath:@"isProcessing" options:NSKeyValueObservingOptionNew context:nil];
    
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

@end
