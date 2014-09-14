//
//  NotificationView.m
//  FreeMan
//
//  Created by Lin Fan on 3/12/12.
//  Copyright (c) 2012 Galaworks Studio. All rights reserved.
//

#import "NotificationView.h"

#define MARGIN			12
#define ICON_SIZE		48
#define ICON_SPACE		12
#define TITLE_FONT		12
#define MESSAGE_FONT	12
#define TEXT_SPACE		8

@implementation NotificationView

- (void)dealloc
{
	[icon release];
	[title release];
	[message release];
	
	[super dealloc];
}

- (void)setIcon:(NSImage *)aIcon withTitle:(NSString *)aTitle andMessage:(NSString *)aMessage
{
	if (icon != aIcon)
	{
		[icon release];
		icon = [aIcon retain];
	}
	
	if (message != aMessage)
	{
		[message release];
		message = [aMessage retain];
	}
	
	if (title != aTitle)
	{
		[title release];
		title = [aTitle retain];
	}
	
	[self setNeedsDisplay:YES];
}

- (CGFloat)heightOfText:(NSString *)text withFont:(NSFont *)font inMaxWidth:(CGFloat)maxWidth
{
	if (!text || [text length] == 0)
	{
		return 0;
	}
	
	NSTextStorage *textStorage = [[NSTextStorage alloc] initWithString:text];
	NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
	NSTextContainer *textContainer = [[NSTextContainer alloc] init];
	[layoutManager addTextContainer:textContainer];
	[textStorage addLayoutManager:layoutManager];
	[textStorage setFont:font];
	[textContainer setContainerSize:NSMakeSize(maxWidth, FLT_MAX)];
	[layoutManager glyphRangeForTextContainer:textContainer];
	NSSize size = [layoutManager usedRectForTextContainer:textContainer].size;
	[textStorage release];
	[layoutManager release];
	[textContainer release];
	
	return size.height;
}

- (CGFloat)textHeight
{
	float textWidth = NSWidth([self bounds]) - MARGIN * 2 - ICON_SIZE - ICON_SPACE;
	float titleHeight = [self heightOfText:title
								  withFont:[NSFont boldSystemFontOfSize:TITLE_FONT]
								inMaxWidth:textWidth];
	float messageHeight = [self heightOfText:message
									withFont:[NSFont systemFontOfSize:MESSAGE_FONT]
								  inMaxWidth:textWidth];
	
	return titleHeight + messageHeight + TEXT_SPACE;
}
	
- (NSSize)drawText:(NSString *)text withFont:(NSFont *)font atPoint:(NSPoint)point
{
	if (!text || [text length] == 0)
	{
		return NSZeroSize;
	}
	
	float textWidth = NSWidth([self bounds]) - MARGIN * 2 - ICON_SIZE - ICON_SPACE;
	NSTextStorage *textStorage = [[NSTextStorage alloc] initWithString:text];
	NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
	NSTextContainer *textContainer = [[NSTextContainer alloc] init];
	[layoutManager addTextContainer:textContainer];
	[textStorage addLayoutManager:layoutManager];
	[textStorage setFont:font];
	[textStorage setForegroundColor:[NSColor whiteColor]];
	[textContainer setContainerSize:NSMakeSize(textWidth, FLT_MAX)];
	NSRange glyphRange = [layoutManager glyphRangeForTextContainer:textContainer];
	[layoutManager drawGlyphsForGlyphRange:glyphRange atPoint:point];
	NSSize size = [layoutManager usedRectForTextContainer:textContainer].size;
	[textStorage release];
	[layoutManager release];
	[textContainer release];
	
	return size;
}

- (BOOL)isFlipped
{
	return YES;
}

- (void)drawRect:(NSRect)rect
{
	rect = [self bounds];
	
	// fill background
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:8 yRadius:8];
	[[NSColor colorWithCalibratedWhite:0.145 alpha:0.608] setFill];
	[path fill];
	
	// stroke border
	[[NSColor whiteColor] setStroke];
	[path setLineWidth:2.0];
	[path setClip];
	[path stroke];

	// draw icon
	[icon setFlipped:YES];
	NSRect iconRect = NSMakeRect(MARGIN, (NSHeight(rect) - ICON_SIZE) / 2, ICON_SIZE, ICON_SIZE);
	[icon drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
	[icon setFlipped:NO];
	
	// calculate
	NSPoint point = NSMakePoint(MARGIN + ICON_SIZE + ICON_SPACE,
								(NSHeight(rect) - [self textHeight]) / 2.0);
	
	// draw title
	NSSize titleSize = [self drawText:title
							 withFont:[NSFont boldSystemFontOfSize:TITLE_FONT]
							  atPoint:point];
	
	// draw message
	point.y += (titleSize.height + TEXT_SPACE);
	[self drawText:message withFont:[NSFont systemFontOfSize:MESSAGE_FONT] atPoint:point];
}

@end
