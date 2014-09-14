//
//  HanzConvertAppDelegate.m
//  HanzConvert
//
//  Created by Lin Fan on 4/23/11.
//  Copyright 2011 Galaworks Studio. All rights reserved.
//

#import "HanzConvertAppDelegate.h"
#import "HCFileStateIconTransformer.h"
#import "AppController.h"

@implementation HanzConvertAppDelegate

@synthesize window;

+ (void)initialize
{
	// initialize value transformers used throughout the application bindings
	NSValueTransformer *transformer = [[HCFileStateIconTransformer alloc] init];
	[NSValueTransformer setValueTransformer:transformer forName:@"HCFileStateIcon"];
	[transformer release];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed: (NSApplication *)app
{
	return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app
{
	// save defaults when user terminate program from preference dialog directly
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:[extensionsField stringValue] forKey:PrefKeyExtensions];
	return YES;
}

- (void)application:(NSApplication *)sender
		  openFiles:(NSArray *)filenames
{
	// open files with dropping files on application icon
	if ([window attachedSheet] == nil)
	{
		int oldCount = [[[appController fileController] content] count];
		[appController openFiles:filenames position:NULL];
		[appController selectToEndFrom: oldCount];
	}
}

@end
