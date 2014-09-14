//
//  HanzConvertAppDelegate.h
//  HanzConvert
//
//  Created by Lin Fan on 4/23/11.
//  Copyright 2011 Galaworks Studio. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class AppController;

@interface HanzConvertAppDelegate : NSObject <NSApplicationDelegate>
{
	IBOutlet AppController *appController;
    IBOutlet NSWindow *window;
	IBOutlet NSTextField *extensionsField;
}

@property (assign) IBOutlet NSWindow *window;

@end
