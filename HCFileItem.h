//
//  HCFileItem.h
//  HanzConvert
//
//  Created by Lin Fan on 4/24/11.
//  Copyright 2011 Galaworks Studio. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum _HCFileState
{
	HC_FS_NONE,
	HC_FS_SUCCESS,
	HC_FS_FAIL,
	HC_FS_CONVERT,
	HC_FS_ERRDETECT
} HCFileState;

@interface HCFileItem : NSObject
{
	HCFileState state;
	NSString *filename;
	NSString *relative;
}

- (id)initWithFilename:(NSString *)newFile andRelative:(NSString *)relativeName;

@property (readwrite) HCFileState state;
@property (readwrite, copy) NSString *filename;
@property (readwrite, copy) NSString *relative;

@end