//
//  HCFileStateIconTransformer.m
//  HanzConvert
//
//  Created by Lin Fan on 4/25/11.
//  Copyright 2011 Galaworks Studio. All rights reserved.
//

#import "HCFileStateIconTransformer.h"
#import "HCFileItem.h"

@implementation HCFileStateIconTransformer

+ (Class)transformedValueClass
{
	return [NSImage class];
}

+ (BOOL)allowsReverseTransformation
{
	return YES;
}

- (id)transformedValue:(id)value
{
	NSString *imageFile;
	switch ([value intValue])
	{
		case HC_FS_SUCCESS:
			imageFile = @"accept";
			break;
		case HC_FS_FAIL:
			imageFile = @"reject";
			break;
		case HC_FS_CONVERT:
			imageFile = @"control_play_blue";
			break;
		case HC_FS_ERRDETECT:
			imageFile = @"error";
			break;
		default:
			imageFile = @"bullet_blue";
			break;
	}
	return [NSImage imageNamed:imageFile];
}

@end
