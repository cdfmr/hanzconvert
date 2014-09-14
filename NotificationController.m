//
//  NotificationController.m
//  FreeMan
//
//  Created by Lin Fan on 3/12/12.
//  Copyright (c) 2012 Galaworks Studio. All rights reserved.
//

#import "NotificationController.h"
#import "NotificationView.h"

@implementation NotificationController

CWL_SYNTHESIZE_SINGLETON_FOR_CLASS(NotificationController)

- (id)init
{
	// create window
	NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 340, 72)
													styleMask:NSBorderlessWindowMask
													  backing:NSBackingStoreBuffered
														defer:NO]
						autorelease];
	if (!window)
	{
		return nil;
	}
	[window setLevel:NSStatusWindowLevel];
	[window setBackgroundColor:[NSColor clearColor]];
	[window setAlphaValue:1.0];
	[window setOpaque:NO];
	[window setHasShadow:YES];
	[window setIgnoresMouseEvents:YES];
	[window setContentView:[[[NotificationView alloc] initWithFrame:NSZeroRect] autorelease]];
	
	if (!(self = [super initWithWindow:window]))
	{
		return nil;
	}
	
	return self;
}

- (void)dealloc
{
	[closeTimer invalidate];
	[closeTimer release];
	
	[super dealloc];
}

#pragma mark -

- (void)updateWindowFrame
{
	NSWindow *window = [self window];
	NSRect windowRect = [window frame];
	NSRect screenRect = [[window screen] frame];
	windowRect.origin.x = (screenRect.size.width - windowRect.size.width) / 2;
	windowRect.origin.y = 160;
	
	[window setFrame:windowRect display:NO];
}

- (void)showNotificationWindow
{
	NSWindow *window = [self window];
	[self updateWindowFrame];
	[window setAlphaValue:0];
	[window makeKeyAndOrderFront:nil];
	[NSAnimationContext beginGrouping];
	[[NSAnimationContext currentContext] setDuration:0.4];
	[[window animator] setAlphaValue:1];
	[NSAnimationContext endGrouping];
}

- (void)closeNotificationWindow
{
	[NSAnimationContext beginGrouping];
	[[NSAnimationContext currentContext] setDuration:0.2];
	[[[self window] animator] setAlphaValue:0];
	[NSAnimationContext endGrouping];
	
	dispatch_after(dispatch_walltime(NULL, NSEC_PER_SEC * 0.5),
				   dispatch_get_main_queue(),
				   ^{
					   [self close];
				   });
}

- (void)showNotificationWithIcon:(NSImage *)icon
						andTitle:(NSString *)title
					  andMessage:(NSString *)message
				 closeAfterDelay:(float)seconds
{
	[[[self window] contentView] setIcon:icon withTitle:title andMessage:message];
	
	// check whether it is showing
	if (closeTimer)
	{
		[closeTimer invalidate];
		[closeTimer release];
	}
	else
	{
		[self showNotificationWindow];
	}
	
	closeTimer = [[NSTimer scheduledTimerWithTimeInterval:seconds
												   target:self
												 selector:@selector(closeTimerFire:)
												 userInfo:nil
												  repeats:NO] retain];
}

- (void)closeNotification
{
	[closeTimer invalidate];
	[closeTimer release];
	closeTimer = nil;
	
	[self closeNotificationWindow];
}

- (void)closeTimerFire:(NSTimer*)timer
{
	[self closeNotification];
}

@end
