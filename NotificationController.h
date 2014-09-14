//
//  NotificationController.h
//  FreeMan
//
//  Created by Lin Fan on 3/12/12.
//  Copyright (c) 2012 Galaworks Studio. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "CWLSynthesizeSingleton.h"

@interface NotificationController : NSWindowController
{
	NSTimer *closeTimer;
}

- (void)showNotificationWithIcon:(NSImage *)icon
						andTitle:(NSString *)title
					  andMessage:(NSString *)message
				 closeAfterDelay:(float)seconds;
- (void)closeNotification;

CWL_DECLARE_SINGLETON_FOR_CLASS(NotificationController)

@end
