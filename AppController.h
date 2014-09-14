//
//  AppController.h
//  HanzConvert
//
//  Created by Lin Fan on 4/24/11.
//  Copyright 2011 Galaworks Studio. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "HintTableHeaderView.h"
#import "HCFileItem.h"

extern NSString * const PrefKeyExtensions;
extern NSString * const PrefKeySearchRecursively;
extern NSString * const PrefKeyWriteUTF8BOM;
extern NSString * const PrefKeyInputEncoding;
extern NSString * const PrefKeyOutputEncoding;
extern NSString * const PrefKeyCharacterSet;
extern NSString * const PrefKeyOutputFolder;
extern NSString * const PrefKeyDetectorDataSize;
extern NSString * const PrefKeyDetectorConfidence;
extern NSString * const PrefKeySecurityBookmark;

@interface AppController : NSObject <NSOpenSavePanelDelegate>
{
	IBOutlet NSWindow *window;
	IBOutlet NSArrayController *fileController;
	IBOutlet NSTableView *tableView;
	IBOutlet NSPopUpButton *outputFolderButton;
	IBOutlet NSPopUpButton *characterSetButton;
	IBOutlet NSPanel *preferencePanel;
	IBOutlet NSTextField *extensionsField;
	IBOutlet NSWindow *progressSheet;
	IBOutlet NSProgressIndicator *progressBar;
	IBOutlet NSTextField *progressText;
	IBOutlet NSPanel *aboutBox;
	IBOutlet NSTextField *versionLabel;
	IBOutlet NSTextField *copyrightLabel;
	IBOutlet HintTableHeaderView *tableHeaderView;

	NSMutableArray *fileItems;
	BOOL cancelThread;
	int currentOpenPanel;
	
	NSURL *bookmarkUrl;
}

@property (readonly) NSArrayController *fileController;
@property (readwrite) BOOL cancelThread;

- (IBAction)addFiles:(id)sender;
- (IBAction)addFolder:(id)sender;
- (IBAction)remove:(id)sender;
- (IBAction)clear:(id)sender;
- (IBAction)openBackup:(id)sender;
- (IBAction)clearBackup:(id)sender;
- (IBAction)changeOutputEncoding:(id)sender;
- (IBAction)chooseOutputFolder:(id)sender;
- (IBAction)doubleClickTableView:(id)sender;
- (IBAction)convert:(id)sender;
- (IBAction)cancel:(id)sender;
- (IBAction)showHelp:(id)sender;
- (IBAction)writeReview:(id)sender;

- (void)centerWindowInScreen:(NSWindow *)wnd;
- (NSArray *)extensionsFromUserDefaults;
- (void)addFile:(NSString *)filename
	   relative:(NSString *)relative
	   position:(int *)position;
- (void)addFile:(NSString *)filename
	   relative:(NSString *)relative
  withExtension:(NSArray *)extensions
	   position:(int *)position;
- (void)addFilesInFolder:(NSString *)folder
		   withExtension:(NSArray *)extensions
				position:(int *)position;
- (void)openFiles:(NSArray *)filenames
		 position:(int *)position;
- (void)selectToEndFrom:(int)from;

- (BOOL)validateInputEncoding:(int)inputEncoding
			andOutputEncoding:(int)outputEncoding
			  andCharacterSet:(int)characterSet;
+ (BOOL)getCconvEncoding:(NSString **)fromEncoding
			  toEncoding:(NSString **)toEncoding
				useIconv:(BOOL *)useIconv
		   inputEncoding:(int)inputEncoding
		  outputEncoding:(int)outputEncoding
			characterSet:(int)characterSet;
+ (void)convertThreadProc:(NSDictionary *)parameters;
+ (BOOL)convertFile:(HCFileItem *)fileItem
	targetDirectory:(NSString *)targetDirectory
	   fromEncoding:(NSString *)fromEncoding
		 toEncoding:(NSString *)toEncoding
		   useIconv:(BOOL)useIconv
		 directCopy:(BOOL)directCopy;
+ (BOOL)convertFile:(NSString *)inFile
			 toFile:(NSString *)outFile
	   fromEncoding:(NSString *)fromEncoding
		 toEncoding:(NSString *)toEncoding
		   useIconv:(BOOL)useIconv;
+ (BOOL)iconvConvertFile:(NSFileHandle *)input
				  toFile:(NSFileHandle *)output
			fromEncoding:(NSString *)fromEncoding
			  toEncoding:(NSString *)toEncoding;
+ (BOOL)cconvConvertFile:(NSFileHandle *)input
				  toFile:(NSFileHandle *)output
			fromEncoding:(NSString *)fromEncoding
			  toEncoding:(NSString *)toEncoding;
+ (int)detectEncoding:(NSString *)filename;

@end
