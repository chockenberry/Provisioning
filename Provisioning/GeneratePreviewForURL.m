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

OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options)
{
    @autoreleasepool {
		
        // Load the property list from the URL
        NSURL *URL = (__bridge NSURL *)url;
		NSLog(@"%s URL = %@", __PRETTY_FUNCTION__, URL);

		CMSDecoderRef decoder = NULL;
		CMSDecoderCreate(&decoder);
		
		NSData *fileData = [NSData dataWithContentsOfURL:URL];
		if (fileData) {
			CMSDecoderUpdateMessage(decoder, fileData.bytes, fileData.length);
			CMSDecoderFinalizeMessage(decoder);
			CFDataRef dataRef = NULL;
			CMSDecoderCopyContent(decoder, &dataRef);
			
			if (dataRef) {
				NSString *fileContents = [[NSString alloc] initWithData:(NSData *)CFBridgingRelease(dataRef) encoding:NSUTF8StringEncoding];
		
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
					QLPreviewRequestSetDataRepresentation(preview, (__bridge CFDataRef)[fileContents dataUsingEncoding:NSUTF8StringEncoding], kUTTypePlainText, NULL);
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
