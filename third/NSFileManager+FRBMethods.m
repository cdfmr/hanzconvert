@implementation NSFileManager (FRBMethods)

- (BOOL)overwriteMoveFileAtPath:(NSString *)src toPath:(NSString *)dst
{
	FSRef dstRef; // <= should be the destination path with filename
	FSRef srcRef; // <= should be the source path with filename
	OSStatus err;
  
	err = FSPathMakeRefWithOptions((UInt8 *)[[dst stringByDeletingLastPathComponent]
											 fileSystemRepresentation],
								   kFSPathMakeRefDoNotFollowLeafSymlink,
								   &dstRef,
								   NULL);
	if (err != noErr)
	{
		NSLog(@"* Error with dst, FSPathMakeRefWithOptions: %ld", (long)err);
		return NO;
	}

	err = FSPathMakeRefWithOptions((UInt8 *)[src fileSystemRepresentation],
								   kFSPathMakeRefDoNotFollowLeafSymlink,
								   &srcRef,
								   NULL);
	if (err != noErr)
	{
		NSLog(@"* Error with src, FSPathMakeRefWithOptions: %ld", (long)err);
		return NO;
	}

	err = FSMoveObjectSync(&srcRef,
						   &dstRef,
						   (CFStringRef)[dst lastPathComponent],
						   NULL,
						   kFSFileOperationOverwrite);
	if (err != noErr)
	{
		NSLog(@"* Error with FSMoveObjectSync, %ld", (long)err);
		return NO;
	}

	return YES;
}

- (BOOL)overwriteCopyFileAtPath:(NSString *)src toPath:(NSString *)dst
{
	FSRef dstRef; // <= should be the destination path with filename
	FSRef srcRef; // <= should be the source path with filename
	OSStatus err;
	
	err = FSPathMakeRefWithOptions((UInt8 *)[[dst stringByDeletingLastPathComponent]
											 fileSystemRepresentation],
								   kFSPathMakeRefDoNotFollowLeafSymlink,
								   &dstRef,
								   NULL);
	if (err != noErr)
	{
		NSLog(@"* Error with dst, FSPathMakeRefWithOptions: %ld", (long)err);
		return NO;
	}
	
	err = FSPathMakeRefWithOptions((UInt8 *)[src fileSystemRepresentation],
								   kFSPathMakeRefDoNotFollowLeafSymlink,
								   &srcRef,
								   NULL);
	if (err != noErr)
	{
		NSLog(@"* Error with src, FSPathMakeRefWithOptions: %ld", (long)err);
		return NO;
	}
	
	err = FSCopyObjectSync(&srcRef,
						   &dstRef,
						   (CFStringRef)[dst lastPathComponent],
						   NULL,
						   kFSFileOperationOverwrite);
	if (err != noErr)
	{
		NSLog(@"* Error with FSMoveObjectSync, %ld", (long)err);
		return NO;
	}
	
	return YES;
}

@end
