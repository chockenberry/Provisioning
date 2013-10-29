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
		[output appendFormat:@"%*s%@ = [\n", indent, "", key];
		NSArray *array = (NSArray *)value;
		for (id value in array) {
			displayKeyAndValue(level + 1, nil, value, output);
		}
		[output appendFormat:@"%*s]\n", indent, ""];
	}
	else if ([value isKindOfClass:[NSData class]]) {
		NSData *data = (NSData *)value;

		// try to display the data as a certificate
		SecCertificateRef certificateRef = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)data);
		if (certificateRef) {
			CFStringRef summaryRef = SecCertificateCopySubjectSummary(certificateRef);
			if (key) {
				[output appendFormat:@"%*s%@ = %@\n", indent, "", key, (__bridge NSString *)summaryRef];
			}
			else {
				[output appendFormat:@"%*s%@\n", indent, "", (__bridge NSString *)summaryRef];
			}
			
			CFRelease(summaryRef);
			CFRelease(certificateRef);
		}
		else {
			if (key) {
				[output appendFormat:@"%*s%@ = %zd bytes of data\n", indent, "", key, [data length]];
			}
			else {
				[output appendFormat:@"%*s%zd bytes of data\n", indent, "", [data length]];
			}
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
#if 0
					// eventually, the fileContents will be formatted using an HTML template...
					NSURL *htmlURL = [[NSBundle bundleWithIdentifier:@"com.iconfactory.Provisioning"] URLForResource:@"template" withExtension:@"html"];
					NSString *html = [NSString stringWithContentsOfURL:htmlURL encoding:NSUTF8StringEncoding error:NULL];
					
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
