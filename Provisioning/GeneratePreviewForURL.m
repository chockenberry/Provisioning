#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <Security/Security.h>

OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options);
void CancelPreviewGeneration(void *thisInterface, QLPreviewRequestRef preview);

/* -----------------------------------------------------------------------------
   Generate a preview for file

   This function's job is to create preview for designated file
   ----------------------------------------------------------------------------- */

void displayKeyAndValue(NSUInteger level, NSString *key, id value, NSMutableString *output)
{
	int indent = (int)(level * 4);
	
	if ([value isKindOfClass:[NSDictionary class]]) {
		if (key) {
			[output appendFormat:@"%*s%@ = {\n", indent, "", key];
		}
		else {
			[output appendFormat:@"%*s{\n", indent, ""];
		}
		NSDictionary *dictionary = (NSDictionary *)value;
		NSArray *keys = [[dictionary allKeys] sortedArrayUsingSelector:@selector(compare:)];
		for (NSString *key in keys) {
			displayKeyAndValue(level + 1, key, [dictionary valueForKey:key], output);
		}
		[output appendFormat:@"%*s}\n", indent, ""];
	}
	else if ([value isKindOfClass:[NSArray class]]) {
		[output appendFormat:@"%*s%@ = (\n", indent, "", key];
		NSArray *array = (NSArray *)value;
		for (id value in array) {
			displayKeyAndValue(level + 1, nil, value, output);
		}
		[output appendFormat:@"%*s)\n", indent, ""];
	}
	else if ([value isKindOfClass:[NSData class]]) {
		NSData *data = (NSData *)value;
		if (key) {
			[output appendFormat:@"%*s%@ = %zd bytes of data\n", indent, "", key, [data length]];
		}
		else {
			[output appendFormat:@"%*s%zd bytes of data\n", indent, "", [data length]];
		}
	}
	else {
		if (key) {
			[output appendFormat:@"%*s%@ = %@\n", indent, "", key, value];
		}
		else {
			[output appendFormat:@"%*s%@\n", indent, "", value];
		}
	}
}

#define SIGNED_CODE 1

OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options)
{
    @autoreleasepool {
        NSURL *URL = (__bridge NSURL *)url;

		NSData *fileData = [NSData dataWithContentsOfURL:URL];
		if (fileData) {
			CMSDecoderRef decoder = NULL;
			CMSDecoderCreate(&decoder);
			CMSDecoderUpdateMessage(decoder, fileData.bytes, fileData.length);
			CMSDecoderFinalizeMessage(decoder);
			CFDataRef dataRef = NULL;
			CMSDecoderCopyContent(decoder, &dataRef);
			NSData *data = (NSData *)CFBridgingRelease(dataRef);
			CFRelease(decoder);
			
			if (data) {
				// check if the request was cancelled
				if (! QLPreviewRequestIsCancelled(preview)) {

#if !SIGNED_CODE
					// get the iOS devices that Xcode has seen, which only works if the plug-in is not running in a sandbox
					NSUserDefaults *xcodeDefaults = [NSUserDefaults new];
					[xcodeDefaults addSuiteNamed:@"com.apple.dt.XCode"];
					NSArray *savedDevices = [xcodeDefaults objectForKey:@"DVTSavediPhoneDevices"];
					NSLog(@"savedDevices = %@", savedDevices);
					
					// the sandbox also thwarts attempts to read the data from the shell command
					// $ defaults read com.apple.dt.XCode DVTSavediPhoneDevices
					NSTask *task = [NSTask new];
					[task setLaunchPath:@"/usr/bin/defaults"];
					[task setArguments:@[ @"read", @"com.apple.dt.XCode", @"DVTSavediPhoneDevices" ]];
					[task setStandardOutput:[NSPipe pipe]];
					[task launch];
					
					NSData *pipeData = [[[task standardOutput] fileHandleForReading] readDataToEndOfFile];
					NSString *pipeString = [[NSString alloc] initWithData:pipeData encoding:NSUTF8StringEncoding];
					NSLog(@"pipeString = %@", pipeString);
#endif

					NSURL *htmlURL = [[NSBundle bundleWithIdentifier:@"com.iconfactory.Provisioning"] URLForResource:@"template" withExtension:@"html"];
					NSMutableString *html = [NSMutableString stringWithContentsOfURL:htmlURL encoding:NSUTF8StringEncoding error:NULL];

					// use all keys and values in the property list to generate replacement tokens and values
					NSDictionary *propertyList = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
					for (NSString *key in [propertyList allKeys]) {
						NSString *replacementValue = [[propertyList valueForKey:key] description];
						NSString *replacementToken = [NSString stringWithFormat:@"__%@__", key];
						[html replaceOccurrencesOfString:replacementToken withString:replacementValue options:0 range:NSMakeRange(0, [html length])];
					}
					
					// synthesize other replacement tokens and values
					NSMutableDictionary *synthesizedInfo = [NSMutableDictionary dictionary];
					id value = nil;
					NSString *synthesizedValue = nil;
					NSDateFormatter *dateFormatter = [NSDateFormatter new];
					[dateFormatter setDateFormat:@"EEEE',' MMMM d',' yyyy 'at' h:mm a"];
					NSCalendar *calendar = [NSCalendar currentCalendar];

					value = [propertyList objectForKey:@"CreationDate"];
					if ([value isKindOfClass:[NSDate class]]) {
						NSDate *date = (NSDate *)value;
						synthesizedValue = [dateFormatter stringFromDate:date];
						[synthesizedInfo setObject:synthesizedValue forKey:@"CreationDateFormatted"];

						NSDateComponents *dateComponents = [calendar components:NSDayCalendarUnit fromDate:date toDate:[NSDate date] options:0];
						synthesizedValue = [NSString stringWithFormat:@"Created %zd days ago", dateComponents.day];
						[synthesizedInfo setObject:synthesizedValue forKey:@"CreationSummary"];
					}
					
					value = [propertyList objectForKey:@"ExpirationDate"];
					if ([value isKindOfClass:[NSDate class]]) {
						NSDate *date = (NSDate *)value;
						synthesizedValue = [dateFormatter stringFromDate:date];
						[synthesizedInfo setObject:synthesizedValue forKey:@"ExpirationDateFormatted"];
						
						NSDateComponents *dateComponents = [calendar components:NSDayCalendarUnit fromDate:[NSDate date] toDate:date options:0];
						// TODO: if negative, show "Expired" instead...
						if (dateComponents.day < 0) {
							synthesizedValue = [NSString stringWithFormat:@"<span class='expired'>Expired %zd days ago</span>", -dateComponents.day];
						}
						else {
							synthesizedValue = [NSString stringWithFormat:@"Expires in %zd days", dateComponents.day];
						}
						[synthesizedInfo setObject:synthesizedValue forKey:@"ExpirationSummary"];
					}
					
					value = [propertyList objectForKey:@"ApplicationIdentifierPrefix"];
					if ([value isKindOfClass:[NSArray class]]) {
						NSArray *array = (NSArray *)value;
						synthesizedValue = [array componentsJoinedByString:@", "];
						[synthesizedInfo setObject:synthesizedValue forKey:@"AppIds"];

					}

					value = [propertyList objectForKey:@"TeamIdentifier"];
					if ([value isKindOfClass:[NSArray class]]) {
						NSArray *array = (NSArray *)value;
						synthesizedValue = [array componentsJoinedByString:@", "];
						[synthesizedInfo setObject:synthesizedValue forKey:@"TeamIds"];
					}

					value = [propertyList objectForKey:@"Entitlements"];
					if ([value isKindOfClass:[NSDictionary class]]) {
						NSDictionary *dictionary = (NSDictionary *)value;
						NSMutableString *dictionaryFormatted = [NSMutableString string];
						displayKeyAndValue(0, nil, dictionary, dictionaryFormatted);
						synthesizedValue = [NSString stringWithFormat:@"<pre>%@</pre>", dictionaryFormatted];
						
						[synthesizedInfo setObject:synthesizedValue forKey:@"EntitlementsFormatted"];
					}
					else {
						[synthesizedInfo setObject:@"No Entitlements" forKey:@"EntitlementsFormatted"];
					}

					value = [propertyList objectForKey:@"DeveloperCertificates"];
					if ([value isKindOfClass:[NSArray class]]) {
						NSMutableArray *summaries = [NSMutableArray array];
						NSArray *array = (NSArray *)value;
						for (NSData *data in array) {
							SecCertificateRef certificateRef = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)data);
							if (certificateRef) {
								CFStringRef summaryRef = SecCertificateCopySubjectSummary(certificateRef);
								NSString *summary = (NSString *)CFBridgingRelease(summaryRef);
								[summaries addObject:summary];
								CFRelease(certificateRef);
							}
						}
						synthesizedValue = [summaries componentsJoinedByString:@"<br/>"];
						[synthesizedInfo setObject:synthesizedValue forKey:@"DeveloperCertificatesFormatted"];
					}
					else {
						[synthesizedInfo setObject:@"No Developer Certificates" forKey:@"DeveloperCertificatesFormatted"];
					}

					value = [propertyList objectForKey:@"ProvisionedDevices"];
					if ([value isKindOfClass:[NSArray class]]) {
						NSArray *array = (NSArray *)value;
						NSArray *sortedArray = [array sortedArrayUsingSelector:@selector(compare:)];

						NSString *currentPrefix = nil;
						NSMutableString *devices = [NSMutableString string];
						[devices appendString:@"<table>\n"];
						BOOL evenRow = NO;
						for (NSString *device in sortedArray) {
							// compute the prefix for the first column of the table
							NSString *displayPrefix = @"";
							NSString *devicePrefix = [device substringToIndex:1];
							if (! [currentPrefix isEqualToString:devicePrefix]) {
								currentPrefix = devicePrefix;
								displayPrefix = [NSString stringWithFormat:@"%@:", devicePrefix];
							}
							
#if !SIGNED_CODE
							// check if Xcode has seen the device
							NSString *deviceName = @"";
							NSString *deviceSoftwareVerson = @"";
							NSPredicate *predicate = [NSPredicate predicateWithFormat:@"deviceIdentifier = %@", device];
							NSArray *matchingDevices = [savedDevices filteredArrayUsingPredicate:predicate];
							if ([matchingDevices count] > 0) {
								id matchingDevice = [matchingDevices firstObject];
								if ([matchingDevice isKindOfClass:[NSDictionary class]]) {
									NSDictionary *matchingDeviceDictionary = (NSDictionary *)matchingDevice;
									deviceName = [matchingDeviceDictionary objectForKey:@"deviceName"];
									deviceSoftwareVerson = [matchingDeviceDictionary objectForKey:@"deviceSoftwareVersion"];
								}
							}
							
							[devices appendFormat:@"<tr class='%s'><td>%@</td><td>%@</td><td>%@</td><td>%@</td></tr>\n", (evenRow ? "even" : "odd"), displayPrefix, device, deviceName, deviceSoftwareVerson];
#else
							[devices appendFormat:@"<tr class='%s'><td>%@</td><td>%@</td></tr>\n", (evenRow ? "even" : "odd"), displayPrefix, device];
#endif
							evenRow = !evenRow;
						}
						[devices appendString:@"</table>\n"];
						
						synthesizedValue = [devices copy];
						[synthesizedInfo setObject:synthesizedValue forKey:@"ProvisionedDevicesFormatted"];
						
						synthesizedValue = [NSString stringWithFormat:@"%zd Devices", [array count]];
						[synthesizedInfo setObject:synthesizedValue forKey:@"ProvisionedDevicesCount"];
					}
					else {
						[synthesizedInfo setObject:@"No Devices" forKey:@"ProvisionedDevicesFormatted"];
						[synthesizedInfo setObject:@"Distribution Profile" forKey:@"ProvisionedDevicesCount"];
					}

#if 0
// the raw data for the provisioning profile can easily be generated, but I can't find a way to copy it to the clipboard in the HTML that's generated
					{
						synthesizedValue = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
						[synthesizedInfo setObject:synthesizedValue forKey:@"RawData"];
					}
// automatically copying the info to the clipboard using NSPasteboard without any user interaction is a bad idea, too...
#endif
					{
						synthesizedValue = [[NSBundle bundleWithIdentifier:@"com.iconfactory.Provisioning"] objectForInfoDictionaryKey:@"CFBundleVersion"];
						[synthesizedInfo setObject:synthesizedValue forKey:@"BundleVersion"];
					}

					// older provisioning files don't include TeamName or AppIDName keys
					value = [propertyList objectForKey:@"TeamName"];
					if (! value) {
						[synthesizedInfo setObject:@"" forKey:@"TeamName"];
					}
					value = [propertyList objectForKey:@"AppIDName"];
					if (! value) {
						[synthesizedInfo setObject:@"" forKey:@"AppIDName"];
					}
					
					for (NSString *key in [synthesizedInfo allKeys]) {
						NSString *replacementValue = [synthesizedInfo objectForKey:key];
						NSString *replacementToken = [NSString stringWithFormat:@"__%@__", key];
						[html replaceOccurrencesOfString:replacementToken withString:replacementValue options:0 range:NSMakeRange(0, [html length])];
					}
					
					NSDictionary *properties = @{ // properties for the HTML data
						(__bridge NSString *)kQLPreviewPropertyTextEncodingNameKey : @"UTF-8",
						(__bridge NSString *)kQLPreviewPropertyMIMETypeKey : @"text/html" };
					
					QLPreviewRequestSetDataRepresentation(preview, (__bridge CFDataRef)[html dataUsingEncoding:NSUTF8StringEncoding], kUTTypeHTML, (__bridge CFDictionaryRef)properties);
				}
			}
		}
	}
	
	return noErr;
}

void CancelPreviewGeneration(void *thisInterface, QLPreviewRequestRef preview)
{
}
