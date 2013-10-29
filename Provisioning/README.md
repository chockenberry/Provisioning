Provisioning QuickLook Generator
--------------------------------

Here is the first pass at displaying the contents of a .mobileprovision on Mavericks. It displays the contents of the file as plain text; this will improve significantly in the future.

Notes:

1) The plug-in code must be signed. The "Code Signing Identity" build setting is to the "Developer ID: *" automatic setting.

2) The "Provisioning" scheme runs "qlmanage" with the -p argument set to "~/Library/MobileDevice/Provisioning\ Profiles/Iconfactory_Development.mobileprovision". You won't have this file, so change it to something you do have.

3) QuickLook plug-ins sometimes don't like to install. Learn to use "qlmanage -r" to reset the daemon. Using "qlmanage -m plugins | grep mobileprovision" will tell you if the plug-in has been recognized.

4) You can use the command-line to debug, as well:

$ mkdir /tmp/quicklook
$ qlmanage -p ~/Library/MobileDevice/Provisioning\ Profiles/Iconfactory_Development.mobileprovision -o /tmp/quicklook

The /tmp/quicklook directory will then contain a dump of the output in a bundle named /tmp/quicklook/Iconfactory_Development.mobileprovision.qlpreview.
