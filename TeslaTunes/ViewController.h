//
//  ViewController.h
//  TeslaTunes
//
//  Created by Rob Arnold on 1/24/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "CopyConvertDirs.h"

@interface ViewController : NSViewController <NSTableViewDataSource>

@property (unsafe_unretained) IBOutlet NSTextView *resultsView;
@property NSURL *sourceDirURL;
@property NSURL *destinationDirURL;
@property (weak) IBOutlet NSButton *doItButton;
@property (weak) IBOutlet NSPopUpButton *opTypeButton;

@property NSString *report;


@property CopyConvertDirs *ccDirs;

@end

