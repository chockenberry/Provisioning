#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <Security/Security.h>


// all code in Mavericks should be signed, but if we do that we lose the ability to lookup devices in Xcodes preferences
#define SIGNED_CODE 0


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

NSString *expirationStringForDateInCalendar(NSDate *date, NSCalendar *calendar)
{
	NSString *result = nil;
	
	if (date) {
		NSDateComponents *dateComponents = [calendar components:NSDayCalendarUnit fromDate:[NSDate date] toDate:date options:0];
		if (dateComponents.day == 0) {
			result = @"<span class='error'>Expires today</span>";
		}
		else if (dateComponents.day < 0) {
			result = [NSString stringWithFormat:@"<span class='error'>Expired %zd day%s ago</span>", -dateComponents.day, (dateComponents.day == -1 ? "" : "s")];
		}
		else if (dateComponents.day < 30) {
			result = [NSString stringWithFormat:@"<span class='warning'>Expires in %zd day%s</span>", dateComponents.day, (dateComponents.day == 1 ? "" : "s")];
		}
		else {
			result = [NSString stringWithFormat:@"Expires in %zd days", dateComponents.day];
		}
	}

	return result;
}

OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options)
{
    @autoreleasepool {
		NSFileManager *fileManager = [NSFileManager defaultManager];
		
        NSURL *URL = (__bridge NSURL *)url;
		
		NSData *fileData = nil;
		if ([[URL pathExtension] isEqualToString:@"app"]) {
			// get the embedded provisioning for the iOS app
			fileData = [NSData dataWithContentsOfURL:[URL URLByAppendingPathComponent:@"embedded.mobileprovision"]];
		}
		else if ([[URL pathExtension] isEqualToString:@"ipa"]) {
			// get the embedded provisioning from an app arcive using: unzip -p /path/to/Application.ipa 'Payload/*.app/embedded.mobileprovision' (piped to standard output)
			NSTask *unzipTask = [NSTask new];
			[unzipTask setLaunchPath:@"/usr/bin/unzip"];
			[unzipTask setStandardOutput:[NSPipe pipe]];
			[unzipTask setArguments:@[@"-p", [URL path], @"Payload/*.app/embedded.mobileprovision" ]];
			[unzipTask launch];
			[unzipTask waitUntilExit];
			
			fileData = [[[unzipTask standardOutput] fileHandleForReading] readDataToEndOfFile];
		}
		else {
			// get the provisioning directly from the file
			fileData = [NSData dataWithContentsOfURL:URL];
		}
		
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
						if (dateComponents.day == 0) {
							synthesizedValue = @"Created today";
						}
						else {
							synthesizedValue = [NSString stringWithFormat:@"Created %zd day%s ago", dateComponents.day, (dateComponents.day == 1 ? "" : "s")];
						}
						[synthesizedInfo setObject:synthesizedValue forKey:@"CreationSummary"];
					}
					
					value = [propertyList objectForKey:@"ExpirationDate"];
					if ([value isKindOfClass:[NSDate class]]) {
						NSDate *date = (NSDate *)value;
						synthesizedValue = [dateFormatter stringFromDate:date];
						[synthesizedInfo setObject:synthesizedValue forKey:@"ExpirationDateFormatted"];
						
						synthesizedValue = expirationStringForDateInCalendar(date, calendar);
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
						static NSString *const devCertSummaryKey = @"summary";
						static NSString *const devCertInvalidityDateKey = @"invalidity";
						
						NSMutableArray *certificateDetails = [NSMutableArray array];
						NSArray *array = (NSArray *)value;
						for (NSData *data in array) {
							SecCertificateRef certificateRef = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)data);
							if (certificateRef) {
								CFStringRef summaryRef = SecCertificateCopySubjectSummary(certificateRef);
								NSString *summary = (NSString *)CFBridgingRelease(summaryRef);
								if (summary) {
									NSMutableDictionary *detailsDict = [NSMutableDictionary dictionaryWithObject:summary forKey:devCertSummaryKey];
									
									CFErrorRef error;
									CFDictionaryRef valuesDict = SecCertificateCopyValues(certificateRef, (__bridge CFArrayRef)@[(__bridge id)kSecOIDInvalidityDate], &error);
									if (valuesDict) {
										CFDictionaryRef invalidityDateDictionaryRef = CFDictionaryGetValue(valuesDict, kSecOIDInvalidityDate);
										if (invalidityDateDictionaryRef) {
											CFTypeRef invalidityRef = CFDictionaryGetValue(invalidityDateDictionaryRef, kSecPropertyKeyValue);
											CFRetain(invalidityRef);
											
											// NOTE: the invalidity date type of kSecPropertyTypeDate is documented as a CFStringRef in the "Certificate, Key, and Trust Services Reference".
											// In reality, it's a __NSTaggedDate (presumably a tagged pointer representing an NSDate.) But to sure, we'll check:
											id invalidity = CFBridgingRelease(invalidityRef);
											if (invalidity) {
												if ([invalidity isKindOfClass:[NSDate class]]) {
													// use the date directly
													[detailsDict setObject:invalidity forKey:devCertInvalidityDateKey];
												}
												else {
													// parse the date from a string
													NSString *string = [invalidity description];
													NSDateFormatter *invalidityDateFormatter = [NSDateFormatter new];
													[invalidityDateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss Z"];
													NSDate *invalidityDate = [invalidityDateFormatter dateFromString:string];
													if (invalidityDate) {
														[detailsDict setObject:invalidityDate forKey:devCertInvalidityDateKey];
													}
												}
											}
											else {
												NSLog(@"No invalidity date in '%@' certificate, dictionary = %@", summary, invalidityDateDictionaryRef);
											}
										}
										else {
											NSLog(@"No invalidity values in '%@' certificate, dictionary = %@", summary, valuesDict);
										}
										
										CFRelease(valuesDict);
									}
									else {
										NSLog(@"Could not get values in '%@' certificate, error = %@", summary, error);
									}
									
									[certificateDetails addObject:detailsDict];
								}
								else {
									NSLog(@"Could not get summary from certificate");
								}
								
								CFRelease(certificateRef);
							}
						}
						
						NSMutableString *certificates = [NSMutableString string];
						[certificates appendString:@"<table>\n"];
						BOOL evenRow = NO;
						NSArray *sortedCertificateDetails = [certificateDetails sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
							return [((NSDictionary *)obj1)[devCertSummaryKey] compare:((NSDictionary *)obj2)[devCertSummaryKey]];
						}];
						
						for (NSDictionary *detailsDict in sortedCertificateDetails) {
							NSString *summary = detailsDict[devCertSummaryKey];
							NSDate *invalidityDate = detailsDict[devCertInvalidityDateKey];
							NSString *expiration = expirationStringForDateInCalendar(invalidityDate, calendar);
							if (! expiration) {
								expiration = @"<span class='warning'>No invalidity date in certificate</span>";
							}
							[certificates appendFormat:@"<tr class='%s'><td>%@</td><td>%@</td></tr>\n", (evenRow ? "even" : "odd"), summary, expiration];
							evenRow = !evenRow;
						}
						[certificates appendString:@"</table>\n"];
						
						synthesizedValue = [certificates copy];
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
								displayPrefix = [NSString stringWithFormat:@"%@ ➞ ", devicePrefix];
							}
							
#if !SIGNED_CODE
							// check if Xcode has seen the device
							NSString *deviceName = @"";
							NSString *deviceSoftwareVerson = @"";
							NSPredicate *predicate = [NSPredicate predicateWithFormat:@"deviceIdentifier = %@", device];
							NSArray *matchingDevices = [savedDevices filteredArrayUsingPredicate:predicate];
							if ([matchingDevices count] > 0) {
								id matchingDevice = [matchingDevices objectAtIndex:0];
								if ([matchingDevice isKindOfClass:[NSDictionary class]]) {
									/* the matchingDevice dictionary looks like this:
									 {
									 buildVersion = 9A334;
									 deviceArchitecture = armv7;
									 deviceBluetoothMAC = "34:15:9e:82:XX:XX";
									 deviceCapacity = 30448345088;
									 deviceClass = iPod;
									 deviceColorString = iPodShinyMetal;
									 deviceDevelopmentStatus = Development;
									 deviceIdentifier = 2eaefee8081ca97fadf0be5f2822b458XXXXXXXX;
									 deviceName = Lustro;
									 deviceSerialNumber = 1B0101XXXXXX;
									 deviceSoftwareVersion = "5.0 (9A334)";
									 deviceType = "iPod3,1";
									 deviceWiFiMAC = "34:15:9e:83:XX:XX";
									 platformIdentifier = "com.apple.platform.iphoneos";
									 productVersion = "5.0";
									 },
									 */
									NSDictionary *matchingDeviceDictionary = (NSDictionary *)matchingDevice;
									deviceName = [matchingDeviceDictionary objectForKey:@"deviceName"];
									deviceSoftwareVerson = [matchingDeviceDictionary objectForKey:@"deviceSoftwareVersion"];
								}
							}
							
							[devices appendFormat:@"<tr class='%s'><td>%@</td><td class='divider'>%@</td><td class='divider'>%@</td><td class='divider'>%@</td></tr>\n", (evenRow ? "even" : "odd"), displayPrefix, device, deviceName, deviceSoftwareVerson];
#else
							[devices appendFormat:@"<tr class='%s'><td>%@</td><td>%@</td></tr>\n", (evenRow ? "even" : "odd"), displayPrefix, device];
#endif
							evenRow = !evenRow;
						}
						[devices appendString:@"</table>\n"];
						
						synthesizedValue = [devices copy];
						[synthesizedInfo setObject:synthesizedValue forKey:@"ProvisionedDevicesFormatted"];
						
						synthesizedValue = [NSString stringWithFormat:@"%zd Device%s", [array count], ([array count] == 1 ? "" : "s")];
						[synthesizedInfo setObject:synthesizedValue forKey:@"ProvisionedDevicesCount"];
					}
					else {
						[synthesizedInfo setObject:@"No Devices" forKey:@"ProvisionedDevicesFormatted"];
						[synthesizedInfo setObject:@"Distribution Profile" forKey:@"ProvisionedDevicesCount"];
					}
					
					{
						NSString *profileString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
						profileString = [profileString stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
						NSDictionary *htmlEntityReplacement = @{
																@"\"": @"&quot;",
																@"'": @"&apos;",
																@"<": @"&lt;",
																@">": @"&gt;",
																};
						for (NSString *key in [htmlEntityReplacement allKeys]) {
							NSString *replacement = [htmlEntityReplacement objectForKey:key];
							profileString = [profileString stringByReplacingOccurrencesOfString:key withString:replacement];
						}
						synthesizedValue = [NSString stringWithFormat:@"<pre>%@</pre>", profileString];
						[synthesizedInfo setObject:synthesizedValue forKey:@"RawData"];
					}
					
					{
						synthesizedValue = [[NSBundle bundleWithIdentifier:@"com.iconfactory.Provisioning"] objectForInfoDictionaryKey:@"CFBundleVersion"];
						[synthesizedInfo setObject:synthesizedValue forKey:@"BundleVersion"];
					}
					
					// older provisioning files don't include some key/value pairs
					value = [propertyList objectForKey:@"TeamName"];
					if (! value) {
						[synthesizedInfo setObject:@"<em>Team name not available</em>" forKey:@"TeamName"];
					}
					value = [propertyList objectForKey:@"TeamIdentifier"];
					if (! value) {
						[synthesizedInfo setObject:@"<em>Team ID not available</em>" forKey:@"TeamIds"];
					}
					value = [propertyList objectForKey:@"AppIDName"];
					if (! value) {
						[synthesizedInfo setObject:@"<em>App name not available</em>" forKey:@"AppIDName"];
					}
                    
                    // determine the profile type
                    BOOL getTaskAllow = NO;
                    value = [propertyList objectForKey:@"Entitlements"];
					if ([value isKindOfClass:[NSDictionary class]]) {
						NSDictionary *dictionary = (NSDictionary *)value;
                        getTaskAllow = [[dictionary valueForKey:@"get-task-allow"] boolValue];
                    }
					
                    BOOL hasDevices = NO;
                    value = [propertyList objectForKey:@"ProvisionedDevices"];
					if ([value isKindOfClass:[NSArray class]]) {
                        hasDevices = YES;
                    }
                    
                    BOOL isEnterprise = [[propertyList objectForKey:@"ProvisionsAllDevices"] boolValue];
                    
                    if ([[URL.absoluteString pathExtension] isEqualToString:@"provisionprofile"]) {
						[synthesizedInfo setObject:@"mac" forKey:@"Platform"];
						
						[synthesizedInfo setObject:@"Mac" forKey:@"ProfilePlatform"];
                        if (hasDevices) {
                            [synthesizedInfo setObject:@"Development" forKey:@"ProfileType"];
                        }
						else {
                            [synthesizedInfo setObject:@"Distribution (App Store)" forKey:@"ProfileType"];
                        }
                    }
					else {
						[synthesizedInfo setObject:@"ios" forKey:@"Platform"];
						
						[synthesizedInfo setObject:@"iOS" forKey:@"ProfilePlatform"];
                        if (hasDevices) {
                            if (getTaskAllow) {
                                [synthesizedInfo setObject:@"Development" forKey:@"ProfileType"];
                            }
							else {
                                [synthesizedInfo setObject:@"Distribution (Ad Hoc)" forKey:@"ProfileType"];
                            }
                        }
						else {
                            if (isEnterprise) {
                                [synthesizedInfo setObject:@"Enterprise" forKey:@"ProfileType"];
                            }
							else {
                                [synthesizedInfo setObject:@"Distribution (App Store)" forKey:@"ProfileType"];
                            }
                        }
                    }
					
					{
						[synthesizedInfo setObject:[URL lastPathComponent] forKey:@"FileName"];
						
						if ([[URL pathExtension] isEqualToString:@"app"]) {
							// get the "file" information using the application package folder
							NSString *folderPath = [URL path];
							
							NSDictionary *folderAttributes = [fileManager attributesOfItemAtPath:folderPath error:NULL];
							if (folderAttributes) {
								NSDate *folderModificationDate = [folderAttributes fileModificationDate];
								
								unsigned long long folderSize = 0;
								NSArray *filesArray = [fileManager subpathsOfDirectoryAtPath:folderPath error:nil];
								for (NSString *fileName in filesArray) {
									NSDictionary *fileAttributes = [fileManager attributesOfItemAtPath:[folderPath stringByAppendingPathComponent:fileName] error:NULL];
									if (fileAttributes)
										folderSize += [fileAttributes fileSize];
								}
								
								synthesizedValue = [NSString stringWithFormat:@"%@, Modified %@",
													[NSByteCountFormatter stringFromByteCount:folderSize countStyle:NSByteCountFormatterCountStyleFile],
													[dateFormatter stringFromDate:folderModificationDate]];
								[synthesizedInfo setObject:synthesizedValue forKey:@"FileInfo"];
							}
							else {
								[synthesizedInfo setObject:@"" forKey:@"FileInfo"];
							}
						}
						else {
							NSDictionary *fileAttributes = [fileManager attributesOfItemAtPath:[URL path] error:NULL];
							if (fileAttributes) {
								NSDate *fileModificationDate = [fileAttributes fileModificationDate];
								unsigned long long fileSize = [fileAttributes fileSize];
								
								synthesizedValue = [NSString stringWithFormat:@"%@, Modified %@",
													[NSByteCountFormatter stringFromByteCount:fileSize countStyle:NSByteCountFormatterCountStyleFile],
													[dateFormatter stringFromDate:fileModificationDate]];
								[synthesizedInfo setObject:synthesizedValue forKey:@"FileInfo"];
							}
						}
					}
					
#ifdef DEBUG
					[synthesizedInfo setObject:@"debug" forKey:@"DEBUG"];
#else
					[synthesizedInfo setObject:@"" forKey:@"DEBUG"];
#endif
					
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
		else {
			NSLog(@"No file data for %@", URL);
		}
	}
	
	return noErr;
}

void CancelPreviewGeneration(void *thisInterface, QLPreviewRequestRef preview)
{
}
