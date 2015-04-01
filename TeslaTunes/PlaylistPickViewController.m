//
//  PlaylistPickViewController.m
//  TeslaTunes
//
//  Created by Rob Arnold on 3/29/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import "PlaylistPickViewController.h"
#import "AppDelegate.h"

@interface PlaylistPickViewController ()

@end

@implementation PlaylistPickViewController {
    AppDelegate *theApp;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    theApp = [[NSApplication sharedApplication] delegate];
    self.playlistTreeView.dataSource =theApp.playlists;
}

@end
