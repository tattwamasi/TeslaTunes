#  Building the Application

## Background

My intent for this project, in addition to the obvious one of make life easier with the music library management, was to use it as a testbed for different implementations as well.  I wanted to do largely the same small program in Swift, Objective C, and (to the extent I could) standard and portable as possible C++ (C++14 / 17 to be more specific).  I also wanted to make Windows and Linux versions with as much common code as possible, as interest and time permits.
It's gotten kind of crufty as a result of figuring things out as I go and switching between languages, libraries, etc.  I'd like to clean it upat bboth code and project level, but am not necessarily ready to spend the time doing so.  I welcome pull requests, etc. that make the project structure cleaner, more self-contained, easier to build, etc.

Please note the [License](LICENSE.md) file before doing anything with the project.

#  Installation

This app uses some external libraries, some of which are included as submodules.

- Flac
- Let's Move
- Sparkle
- Taglib




To get the whole project, including submodules, be sure to use
`git clone --recursive` not just git clone.
If you already cloned, I think it's a `git submodule update  --init --recursive` to get things set.

Also remember to `git submodule update --recursive` after fetching new stuff.

If you later have issues building the submodule frameworks, make sure you actually recursively got all *their* 
submodules (which the above command should do).

The flac library is also used, but isn't set as a submodule.  The project files expect to be able to find the headers and link to the static library.  
I have them installed in /usr/local.

Build Targets:
I made a couple of script targets to make packaging, etc. easier.  
GenGitVersion gets used every build to create the version string that gets put into the about box, etc.
GenSparkleInfo makes a zip file and creates the appcast xml that will need to be integrated with the update server
The later target in particular won't be useful for someone else playing around with my code.



Library notes:
Frankly, setting up these things as submodules and as build steps in the main project is kind of a pain and I sort of wish I'd never started...


LetsMove:
I let Xcode update to the recommended project settings, which unfortunately means the submodule is now different.
Had to set deploy target for proj/framework to 10.10 to avoid objc-weak warning

Sparkle:  no changes required to submodule
You'll want to make sure you aren't using a debug build for the final build.

TagLib:
Use taglib2 branch.  Need to run CMake to generate the right stuff.  I made a shell script for that, `make-taglib`
This uses a -G Xcode  and a flag to build the framework to make a project file which is referenced in the main project.




## TODO And Notes

### todo:

Scan through code todo tags and, you know, do them :)

Add error handling and notification pathway so the inner processing code can unwind and clean up properly, for example deleting half made files, and get the information back to the user rather than just sitting there in a failed assert, etc.
* added code to delete partially converted flac files, still need to plumb actual progress and error information flow back to user
* added alert popups if playlist locations aren't set, which I've seen happen when a library on a networked drive is not available.

Change progress icon and add a details arrow similar to iTunes or safari down arrow and blue line indeterminate progress indicator.
Add new window for details, probably a table view of all queued operations with their progress and status.

See if there is a way to make the path controls show a little more context - with just the last component shown, makes it easy to loose track of where the directories actually are since in many cases the last path component is likely to be named the same, something like "Music" for example.
(done) If no default source, then use iTunes properties to guess at sources location
(done) Add user defaults for the needed items, and make sure extra cruft isn't automatically saved
* user path selections now saved.  Still need to add default iTunes lookup and decruft.
* need to figure out where things are being saved besides the prefs file and the autosave - can't see how to get back to a never run state even after deleting prefs and autosave.

(done) Code signing and packaging
* sandbboxing / hardening / app store ... need to consider all.
(done) (if still a placeholder) App icon
(done) About this app popup
* need to add dark mode handling to make the about text not show in a white region.
(done) sleep disable reenable on app exit, in case exit is called without a chance for inProcess handler to run
(done - so far as I can see) make sure no signing keys, etc. get stored
(done) release build testing



issues seen:
left running overnight, an open failed, assert fired for empty metadata - example of error path to be handled.  file locations can time out, for example network drive flakiness, USB drive getting pulled out, etc.  (for that matter, they can get full, have an error, etc.)
