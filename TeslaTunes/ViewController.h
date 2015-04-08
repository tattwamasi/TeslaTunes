//
//  ViewController.h
//  TeslaTunes
//
//  Created by Rob Arnold on 1/24/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "CopyConvertDirs.h"
@interface ViewController : NSViewController

@property BOOL copyFolder;
@property BOOL copyPlaylists;

@property (weak) IBOutlet NSPathControl *sourcePath;
@property (weak) IBOutlet NSPathControl *destinationPath;

@property (weak) IBOutlet NSButton *doItButton;
@property (weak) IBOutlet NSPopUpButton *opTypeButton;
@property (weak) IBOutlet NSMenuItem *CCScanResultsPopupItem;

@property NSString *report;

@property (weak) IBOutlet NSTextField *numberOfFilesScannedLabel;
@property (weak) IBOutlet NSTextField *numberOfFilesToCopyOrConvertLabel;
@property (weak) IBOutlet NSTextField *numberOfFilesCopiedOrConvertedLabel;
@property (weak) IBOutlet NSProgressIndicator *progressIndicator;

@property CopyConvertDirs *ccDirs;

@end

