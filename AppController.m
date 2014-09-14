//
//  AppController.m
//  HanzConvert
//
//  Created by Lin Fan on 4/24/11.
//  Copyright 2011 Galaworks Studio. All rights reserved.
//

#import "AppController.h"
#import "HCFileItem.h"
#import "NSFileManager+FRBMethods.h"
#import "cconv/cconv.h"
#import "UniversalDetector/UniversalDetector.h"
#import "NSFileManager+DirectoryLocations.h"
#import "NSBundle+OBCodeSigningInfo.h"
#import "NotificationController.h"

// buffer size
#define IN_BUFFER_SIZE 10240
#define OUT_BUFFER_SIZE (IN_BUFFER_SIZE * 4 + 8)

// Mac App Store ID
NSString * const MASId = @"442107196";

// Placeholder of empty output folder
NSString * const EMPTY_OUTPUT = @"-";

// user defaults keys
NSString * const PrefKeyExtensions		   = @"pref_key_extensions";
NSString * const PrefKeySearchRecursively  = @"pref_key_search_recursively";
NSString * const PrefKeyWriteUTF8BOM	   = @"pref_key_write_utf8_bom";
NSString * const PrefKeyInputEncoding	   = @"pref_key_input_encoding";
NSString * const PrefKeyOutputEncoding	   = @"pref_key_output_encoding";
NSString * const PrefKeyCharacterSet	   = @"pref_key_character_set";
NSString * const PrefKeyOutputFolder	   = @"pref_key_output_folder";
NSString * const PrefKeyDetectorDataSize   = @"pref_key_detector_data_size";
NSString * const PrefKeyDetectorConfidence = @"pref_key_detector_confidence";
NSString * const PrefKeySecurityBookmark   = @"pref_key_security_bookmark";

// toolbar item identifiers
NSString * const ToolbarItemClear	= @"id_toolbaritem_clear";
NSString * const ToolbarItemConvert = @"id_toolbaritem_convert";

// encoding constants
enum
{
	ENCODING_UTF8,
	ENCODING_GB18030,
	ENCODING_BIG5,
	ENCODING_AUTO
};
enum
{
	CHARSET_KEEP,
	CHARSET_SIMPLIFIED,
	CHARSET_TRADITIONAL
};
enum
{
	OUTPUT_INPLACE,
	OUTPUT_CUSTOM
};

// open panel identification
enum
{
	OPENPANEL_ADDFOLDER,
	OPENPANEL_CHOOSEOUTPUT
};

#pragma mark -

static int getSystemVersion()
{
	SInt32 version = 0;
	Gestalt(gestaltSystemVersion, &version);
	return version;
}

static void OpenFolderWithAppleScriptBecauseTheSandboxIsTerrible(NSString *path)
{
	FSRef ref;
	bzero(&ref, sizeof(ref));
	if (FSPathMakeRef((UInt8 *)[path fileSystemRepresentation], &ref, NULL) != noErr)
	{
		return;
	}
	
	static const OSType signature = 'MACS';
	AppleEvent event = {typeNull, nil};
	AEBuildError builderror;
	
	AEDesc filedesc;
	AEInitializeDesc(&filedesc);
	if (AECoercePtr(typeFSRef, &ref, sizeof(ref), typeAlias, &filedesc) != noErr)
	{
		return;
	}
	
	if (AEBuildAppleEvent(kCoreEventClass, kAEOpenDocuments, typeApplSignature, &signature,
						  sizeof(OSType), kAutoGenerateReturnID, kAnyTransactionID, &event,
						  &builderror, "'----':(@)", &filedesc) != noErr)
	{
		return;
	}
	
	AEDisposeDesc(&filedesc);
	
    AppleEvent reply = {typeNull, nil};
	
	AESendMessage(&event, &reply, kAENoReply, kAEDefaultTimeout);
	
	AEDisposeDesc(&reply);
	AEDisposeDesc(&event);
	
	NSArray *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:
					 @"com.apple.finder"];
	[[apps objectAtIndex:0] activateWithOptions:0];
}

#pragma mark -

@implementation AppController

@synthesize fileController;
@synthesize cancelThread;

NSString *backupFolderRoot;
NSString *backupFolderCurrent;

#pragma mark init/dealloc

+ (void)initialize
{
	// register user defaults
	NSMutableDictionary *defaultValues = [NSMutableDictionary dictionary];
	[defaultValues setObject:@"txt, htm, html" forKey:PrefKeyExtensions];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:PrefKeySearchRecursively];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:PrefKeyWriteUTF8BOM];
	[defaultValues setObject:[NSNumber numberWithInt:ENCODING_AUTO] forKey:PrefKeyInputEncoding];
	[defaultValues setObject:[NSNumber numberWithInt:ENCODING_UTF8] forKey:PrefKeyOutputEncoding];
	[defaultValues setObject:[NSNumber numberWithInt:CHARSET_KEEP] forKey:PrefKeyCharacterSet];
	[defaultValues setObject:EMPTY_OUTPUT forKey:PrefKeyOutputFolder];
	[defaultValues setObject:[NSNumber numberWithInt:2] forKey:PrefKeyDetectorDataSize];
	[defaultValues setObject:[NSNumber numberWithInt:90] forKey:PrefKeyDetectorConfidence];
	[[NSUserDefaults standardUserDefaults] registerDefaults:defaultValues];
}

- (id)init
{
	if (!(self = [super init]))
	{
		return nil;
	}
	
	fileItems = [[NSMutableArray alloc] init];
	
	// retrieve and create backup folder
	backupFolderRoot = [[[NSFileManager defaultManager] applicationSupportDirectory]
						stringByAppendingPathComponent:@"Backup"];
	[backupFolderRoot retain];
	[[NSFileManager defaultManager] createDirectoryAtPath:backupFolderRoot
							  withIntermediateDirectories:YES
											   attributes:nil
													error:nil];
	if ([[NSBundle mainBundle] ob_isSandboxed])
	{
		[[NSFileManager defaultManager] createFileAtPath:[backupFolderRoot 
														  stringByAppendingPathComponent:@".dir"]
												contents:nil
											  attributes:nil];
	}

	return self;
}

- (void)dealloc
{
	if (bookmarkUrl)
	{
		[bookmarkUrl stopAccessingSecurityScopedResource];
		[bookmarkUrl release];
	}
	
	[fileItems release];
	[backupFolderRoot release];
	[backupFolderCurrent release];
	
	[super dealloc];
}

#pragma mark ui management

- (void)centerWindowInScreen:(NSWindow *)wnd
{
	NSRect screenRect = [[wnd screen] frame];
	NSRect windowRect = [wnd frame];
	windowRect.origin.x = (screenRect.size.width - windowRect.size.width) / 2;
	windowRect.origin.y = (screenRect.size.height - windowRect.size.height) / 2;
	[wnd setFrame:windowRect display:NO];
}

- (void)awakeFromNib
{
	// center windows
	[self centerWindowInScreen:window];
	[self centerWindowInScreen:preferencePanel];
	[self centerWindowInScreen:aboutBox];
	
	// setup about box
	NSBundle *bundle = [NSBundle mainBundle];
	NSString *version = [NSString stringWithFormat:@"%@ %@ (%@)",
						 NSLocalizedString(@"VERSION", @"Version"),
						 [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
						 [bundle objectForInfoDictionaryKey:@"CFBundleVersion"]];
	[versionLabel setStringValue:version];
	NSString *copyright = [NSString stringWithFormat:NSLocalizedString(@"COPYRIGHT", nil),
						   [[NSCalendarDate calendarDate] yearOfCommonEra]];
	[copyrightLabel setStringValue:copyright];

	// update convert setting controls
	[self changeOutputEncoding:self];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *outputFolder = [defaults stringForKey:PrefKeyOutputFolder];
	if ([outputFolder length] > 0)
	{
		if (![outputFolder isEqualToString:EMPTY_OUTPUT])
		{
			if ([[NSBundle mainBundle] ob_isSandboxed])
			{
				[defaults setObject:EMPTY_OUTPUT forKey:PrefKeyOutputFolder];
				if (getSystemVersion() >= 0x1073)
				{
					NSData *bookmark = [defaults objectForKey:PrefKeySecurityBookmark];
					BOOL bookmarkDataIsStale;
					bookmarkUrl = [NSURL URLByResolvingBookmarkData:bookmark
															options:
															NSURLBookmarkResolutionWithSecurityScope
													  relativeToURL:nil
												bookmarkDataIsStale:&bookmarkDataIsStale
															  error:nil];
					if (bookmarkUrl)
					{
						[bookmarkUrl startAccessingSecurityScopedResource];
						[bookmarkUrl retain];
						outputFolder = [bookmarkUrl path];
						[defaults setObject:outputFolder forKey:PrefKeyOutputFolder];
						[[outputFolderButton itemAtIndex:OUTPUT_CUSTOM] setTitle:outputFolder];
					}
				}
			}
			else
			{
				[[outputFolderButton itemAtIndex:OUTPUT_CUSTOM] setTitle:outputFolder];
			}
		}
		
		[outputFolderButton selectItemAtIndex:OUTPUT_CUSTOM];
	}
	
	// setup table view
	[tableHeaderView setFrame:[[tableView headerView] frame]];
	[tableView setHeaderView:tableHeaderView];
	[tableView setAllowsColumnReordering:NO];
	[tableView setTarget:self];
	[tableView setDoubleAction:@selector(doubleClickTableView:)];
	[tableView registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if ([menuItem action] == @selector(remove:))
	{
		return [fileController canRemove] && [window attachedSheet] == nil;
	}

	if ([menuItem action] == @selector(clear:))
	{
		return [fileItems count] > 0 && [window attachedSheet] == nil;
	}

	if ([menuItem action] == @selector(convert:))
	{
		if ([window attachedSheet] != nil)
		{
			return NO;
		}
		for (HCFileItem *fileItem in fileItems)
		{
			if ([fileItem state] == HC_FS_NONE ||
				[fileItem state] == HC_FS_FAIL ||
				[fileItem state] == HC_FS_ERRDETECT)
			{
				return YES;
			}
		}
		return NO;
	}

	return YES;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)toolbarItem
{
	if ([[toolbarItem itemIdentifier] isEqualToString:ToolbarItemClear])
	{
		return [fileItems count] > 0;
	}

	if ([[toolbarItem itemIdentifier] isEqualToString:ToolbarItemConvert])
	{
		for (HCFileItem *fileItem in fileItems)
		{
			if ([fileItem state] == HC_FS_NONE ||
				[fileItem state] == HC_FS_FAIL ||
				[fileItem state] == HC_FS_ERRDETECT)
			{
				return YES;
			}
		}
		return NO;
	}

	return NO;
}

- (void)windowDidResignKey:(NSNotification *)notification
{
	// close icon help window
	if ([notification object] == window)
	{
		[tableHeaderView closeIconHelp];
	}
	
	// save user defaults even user didn't press Enter in file extensions field
	if ([notification object] == preferencePanel)
	{
		[[NSUserDefaults standardUserDefaults]
		 setObject:[extensionsField stringValue] forKey:PrefKeyExtensions];
	}
}

- (void)windowWillClose:(NSNotification *)notification
{
	[[NotificationController sharedNotificationController] closeNotification];
	
	// Save security-scoped bookmark
	if ([[NSBundle mainBundle] ob_isSandboxed] && getSystemVersion() >= 0x1073)
	{
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		NSData *bookmark = nil;
		NSString *output = [defaults stringForKey:PrefKeyOutputFolder];
		if ([output length] > 0 && ![output isEqualToString:EMPTY_OUTPUT])
		{
			NSURL *url = [NSURL fileURLWithPath:output isDirectory:YES];
			bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
					 includingResourceValuesForKeys:nil
									  relativeToURL:nil
											  error:nil];
		}
		[defaults setObject:bookmark forKey:PrefKeySecurityBookmark];
	}
}

- (IBAction)changeOutputEncoding:(id)sender
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults integerForKey:PrefKeyOutputEncoding] == ENCODING_BIG5)
	{
		[defaults setInteger:CHARSET_TRADITIONAL forKey:PrefKeyCharacterSet];
		[characterSetButton setEnabled:NO];
	}
	else
	{
		[characterSetButton setEnabled:YES];
	}
}

- (void)chooseOutputFolderPanelDidEnd:(NSOpenPanel *)openPanel
						   returnCode:(int)returnCode
						  contextInfo:(void *)contextInfo
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if (returnCode == NSOKButton)
	{
		NSString *path = [[openPanel URL] path];
		[defaults setObject:path forKey:PrefKeyOutputFolder];
		[[outputFolderButton itemAtIndex:OUTPUT_CUSTOM] setTitle:path];
		
		if (contextInfo != NULL)
		{
			[self performSelector:@selector(convert:) withObject:nil afterDelay:0.2];
		}
	}
	else
	{
		if ([[defaults stringForKey:PrefKeyOutputFolder] length] == 0)
		{
			[outputFolderButton selectItemAtIndex:OUTPUT_INPLACE];
		}
	}
}

- (IBAction)chooseOutputFolder:(id)sender
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([outputFolderButton indexOfSelectedItem] == 0)
    {
        [defaults setObject:@"" forKey:PrefKeyOutputFolder];
        [[outputFolderButton itemAtIndex:1] setTitle:NSLocalizedString(@"CHOOSE_FOLDER", nil)];
    }
	else
	{
		currentOpenPanel = OPENPANEL_CHOOSEOUTPUT;
		NSOpenPanel *panel = [NSOpenPanel openPanel];
		[panel setPrompt:NSLocalizedString(@"CHOOSE", @"Choose")];
		[panel setDelegate:self];
		[panel setCanChooseFiles:NO];
		[panel setCanChooseDirectories:YES];
		[panel setCanCreateDirectories:YES];
		NSString *path = [defaults stringForKey:PrefKeyOutputFolder];
		if ([path length] > 0 && ![path isEqualToString:EMPTY_OUTPUT])
		{
			[panel setDirectoryURL:[NSURL fileURLWithPath:path]];
		}
		[panel beginSheetModalForWindow:window completionHandler:^(NSInteger returnCode)
		{
			[self chooseOutputFolderPanelDidEnd:panel
									 returnCode:returnCode
									contextInfo:NULL];
		}];
	}
}

- (IBAction)showHelp:(id)sender
{
	NSURL *helpURL = [NSURL URLWithString:NSLocalizedString(@"HELP_URL", @"Homepage")];
	[[NSWorkspace sharedWorkspace] openURL:helpURL];
}

- (IBAction)writeReview:(id)sender
{
	NSString *masPage = [NSString stringWithFormat:@"macappstore://itunes.apple.com/app/id%@?mt=12",
												   MASId];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:masPage]];
}

#pragma mark file management

- (NSArray *)extensionsFromUserDefaults
{
	// get user defaults
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSMutableArray *extensions = [NSMutableArray arrayWithArray:
								  [[defaults stringForKey:PrefKeyExtensions]
								   componentsSeparatedByString: @","]];

	// adjust
	int i = 0;
	while (i < [extensions count])
	{
		NSString *extension = [extensions objectAtIndex:i];
		extension = [extension stringByTrimmingCharactersInSet:
					 [NSCharacterSet whitespaceCharacterSet]];
		if ([extension length] > 0)
		{
			[extensions replaceObjectAtIndex:i withObject:[extension lowercaseString]];
			i++;
		}
		else
		{
			[extensions removeObjectAtIndex:i];
		}
	}

	// default value
	if ([extensions count] == 0)
	{
		[extensions addObject:@"txt"];
	}

	return extensions;
}

- (void)addFile:(NSString *)filename relative:(NSString *)relative position:(int *)position
{
	BOOL isDirectory;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if ([fileManager fileExistsAtPath:filename isDirectory:&isDirectory] && !isDirectory)
	{
		HCFileItem *fileItem = [[HCFileItem alloc] initWithFilename:filename
														andRelative:relative];
		if (![fileItems containsObject:fileItem])
		{
			if (position)
			{
				[fileController insertObject:fileItem atArrangedObjectIndex:*position];
				(*position)++;
			}
			else
			{
				[fileController addObject:fileItem];
			}

		}
		[fileItem release];
	}
}

- (void)addFile:(NSString *)filename
	   relative:(NSString *)relative
  withExtension:(NSArray *)extensions
	   position:(int *)position
{
	NSString *extension = [[filename pathExtension] lowercaseString];
	if ([extensions indexOfObject:extension] != NSNotFound)
	{
		[self addFile:filename relative:relative position:position];
	}
}

- (void)addFilesInFolder:(NSString *)folder
		   withExtension:(NSArray *)extensions
				position:(int *)position
{
	if ([[NSUserDefaults standardUserDefaults] boolForKey:PrefKeySearchRecursively])
	{
		NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:folder];
		NSString *filename;
		while (filename = [dirEnum nextObject])
		{
			[self addFile:[NSString stringWithFormat:@"%@/%@", folder, filename]
				 relative:[NSString stringWithFormat:@"%@/%@", [folder lastPathComponent], filename]
			withExtension:extensions
				 position:position];
		}
	}
	else
	{
		NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder
																			 error:NULL];
		for (NSString *filename in files)
		{
			[self addFile:[NSString stringWithFormat:@"%@/%@", folder, filename]
				 relative:[NSString stringWithFormat:@"%@/%@", [folder lastPathComponent], filename]
			withExtension:extensions
				 position:position];
		}
	}
}

- (void)openFiles:(NSArray *)filenames position:(int *)position
{
	NSArray *extensions = [self extensionsFromUserDefaults];
	for (NSString *filename in filenames)
	{
		NSFileManager *fileManager = [NSFileManager defaultManager];
		BOOL isDirectory;
		if ([fileManager fileExistsAtPath:filename isDirectory:&isDirectory])
		{
			if (isDirectory)
			{
				[self addFilesInFolder:filename withExtension:extensions position:position];
			}
			else
			{
				[self addFile:filename
					 relative:[filename lastPathComponent]
				withExtension:extensions
					 position:position];
			}
		}
	}
}

- (IBAction)addFiles:(id)sender
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setPrompt:NSLocalizedString(@"ADD", @"Add")];
	[panel setAllowsMultipleSelection:YES];
	[panel setAllowedFileTypes:[self extensionsFromUserDefaults]];
	[panel beginSheetModalForWindow:window completionHandler:^(NSInteger returnCode)
	{
		if (returnCode == NSOKButton)
		{
			int oldCount = [fileItems count];
			for (NSURL *URL in [panel URLs])
			{
				[self addFile:[URL path] relative:[[URL path] lastPathComponent] position:NULL];
			}
			[self selectToEndFrom:oldCount];
		}
	}];
}

- (IBAction)addFolder:(id)sender
{
	currentOpenPanel = OPENPANEL_ADDFOLDER;
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setPrompt:NSLocalizedString(@"ADD", @"Add")];
	[panel setDelegate:self];
	[panel setCanChooseFiles:NO];
	[panel setCanChooseDirectories:YES];
	[panel beginSheetModalForWindow:window completionHandler:^(NSInteger returnCode)
	{
		if (returnCode == NSOKButton)
		{
			int oldCount = [fileItems count];
			NSArray *extensions = [self extensionsFromUserDefaults];
			[self addFilesInFolder:[[panel URL] path] withExtension:extensions position:NULL];
			[self selectToEndFrom:oldCount];
		}
	}];
}

- (BOOL)panel:(id)sender
  validateURL:(NSURL *)url
		error:(NSError **)outError
{
	// forbid adding root folder
	if (currentOpenPanel == OPENPANEL_ADDFOLDER)
	{
		if ([url isEqual:[NSURL fileURLWithPath:@"/"]])
		{
			if (outError)
			{
				NSString *errMsg = NSLocalizedString(@"NO_ROOT_FOLDER", nil);
				NSDictionary *eDict = [NSDictionary dictionaryWithObject:errMsg
																  forKey:
																NSLocalizedFailureReasonErrorKey];
				*outError = [NSError errorWithDomain:NSOSStatusErrorDomain
												code:0
											userInfo:eDict];
			}
			return NO;
		}
	}
	
	// check write permission of output folder
	else if (currentOpenPanel == OPENPANEL_CHOOSEOUTPUT &&
			 ![[NSBundle mainBundle] ob_isSandboxed])
	{
		if (![[NSFileManager defaultManager] isWritableFileAtPath:[url path]])
		{
			if (outError)
			{
				NSString *errMsg = NSLocalizedString(@"NO_WRITE_PERMISSION", nil);
				NSDictionary *eDict = [NSDictionary dictionaryWithObject:errMsg
																  forKey:
																NSLocalizedFailureReasonErrorKey];
				*outError = [NSError errorWithDomain:NSOSStatusErrorDomain
												code:0
											userInfo:eDict];
			}
			return NO;
		}
	}

	return YES;
}

- (IBAction)remove:(id)sender
{
	[fileController remove:self];
}

- (IBAction)clear:(id)sender
{
	[fileController removeObjectsAtArrangedObjectIndexes:
	 [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [fileItems count])]];
	// the following line can remove all objects too, but it's slow
	// [[self mutableArrayValueForKey:@"fileItems"] removeAllObjects];

	// avoid twinkle of clear button
	if ([sender isKindOfClass:[NSToolbarItem class]])
	{
		NSToolbarItem *toolbarItem = sender;
		[toolbarItem setEnabled:NO];
	}
}

- (IBAction)openBackup:(id)sender
{
	NSString *folder = backupFolderRoot;
	
	BOOL isDirectory;
	if (backupFolderCurrent &&
		[[NSFileManager defaultManager] fileExistsAtPath:backupFolderCurrent
											 isDirectory:&isDirectory] &&
		isDirectory)
	{
		folder = backupFolderCurrent;
	}

	if ([[NSBundle mainBundle] ob_isSandboxed])
	{
		NSString *file = folder;
		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSDirectoryEnumerator *dirEnum = [fileManager enumeratorAtPath:folder];
		NSString *fileName;
		if ((fileName = [dirEnum nextObject]) != nil)
		{
			file = [folder stringByAppendingPathComponent:fileName];
		}
		[[NSWorkspace sharedWorkspace] selectFile:file inFileViewerRootedAtPath:@""];
	}
	else
	{
		[[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:folder]];
	}
}

- (IBAction)clearBackup:(id)sender
{
	NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"CONFIRM", nil)
									 defaultButton:NSLocalizedString(@"DELETE", @"Delete")
								   alternateButton:NSLocalizedString(@"CANCEL", @"Cancel")
									   otherButton:nil
						 informativeTextWithFormat:NSLocalizedString(@"CLEAR_CONFIRM", nil)];
	[alert setAlertStyle:NSWarningAlertStyle];
	[alert beginSheetModalForWindow:window
					  modalDelegate:self
					 didEndSelector:@selector(clearBackupAlertDidEnd:returnCode:contextInfo:)
						contextInfo:NULL];
}

- (void)clearBackupAlertDidEnd:(NSAlert *)alert
					returnCode:(NSInteger)returnCode
				   contextInfo:(void *)contextInfo
{
	if (returnCode != NSAlertDefaultReturn)
	{
		return;
	}
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSDirectoryEnumerator *dirEnum = [fileManager enumeratorAtPath:backupFolderRoot];
	NSString *fileName;
	while (fileName = [dirEnum nextObject])
	{
		NSError *err = nil;
		if (![fileName isEqualToString:@".dir"])
		{
			NSString *filePath = [backupFolderRoot stringByAppendingPathComponent:fileName];
			BOOL result = [fileManager removeItemAtPath:filePath error:&err];
			if (!result && err)
			{
				NSLog(@"Oops: %@", err);
			}
		}
	}
}

- (void)selectToEndFrom:(int)from
{
	int count = [fileItems count];
	if (count > from)
	{
//		[fileController setSelectionIndexes:[NSIndexSet indexSetWithIndexesInRange:
//											 NSMakeRange(from, count - from)]];
		[tableView scrollRowToVisible:count - 1];
	}
}

- (IBAction)doubleClickTableView:(id)sender
{
	// open clicked file
	NSArray *selectedItems = [fileController selectedObjects];
	if ([selectedItems count] == 1)
	{
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		HCFileItem *fileItem = [selectedItems objectAtIndex:0];
		NSString *filename = [fileItem filename];
		NSString *outputFolder = [defaults objectForKey:PrefKeyOutputFolder];
		if ([fileItem state] == HC_FS_SUCCESS &&
			[outputFolder length] > 0 &&
			![outputFolder isEqualToString:EMPTY_OUTPUT])
		{
			NSString *target = [outputFolder stringByAppendingPathComponent:
								[fileItem relative]];
			if ([[NSFileManager defaultManager] fileExistsAtPath:target])
			{
				filename = target;
			}
		}
		[[NSWorkspace sharedWorkspace] openFile:filename];
	}
}

#pragma mark drag & drop

- (NSDragOperation)tableView:(NSTableView*)tv
				validateDrop:(id <NSDraggingInfo>)info
				 proposedRow:(NSInteger)row
	   proposedDropOperation:(NSTableViewDropOperation)op
{
	return [window attachedSheet] == nil ? NSDragOperationCopy : NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)aTableView
	   acceptDrop:(id <NSDraggingInfo>)info
			  row:(NSInteger)row
	dropOperation:(NSTableViewDropOperation)operation
{
	NSPasteboard *pboard = [info draggingPasteboard];
	NSArray *filenames = [pboard propertyListForType:NSFilenamesPboardType];
	int begin = row;
	int end = row;
	[self openFiles:filenames position:&end];
	if (end > begin)
	{
		[fileController setSelectionIndexes:[NSIndexSet indexSetWithIndexesInRange:
											 NSMakeRange(begin, end - begin)]];
		[tableView scrollRowToVisible:end - 1];
	}
	[NSApp activateIgnoringOtherApps:YES];
	return YES;
}

#pragma mark convert

- (BOOL)validateInputEncoding:(int)inputEncoding
			andOutputEncoding:(int)outputEncoding
			  andCharacterSet:(int)characterSet
{
	// error checking
	BOOL error = NO;
	NSString *errorMessage;
	if ((inputEncoding == outputEncoding) &&
		(characterSet == CHARSET_KEEP || inputEncoding == ENCODING_BIG5))
	{
		error = YES;
		errorMessage = NSLocalizedString(@"NOTNEED_CONVERT",
					   @"Converting without changing encoding and character set is not needed.");
	}
	else if (outputEncoding == ENCODING_BIG5 &&
			 characterSet != CHARSET_TRADITIONAL)
	{
		error = YES;
		errorMessage = NSLocalizedString(@"BIG5_ONLY_TRAD",
					   @"Only traditional character set is available for BIG-5 encoding.");
	}
	
	// popup error message
	if (error)
	{
		NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"BAD_SETTINGS", nil)
										 defaultButton:NSLocalizedString(@"OK", @"OK")
									   alternateButton:nil
										   otherButton:nil
							 informativeTextWithFormat:@"%@", errorMessage];
		[alert setAlertStyle:NSCriticalAlertStyle];
		[alert beginSheetModalForWindow:window
						  modalDelegate:self
						 didEndSelector:NULL
							contextInfo:NULL];
		return NO;
	}
	
	return YES;
}

+ (BOOL)getCconvEncoding:(NSString **)fromEncoding
			  toEncoding:(NSString **)toEncoding
				useIconv:(BOOL *)useIconv
		   inputEncoding:(int)inputEncoding
		  outputEncoding:(int)outputEncoding
			characterSet:(int)characterSet;
{
	NSAssert(fromEncoding != NULL && toEncoding != NULL && useIconv != NULL,
			 @"Output parameters can not be null.");
	
	// need not to convert
	if ((inputEncoding == outputEncoding) &&
		(characterSet == CHARSET_KEEP || inputEncoding == ENCODING_BIG5))
	{
		return NO;
	}
	if (outputEncoding == ENCODING_BIG5 && characterSet != CHARSET_TRADITIONAL)
	{
		return NO;
	}

	// whether use iconv directly
	*useIconv = (characterSet == CHARSET_KEEP ||
				 (inputEncoding == ENCODING_BIG5 &&
				  characterSet == CHARSET_TRADITIONAL));

	// get from encoding
	switch (inputEncoding)
	{
		case ENCODING_BIG5:
			*fromEncoding = @"BIG5";
			break;
		case ENCODING_GB18030:
			*fromEncoding = @"GB18030";
			break;
		default:
			*fromEncoding = @"UTF-8";
			break;
	}

	// get to encoding
	if (*useIconv)
	{
		switch (outputEncoding)
		{
			case ENCODING_BIG5:
				*toEncoding = @"BIG5";
				break;
			case ENCODING_GB18030:
				*toEncoding = @"GB18030";
				break;
			default:
				*toEncoding = @"UTF-8";
				break;
		}
	}
	else
	{
		switch (outputEncoding)
		{
			case ENCODING_BIG5:
				*toEncoding = @"BIG5";
				break;
			case ENCODING_GB18030:
				*toEncoding = (characterSet == CHARSET_TRADITIONAL) ?
							  @"GB-HANT": @"GB-HANS";
				break;
			default:
				*toEncoding = (characterSet == CHARSET_TRADITIONAL) ?
							  @"UTF8-TW": @"UTF8-CN";
				break;
		}
	}

	return YES;
}

- (IBAction)convert:(id)sender
{
	// validate ui status
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	int inputEncoding = [defaults integerForKey:PrefKeyInputEncoding];
	int outputEncoding = [defaults integerForKey:PrefKeyOutputEncoding];
	int characterSet = [defaults integerForKey:PrefKeyCharacterSet];
	if (![self validateInputEncoding:inputEncoding
				   andOutputEncoding:outputEncoding
					 andCharacterSet:characterSet])
	{
		return;
	}
	
	// get convert settings (delay detecting for auto detect mode)
	NSString *fromEncoding = @"";
	NSString *toEncoding = @"";
	BOOL useIconv = NO;
	if (inputEncoding != ENCODING_AUTO)
	{
		if (![AppController getCconvEncoding:&fromEncoding
								  toEncoding:&toEncoding
									useIconv:&useIconv
							   inputEncoding:inputEncoding
							  outputEncoding:outputEncoding
								characterSet:characterSet])
		{
			return;
		}
	}

	// choose output folder
	NSString *outputFolder = [defaults stringForKey:PrefKeyOutputFolder];
	if ([outputFolder isEqualToString:EMPTY_OUTPUT])
	{
		currentOpenPanel = OPENPANEL_CHOOSEOUTPUT;
		NSOpenPanel *panel = [NSOpenPanel openPanel];
		[panel setPrompt:NSLocalizedString(@"SAVE", @"Save")];
		[panel setDelegate:self];
		[panel setCanChooseFiles:NO];
		[panel setCanChooseDirectories:YES];
		[panel setCanCreateDirectories:YES];
		[panel beginSheetModalForWindow:window completionHandler:^(NSInteger returnCode)
		{
			[self chooseOutputFolderPanelDidEnd:panel
									 returnCode:returnCode
									contextInfo:panel];
		}];
		return;
	}
	
	// check output folder
	if ([outputFolder length] > 0)
	{
		// create output folder
		NSError *error;
		if (![[NSFileManager defaultManager] createDirectoryAtPath:outputFolder
									   withIntermediateDirectories:YES
														attributes:nil
															 error:&error])
		{
			NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"ERR_OUTPUT_FOLDER",
														   @"Can't create output folder")
											 defaultButton:NSLocalizedString(@"OK", @"OK")
										   alternateButton:nil
											   otherButton:nil
								 informativeTextWithFormat:@"%@", [error localizedDescription]];
			[alert setAlertStyle:NSCriticalAlertStyle];
			[alert beginSheetModalForWindow:window
							  modalDelegate:self
							 didEndSelector:NULL
								contextInfo:NULL];
			return;
		}
		
		// check write permission
		if (![[NSFileManager defaultManager] isWritableFileAtPath:outputFolder])
		{
			NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"ERR_OUTPUT_FILE",
												           @"Can't create output file")
											 defaultButton:NSLocalizedString(@"OK", @"OK")
										   alternateButton:nil
											   otherButton:nil
								 informativeTextWithFormat:
									NSLocalizedString(@"NO_WRITE_PERMISSION_OUTPUT",
									@"You don't have permission to save files in the folder %@."),
															outputFolder];
			[alert setAlertStyle:NSCriticalAlertStyle];
			[alert beginSheetModalForWindow:window
							  modalDelegate:self
							 didEndSelector:NULL
								contextInfo:NULL];
			return;
		}
	}

	// open progress sheet
	int fileCount = 0;
	for (HCFileItem *fileItem in fileItems)
	{
		if ([fileItem state] == HC_FS_NONE ||
			[fileItem state] == HC_FS_FAIL ||
			[fileItem state] == HC_FS_ERRDETECT)
		{
			fileCount++;
		}
	}
	[progressBar setMaxValue:fileCount];
	[progressBar setDoubleValue:0.0];
	[progressText setStringValue:@""];
	[NSApp beginSheet:progressSheet
	   modalForWindow:window
		modalDelegate:nil
	   didEndSelector:NULL
		  contextInfo:NULL];
	
	// get backup folder
	[backupFolderCurrent release];
	backupFolderCurrent = [backupFolderRoot stringByAppendingPathComponent:
						   [[NSDate date] descriptionWithCalendarFormat:@"%Y-%m-%d %H-%M-%S"
															   timeZone:nil
																 locale:nil]];
	[backupFolderCurrent retain];
	
	// start thread
	NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
	[parameters setObject:self forKey:@"instance"];
	[parameters setObject:outputFolder forKey:@"output"];
	[parameters setObject:fromEncoding forKey:@"from"];
	[parameters setObject:toEncoding forKey:@"to"];
	[parameters setObject:[NSNumber numberWithBool:useIconv] forKey:@"iconv"];
	[NSThread detachNewThreadSelector:@selector(convertThreadProc:)
							 toTarget:[AppController class]
						   withObject:parameters];
}

- (IBAction)cancel:(id)sender
{
	cancelThread = YES;
}

- (void)updateProgressUI:(NSDictionary *)parameters
{
	NSString *filename = [parameters objectForKey:@"filename"];
	int index = [[parameters objectForKey:@"index"] intValue];
	double progress = [[parameters objectForKey:@"progress"] doubleValue];
	[tableView scrollRowToVisible:index];
	[progressText setStringValue:filename];
	[progressBar setDoubleValue:progress];
}

- (void)closeProgressSheet:(NSDictionary *)parameters
{
	[NSApp endSheet:progressSheet];
	[progressSheet orderOut:self];
	
	// show notification
	if (![window isKeyWindow] && ![[parameters objectForKey:@"error"] boolValue])
	{
		NSString *title = NSLocalizedString(@"CONVERT_SUCCESS_TITLE", @"Finished");
		NSString *description = NSLocalizedString(@"CONVERT_SUCCESS",
												  @"All files were converted successfully.");
		[[NotificationController sharedNotificationController] showNotificationWithIcon:
															[NSImage imageNamed:@"hanzconvert.icns"]
																			   andTitle:title
																			 andMessage:description
																		closeAfterDelay:4.0];
	}

	// warning box
	if ([[parameters objectForKey:@"error"] boolValue])
	{
		NSAlert *alert = [NSAlert alertWithMessageText:
						  NSLocalizedString(@"CONVERT_ERROR_TITLE", @"Bad News")
										 defaultButton:
						  NSLocalizedString(@"OK", @"OK")
									   alternateButton:nil
										   otherButton:nil
							 informativeTextWithFormat:
						  NSLocalizedString(@"CONVERT_ERROR",
					@"Not all files were converted successfully, please check convert settings.")];
		[alert setAlertStyle:NSCriticalAlertStyle];
		[alert beginSheetModalForWindow:window
						  modalDelegate:self
						 didEndSelector:NULL
							contextInfo:NULL];
	}
}

+ (void)convertThreadProc:(NSDictionary *)parameters
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	BOOL error = NO;
	
	// get user defaults
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	int inputEncoding = [defaults integerForKey:PrefKeyInputEncoding];
	int outputEncoding = [defaults integerForKey:PrefKeyOutputEncoding];
	int characterSet = [defaults integerForKey:PrefKeyCharacterSet];
	
	// get convert argument
	AppController *appController = [parameters objectForKey:@"instance"];
	NSString *outputFolder = [parameters objectForKey:@"output"];
	NSString *fromEncoding = [parameters objectForKey:@"from"];
	NSString *toEncoding = [parameters objectForKey:@"to"];
	BOOL useIconv = [[parameters objectForKey:@"iconv"] boolValue];
	
	// convert one by one
	[appController setCancelThread:NO];
	int progress = 0;
	int index = 0;
	for (HCFileItem *fileItem in [[appController fileController] arrangedObjects])
	{
		if ([appController cancelThread])
		{
			break;
		}
		
		if ([fileItem state] == HC_FS_NONE ||
			[fileItem state] == HC_FS_FAIL ||
			[fileItem state] == HC_FS_ERRDETECT)
		{
			[fileItem setState:HC_FS_CONVERT];
			NSMutableDictionary *uiParams = [NSMutableDictionary dictionary];
			[uiParams setObject:[fileItem filename] forKey:@"filename"];
			[uiParams setObject:[NSNumber numberWithInt:index] forKey:@"index"];
			[uiParams setObject:[NSNumber numberWithInt:progress]
						 forKey:@"progress"];
			[appController performSelectorOnMainThread:@selector(updateProgressUI:)
											withObject:uiParams
										 waitUntilDone:YES];
			
			BOOL fileError = NO;
			BOOL needConvert = YES;
			
			if (inputEncoding == ENCODING_AUTO)
			{
				int fileEncoding = [self detectEncoding:[fileItem filename]];
				if (fileEncoding == -1)
				{
					fileError = YES;
					[fileItem setState:HC_FS_ERRDETECT];
				}
				else
				{
					needConvert = [AppController getCconvEncoding:&fromEncoding
													   toEncoding:&toEncoding
														 useIconv:&useIconv
													inputEncoding:fileEncoding
												   outputEncoding:outputEncoding
													 characterSet:characterSet];
				}
			}
			
			if (!fileError)
			{
				fileError = ![AppController convertFile:fileItem
										targetDirectory:outputFolder
										   fromEncoding:fromEncoding
											 toEncoding:toEncoding
											   useIconv:useIconv
											 directCopy:!needConvert];
				[fileItem setState:fileError ? HC_FS_FAIL : HC_FS_SUCCESS];
			}
			
			if (fileError)
			{
				error = YES;
			}
			
			[uiParams setObject:[NSNumber numberWithInt:++progress] forKey:@"progress"];
			[appController performSelectorOnMainThread:@selector(updateProgressUI:)
											withObject:uiParams
										 waitUntilDone:YES];
		}
		
		index++;
	}
	
	// close progress sheet
	NSMutableDictionary *resultParams =
	  [NSMutableDictionary dictionaryWithObject:[NSNumber numberWithBool:error]
										 forKey:@"error"];
	[appController performSelectorOnMainThread:@selector(closeProgressSheet:)
									withObject:resultParams
								 waitUntilDone:NO];
	
	[pool drain];
}

+ (BOOL)convertFile:(HCFileItem *)fileItem
	targetDirectory:(NSString *)targetDirectory
	   fromEncoding:(NSString *)fromEncoding
		 toEncoding:(NSString *)toEncoding
		   useIconv:(BOOL)useIconv
		 directCopy:(BOOL)directCopy
{
	NSString *inFile = [fileItem filename];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	BOOL backup = [targetDirectory length] == 0 ||
			      [inFile isEqualToString:
				   [targetDirectory stringByAppendingPathComponent:[fileItem relative]]];

	if (backup)
	{
		NSString *backupFile = [backupFolderCurrent stringByAppendingPathComponent:
								[fileItem relative]];
		NSString *backupFolder = [backupFile stringByDeletingLastPathComponent];
		
		// create backup folder
		BOOL isDirectory;
		BOOL exists = [fileManager fileExistsAtPath:backupFolder isDirectory:&isDirectory];
		if (exists && !isDirectory)
		{
			NSLog(@"Can not create backup folder %@", backupFolder);
			return NO;
		}
		if (!exists)
		{
			if (![fileManager createDirectoryAtPath:backupFolder
						withIntermediateDirectories:YES
										 attributes:nil
											  error:nil])
			{
				NSLog(@"Can not create backup folder %@", backupFolder);
				return NO;
			}
		}
		
		// backup file
		if (directCopy)
		{
			[fileManager overwriteCopyFileAtPath:inFile toPath:backupFile];
			return YES;
		}
		if (![fileManager overwriteMoveFileAtPath:inFile toPath:backupFile])
		{
			NSLog(@"Can not create backup file %@", inFile);
			return NO;
		}
		
		// convert
		if (![AppController convertFile:backupFile
								 toFile:inFile
						   fromEncoding:fromEncoding
							 toEncoding:toEncoding
							   useIconv:useIconv])
		{
			// restore backup
			if (![fileManager overwriteMoveFileAtPath:backupFile toPath:inFile])
			{
				NSLog(@"Can not restore from backup file %@", inFile);
			}
			return NO;
		}
	}
	else
	{
		NSString *outFile = [targetDirectory stringByAppendingPathComponent:[fileItem relative]];
		NSString *outFolder = [outFile stringByDeletingLastPathComponent];
		
		// Create output folder
		BOOL isDirectory;
		BOOL exists = [fileManager fileExistsAtPath:outFolder isDirectory:&isDirectory];
		if (exists && !isDirectory)
		{
			NSLog(@"Can not create output folder %@", outFolder);
			return NO;
		}
		if (!exists)
		{
			if (![fileManager createDirectoryAtPath:outFolder
						withIntermediateDirectories:YES
										 attributes:nil
											  error:nil])
			{
				NSLog(@"Can not create output folder %@", outFolder);
				return NO;
			}
		}
		
		BOOL success = directCopy ?
					   [fileManager overwriteCopyFileAtPath:inFile toPath:outFile] :
					   [AppController convertFile:inFile
										   toFile:outFile
									 fromEncoding:fromEncoding
									   toEncoding:toEncoding
										 useIconv:useIconv];
		if (!success)
		{
			[fileManager removeItemAtPath:outFile error:NULL];
			return NO;
		}
	}

	return YES;
}

+ (BOOL)convertFile:(NSString *)inFile
			 toFile:(NSString *)outFile
	   fromEncoding:(NSString *)fromEncoding
		 toEncoding:(NSString *)toEncoding
		   useIconv:(BOOL)useIconv
{
	// open input file
	NSFileHandle *input = [NSFileHandle fileHandleForReadingAtPath:inFile];
	if (input == nil)
	{
		NSLog(@"Can not open input file %@", inFile);
		return NO;
	}
	
	// skip utf-8 bom
	if ([fromEncoding isEqualToString:@"UTF-8"])
	{
		NSData *bomData = [input readDataOfLength:3];
		const unsigned char *bom = [bomData bytes];
		if ([bomData length] < 3 || !(bom[0] == 0xEF && bom[1] == 0xBB && bom[2] == 0xBF))
		{
			[input seekToFileOffset:0];
		}
	}

	// create output file
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if ([fileManager fileExistsAtPath:outFile])
	{
		if (![[NSWorkspace sharedWorkspace]
			performFileOperation:NSWorkspaceRecycleOperation
						  source:[outFile stringByDeletingLastPathComponent]
					 destination:@""
						   files:[NSArray arrayWithObject:[outFile lastPathComponent]]
							 tag:0])
		{
			NSLog(@"Can not delete existing file %@", outFile);
			return NO;
		}
	}
	if (![fileManager createFileAtPath:outFile contents:nil attributes:nil])
	{
		NSLog(@"Can not create output file %@", outFile);
		return NO;
	}

	// open output file
	NSFileHandle *output = [NSFileHandle fileHandleForWritingAtPath:outFile];
	if (output == nil)
	{
		NSLog(@"Can not open output file %@", outFile);
		return NO;
	}
	
	// write utf-8 bom
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults boolForKey:PrefKeyWriteUTF8BOM] &&
		[defaults integerForKey:PrefKeyOutputEncoding] == ENCODING_UTF8)
	{
		unsigned char bom[3];
		bom[0] = 0xEF; bom[1] = 0xBB; bom[2] = 0xBF;
		@try
		{
			[output writeData:[NSData dataWithBytesNoCopy:bom
												   length:3
											 freeWhenDone:NO]];
		}
		@catch (NSException *e)
		{
			NSLog(@"Write bom error: %@, reason: %@", [e name], [e reason]);
			return NO;
		}
	}

	return useIconv ?
		[AppController iconvConvertFile:input
								 toFile:output
						   fromEncoding:fromEncoding
							 toEncoding:toEncoding] :
		[AppController cconvConvertFile:input
								 toFile:output
						   fromEncoding:fromEncoding
							 toEncoding:toEncoding];
}

+ (BOOL)iconvConvertFile:(NSFileHandle *)input
				  toFile:(NSFileHandle *)output
			fromEncoding:(NSString *)fromEncoding
			  toEncoding:(NSString *)toEncoding
{
	// initialize convert engine
	iconv_t conv = iconv_open([toEncoding UTF8String],
							  [fromEncoding UTF8String]);
	if (conv == (iconv_t)(-1))
	{
		NSLog(@"Can not initialize iconv.");
		return NO;
	}
	int one = 1;
	iconvctl(conv, ICONV_SET_DISCARD_ILSEQ, &one);

	// loop converting
	size_t outputSize = 0;
	char outBuffer[OUT_BUFFER_SIZE];
	while (YES)
	{
		// read data
		NSData *inData;
		@try
		{
			inData = [input readDataOfLength:IN_BUFFER_SIZE];

			// reach eof
			if ([inData length] == 0)
			{
				break;
			}
		}
		@catch (NSException *e)
		{
			NSLog(@"Read error: %@, reason: %@", [e name], [e reason]);
			iconv_close(conv);
			return NO;
		}

		// convert
		char *inPointer = (char *)[inData bytes];
		char *outPointer = outBuffer;
		size_t inBufferRest = [inData length];
		size_t outBufferRest = sizeof(outBuffer);
		if (iconv(conv, &inPointer, &inBufferRest, &outPointer, &outBufferRest) == (size_t)-1 &&
			errno != EINVAL)
		{
			NSLog(@"Convert error: [%d] %s.", errno, strerror(errno));
			iconv_close(conv);
			return NO;
		}

		// didn't convert anything
		if (inBufferRest == [inData length])
		{
			if (outputSize == 0)
			{
				NSLog(@"Output is empty.");
				iconv_close(conv);
				return NO;
			}

			break;
		}

		// write data
		if (outBufferRest < sizeof(outBuffer))
		{
			NSData *outData =
				[NSData dataWithBytesNoCopy:outBuffer
									 length:sizeof(outBuffer) - outBufferRest
							   freeWhenDone:NO];
			@try
			{
				[output writeData:outData];
				outputSize += [outData length];
			}
			@catch (NSException *e)
			{
				NSLog(@"Write error: %@, reason: %@", [e name], [e reason]);
				iconv_close(conv);
				return NO;
			}
		}

		// adjust file offset
		[input seekToFileOffset:[input offsetInFile] - inBufferRest];
	}

	// shutdown convert engine
	iconv_close(conv);

	return YES;
}

+ (BOOL)cconvConvertFile:(NSFileHandle *)input
				  toFile:(NSFileHandle *)output
			fromEncoding:(NSString *)fromEncoding
			  toEncoding:(NSString *)toEncoding
{
	// initialize convert engine
	cconv_t conv = cconv_open([toEncoding UTF8String],
							  [fromEncoding UTF8String]);
	if (conv == (cconv_t)(-1))
	{
		NSLog(@"Can not initialize cconv.");
		return NO;
	}

	// loop converting
	size_t outputSize = 0;
	char outBuffer[OUT_BUFFER_SIZE];
	while (YES)
	{
		// read data
		NSData *inData;
		@try
		{
			inData = [input readDataOfLength:IN_BUFFER_SIZE];

			// reach eof
			if ([inData length] == 0)
			{
				break;
			}
		}
		@catch (NSException *e)
		{
			NSLog(@"Read error: %@, reason: %@", [e name], [e reason]);
			cconv_close(conv);
			return NO;
		}

		// convert
		char *inPointer = (char *)[inData bytes];
		char *outPointer = outBuffer;
		size_t inBufferRest = [inData length];
		size_t outBufferRest = sizeof(outBuffer);
		if (cconv(conv, &inPointer, &inBufferRest,
				  &outPointer, &outBufferRest) == (size_t)-1)
		{
			NSLog(@"Convert error: [%d] %s.", errno, strerror(errno));
			cconv_close(conv);
			return NO;
		}

		// didn't convert anything
		if (inBufferRest == [inData length])
		{
			if (outputSize == 0)
			{
				NSLog(@"Output is empty.");
				cconv_close(conv);
				return NO;
			}

			break;
		}

		// write data
		if (outBufferRest < sizeof(outBuffer))
		{
			NSData *outData = [NSData dataWithBytesNoCopy:outBuffer
												   length:sizeof(outBuffer) - outBufferRest
											 freeWhenDone:NO];
			@try
			{
				[output writeData:outData];
				outputSize += [outData length];
			}
			@catch (NSException *e)
			{
				NSLog(@"Write error: %@, reason: %@", [e name], [e reason]);
				cconv_close(conv);
				return NO;
			}
		}

		// adjust file offset
		[input seekToFileOffset:[input offsetInFile] - inBufferRest];
	}

	// shutdown convert engine
	cconv_close(conv);

	return YES;
}

+ (int)detectEncoding:(NSString *)filename
{
	// user defaults
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	int dataSize = [defaults integerForKey:PrefKeyDetectorDataSize] * 1024;
	int confidence = [defaults integerForKey:PrefKeyDetectorConfidence];

	// read data for analyzing
	NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:filename];
	if (file == nil)
	{
		NSLog(@"Can not open input file %@ to detect encoding", filename);
		return -1;
	}
	NSData *data = [file readDataOfLength:dataSize];
	[file closeFile];
	if ([data length] == 0)
	{
		return -1;
	}
	
	// analyzing
	int encoding = -1;
	UniversalDetector *detector = [[UniversalDetector alloc] init];
	[detector analyzeData:data];
	NSString *charset = [[detector MIMECharset] uppercaseString];
	NSLog(@"Detected encoding of %@ is: %@, confidence: %d%%",
		  filename, charset, (int)([detector confidence] * 100.0));
	
	// get result
	if ((int)([detector confidence] * 100.0) >= confidence)
	{
		if ([charset isEqualToString:@"UTF-8"])
		{
			encoding = ENCODING_UTF8;
		}
		else if ([charset isEqualToString:@"GB18030"] ||
				 [charset isEqualToString:@"GB2312"] ||
				 [charset isEqualToString:@"GBK"] ||
				 [charset isEqualToString:@"EUC-CN"])
		{
			encoding = ENCODING_GB18030;
		}
		else if ([charset isEqualToString:@"BIG5"])
		{
			encoding = ENCODING_BIG5;
		}
	}
	
	[detector release];
	
	return encoding;
}

@end
