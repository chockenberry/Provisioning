Provisioning
============

A QuickLook plug-in for .mobileprovision files


Here is the first pass at displaying the contents of a .mobileprovision on Mavericks. It displays the contents of the file as plain text; this will improve significantly in the future.

Notes
-----

* The plug-in code must be signed. The "Code Signing Identity" build setting is to the "Developer ID: *" automatic setting. If you don't have a Developer ID, get creative.

* The "Provisioning" scheme runs "qlmanage" with the -p argument set to "~/Library/MobileDevice/Provisioning\ Profiles/Iconfactory_Development.mobileprovision". You won't have this file, so change it to something you do have.

* QuickLook plug-ins sometimes don't like to install. Learn to use "qlmanage -r" to reset the daemon. Using "qlmanage -m plugins | grep mobileprovision" will tell you if the plug-in has been recognized.

* You can use the command-line to debug, as well. To dump of the output in a .qlpreview bundle, use: "qlmanage -p ~/Library/MobileDevice/Provisioning\ Profiles/Iconfactory_Development.mobileprovision -o /tmp/quicklook". You'll need to make the directory first.


