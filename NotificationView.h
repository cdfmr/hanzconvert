//
//  NotificationView.h
//  FreeMan
//
//  Created by Lin Fan on 3/12/12.
//  Copyright (c) 2012 Galaworks Studio. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NotificationView : NSView
{
	NSImage *icon;
	NSString *title;
	NSString *message;
}

- (void)setIcon:(NSImage *)aIcon withTitle:(NSString *)aTitle andMessage:(NSString *)aMessage;

@end
