//
//  HintTableHeaderView.m
//  HanzConvert
//
//  Created by Lin Fan on 05/12/2011.
//  Copyright 2011 Galaworks Studio. All rights reserved.
//

#import "HintTableHeaderView.h"

@implementation HintTableHeaderView

- (void)showIconHelp
{
    if (!iconHelpWindow)
	{
		NSTableView *tableView = [self tableView];
		NSUInteger index = [[tableView tableColumns] indexOfObject:
							[tableView tableColumnWithIdentifier:@"status"]];
		if (index == NSNotFound)
		{
			return;
		}
		
		NSRect rect = [self headerRectOfColumn:index];
		NSPoint point = NSMakePoint(NSMidX(rect), NSMaxY(rect));
		point = [self convertPoint:point toView:nil];
		iconHelpWindow = [[MAAttachedWindow alloc] initWithView:iconHelpView
												attachedToPoint:point
													   inWindow:[self window]
														 onSide:MAPositionBottomRight
													 atDistance:2.0];
		[iconHelpWindow setBorderWidth:1.0];
		[iconHelpWindow setArrowBaseWidth:16.0];
		[iconHelpWindow setArrowHeight:8.0];
		
        [[self window] addChildWindow:iconHelpWindow ordered:NSWindowAbove];
    }
}

- (void)closeIconHelp
{
	if (iconHelpWindow)
	{
		[[self window] removeChildWindow:iconHelpWindow];
		[iconHelpWindow orderOut:self];
		[iconHelpWindow release];
		iconHelpWindow = nil;
	}
}

- (void)awakeFromNib
{
	NSTrackingArea *trackingArea = 
		 [[[NSTrackingArea alloc] initWithRect:[self visibleRect]
									   options:NSTrackingMouseEnteredAndExited |
											   NSTrackingMouseMoved |
											   NSTrackingInVisibleRect |
											   NSTrackingActiveAlways
										 owner:self
									  userInfo:nil] autorelease];
	[self addTrackingArea:trackingArea];
}

- (void)mouseMoved:(NSEvent *)theEvent
{
	NSTableView *tableView = [self tableView];
	NSUInteger index = [[tableView tableColumns] indexOfObject:
						[tableView tableColumnWithIdentifier:@"status"]];
	if (index == NSNotFound)
	{
		return;
	}
	
	NSRect rect = [self headerRectOfColumn:index];
	NSPoint point = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	if (NSPointInRect(point, rect))
	{
		[self showIconHelp];
	}
	else
	{
		[self closeIconHelp];
	}
}

- (void)mouseExited:(NSEvent *)theEvent
{
	[self closeIconHelp];
}

@end
