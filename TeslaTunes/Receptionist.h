//
//  Receptionist.h
//  TeslaTunes
//
//  Created by Rob Arnold on 3/9/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#import <Foundation/Foundation.h>
typedef void (^RCTaskBlock)(NSString *keyPath, id object, NSDictionary *change);

@interface Receptionist : NSObject {
    id observedObject;
    NSString *observedKeyPath;
    RCTaskBlock task;
    NSOperationQueue *queue;
}

+ (id)receptionistForKeyPath:(NSString *)path
                      object:(id)obj
                       queue:(NSOperationQueue *)queue
                        task:(RCTaskBlock)task;
@end
