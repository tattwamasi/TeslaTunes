#  Installation

This app uses some external libraries, which are included as submodules.

To get the whole project, including submodules, be sure to use
`git clone --recursive` not just git clone.
Also remember to `git submodule update` after fetching new stuff.

Library notes:

LetsMove:
I let Xcode update to the recommended project settings, which unfortunately means the submodule is now different.
Had to set deploy target for proj/framework to 10.10 to avoid objc-weak warning


TagLib:
Use taglib2 branch.  Need to run CMake to generate the right stuff.  I made a shell script for that, `make-taglib`
This uses a -G Xcode  and a flag to build the framework to make a project file which is referenced in the main project.



