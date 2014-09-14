//
//  HCFileItem.m
//  HanzConvert
//
//  Created by Lin Fan on 4/24/11.
//  Copyright 2011 Galaworks Studio. All rights reserved.
//

#import "HCFileItem.h"

@implementation HCFileItem

@synthesize state;
@synthesize filename;
@synthesize relative;

- (id)init
{
	return [self initWithFilename:@"" andRelative:@""];
}

- (id)initWithFilename:(NSString *)newFile andRelative:(NSString *)relativeName
{
	[super init];
	state = HC_FS_NONE;
	filename = [[NSString alloc] initWithString:newFile];
	relative = [[NSString alloc] initWithString:relativeName];
	
	return self;
}

- (void)dealloc
{
	[filename release];
	[relative release];
	[super dealloc];
}

- (BOOL)isEqual:(HCFileItem *)otherItem
{
	return [filename isEqualToString:[otherItem filename]];
}

@end
