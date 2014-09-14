@interface NSFileManager (FRBMethods)

- (BOOL)overwriteMoveFileAtPath:(NSString *)src toPath:(NSString *)dst;
- (BOOL)overwriteCopyFileAtPath:(NSString *)src toPath:(NSString *)dst;

@end
