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

OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options)
{
    @autoreleasepool {
		
        // Load the property list from the URL
        NSURL *URL = (__bridge NSURL *)url;
		NSLog(@"URL = %@", URL);

		CMSDecoderRef decoder = NULL;
		CMSDecoderCreate(&decoder);
		
		NSData *fileData = [NSData dataWithContentsOfURL:URL];
		if (fileData) {
			CMSDecoderUpdateMessage(decoder, fileData.bytes, fileData.length);
			CMSDecoderFinalizeMessage(decoder);
			CFDataRef dataRef = NULL;
			CMSDecoderCopyContent(decoder, &dataRef);
			NSData *data = (NSData *)CFBridgingRelease(dataRef);
			
			if (data) {
				// check if the request was cancelled
				if (! QLPreviewRequestIsCancelled(preview)) {
#if 1
					// eventually, the fileContents will be formatted using an HTML template...
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
					[dateFormatter setDateFormat:@"h:mm a 'on' EEEE',' MMMM d',' yyyy"];
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
							synthesizedValue = [NSString stringWithFormat:@"Expired %zd days ago", -dateComponents.day];
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
						NSMutableString *synthesizedValue = [NSMutableString string];
						displayKeyAndValue(0, nil, dictionary, synthesizedValue);
						
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
						synthesizedValue = [sortedArray componentsJoinedByString:@"\n"];
						[synthesizedInfo setObject:synthesizedValue forKey:@"ProvisionedDevicesFormatted"];
						
						synthesizedValue = [NSString stringWithFormat:@"%zd Devices", [array count]];
						[synthesizedInfo setObject:synthesizedValue forKey:@"ProvisionedDevicesCount"];
					}
					else {
						[synthesizedInfo setObject:@"" forKey:@"ProvisionedDevicesFormatted"];
						[synthesizedInfo setObject:@"No Devices" forKey:@"ProvisionedDevicesCount"];
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
#else
					// for now, just use a plain-text representation
					NSDictionary *propertyList = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
					if (propertyList) {
						NSMutableString *output = [NSMutableString string];
						displayKeyAndValue(0, nil, propertyList, output);
						QLPreviewRequestSetDataRepresentation(preview, (__bridge CFDataRef)[output dataUsingEncoding:NSUTF8StringEncoding], kUTTypePlainText, NULL);
					}
#endif
				}
			}
		}
	}
	
	return noErr;
}

void CancelPreviewGeneration(void *thisInterface, QLPreviewRequestRef preview)
{
}
