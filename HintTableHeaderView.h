//
//  HintTableHeaderView.h
//  HanzConvert
//
//  Created by Lin Fan on 05/12/2011.
//  Copyright 2011 Galaworks Studio. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MAAttachedWindow.h"

@interface HintTableHeaderView : NSTableHeaderView
{
	IBOutlet NSView *iconHelpView;
    MAAttachedWindow *iconHelpWindow;
}

- (void)showIconHelp;
- (void)closeIconHelp;

@end
