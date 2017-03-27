# Provisioning

A Quick Look plug-in for .mobileprovision files (on iOS) and .provisionprofile files (on OS X).

## Installation

### Manual installation

A ZIP file with the latest version can be [downloaded from the Releases page](https://github.com/chockenberry/Provisioning/releases).

### Using [brew cask](https://caskroom.github.io/)

```bash
brew cask install provisioning
```

## Select and copy text from Quick Look

If you want to copy information from the Quick Look preview, you need to [change a hidden Finder preference](http://www.macworld.com/article/1164668/select_and_copy_text_within_quick_look_previews.html) using the command line:

```bash
defaults write com.apple.finder QLEnableTextSelection -bool TRUE
killall Finder
```

## Provisionning overview

If you're like the rest of us, provisioning can sometimes make your head spin. When that happens, I recommend reading Sean Heber's [provisioning overview](http://bigzaphod.tumblr.com/post/78574849549/provisioning).

## Thanks

Thanks to following individuals who've helped with this project:

* [Pieter Claerhout](https://github.com/pieterclaerhout) for the OS X and profile type support.
* [Kyle Sluder](https://github.com/kylesluder) for expiration (invalidity dates) in the developer certificates.
* [Evgeny Aleksandrov](https://github.com/ealeksandrov) for locale-aware date formatting.


## Project Notes

* The plug-in code can be signed, but currently isn't because it prevents the app from reading user defaults from Xcode (and showing device names and software versions). If you want to sign the code, set the `Code Signing Identity` build setting to the `Developer ID: *` automatic setting. If you don't have a Developer ID, get creative. You'll also need to change the `SIGNED_CODE` definition from `0` to `1`.

* There is a "Provisioning (Install)" aggregate target that puts the build of Provisioning.qlgenerator in your `~/Library/QuickLook` folder.

* The "Provisioning" schemes runs `qlmanage` with the `-p` argument set to `~/Library/MobileDevice/Provisioning\ Profiles/Iconfactory_Development.mobileprovision`. You won't have this file, so change it to something you do have.

* QuickLook plug-ins sometimes don't like to install. Learn to use `qlmanage -r` to reset the daemon. Using `qlmanage -m plugins | grep mobileprovision` will tell you if the plug-in has been recognized. Sometimes you have to login and out before the plug-in is recognized.

* You can use the command-line to debug, as well. To dump of the output in a `.qlpreview` bundle, use: `qlmanage -p ~/Library/MobileDevice/Provisioning\ Profiles/Iconfactory_Development.mobileprovision -o /tmp/quicklook`. You'll need to make the directory first.

## LICENSE

MIT © [Craig Hockenberry](https://github.com/chockenberry)
