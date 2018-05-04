//
//  Receptionist.m
//  TeslaTunes
//
//  Created by Rob Arnold on 3/9/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import "Receptionist.h"

@implementation Receptionist
+ (id)receptionistForKeyPath:(NSString *)path object:(id)obj queue:(NSOperationQueue *)queue task:(RCTaskBlock)task {
    Receptionist *receptionist = [Receptionist new];
    receptionist->task = [task copy];
    receptionist->observedKeyPath = [path copy];
    receptionist->observedObject = obj;
    receptionist->queue = queue;
    [obj addObserver:receptionist forKeyPath:path
             options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:0];
    return receptionist;
}



- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    [queue addOperationWithBlock:^{
        self->task(keyPath, object, change);
    }];
}

@end
