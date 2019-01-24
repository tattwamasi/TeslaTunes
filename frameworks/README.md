#  Installation

This app uses some external libraries, which are included as submodules.

To get the whole project, including submodules, be sure to use
`git clone --recursive` not just git clone.
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



