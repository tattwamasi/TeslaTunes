# TeslaTunes
Copy your iTunes or other music library, automatically converting Apple Lossless to Flac, to a destination for use with your Tesla Model S

This is a little Mac OS X utility I wrote for personal use to simplify a reoccurring need to get new music from my home music library into the external drive I use in my Model S. My library is mostly composed of Apple Lossless tracks, but also has a number of other formats as well, chiefly mp3, aac (m4a), and a few wave files.  While it's easy enough to copy the whole library manually, there are a few issues that make that enough of a pain that I wanted something easier - thus this utility was created:

1.  Unfortunately the Model S doesn't (yet) handle the Apple Lossless format - though it does handle FLAC, another lossless audio format which Apple Lossless can be converted to.
2.  I don't want to convert all my Apple Lossless to FLAC in my home library, though I'd reconsider if Apple started directly supporting it.
3. While other programs exist that can copy or sync directories, none of them worked automatically while also handling automatic conversion of *just* files that need to be converted, while leaving others alone.

So I built this.  The app will scan a source and destination directory of your choosing (and remember it, so you don't have to choose it each time), and will copy or convert as appropriate all files in the source directory that don't exist in the destination directory (including in converted FLAC form, if the source is Apple Lossless).  
* It won't copy files it doesn't think the Model S can play (though as noted will convert Apple Lossless to FLAC automatically).
* It won't overwrite any files, and it won't create extra copies of any files, including leaving around Apple Lossless copies at the destination.
* It won't leave partially copied or converted files laying around if you stop it partway through (though no promises in the event of crashes, system hangs, etc.).
* It's vaguely fast... with qualifications.  
  * It's multithreaded and once it gets to the actual Apple Lossless to FLAC bits, it's quite good at loading up the machine and doing them fast as possible.  The FLAC conversions use the Flac project libraries directly rather than calling out to another program.  It could be faster... but not a lot, I don't think.
  * Copies are also reasonable (and also multithreaded), if not fast - similar to what it'd be if you just dragged and dropped the files yourself.  It's mostly system time.  Not sure how to get them any faster.
  * Scanning for what to copy or convert in the first place is fairly fast, but limited to a single thread and in the event of m4a files, each has to be opened to see if it is actually an Apple Lossless file rather than a AAC file, since both use the MPEG4 audio file container.
* By popular demand, it handles playlists from iTunes, as best as we can given the Model S lacks actual playlist support
  * A folder named Playlists is created on the destination path.  Inside it, individual playlists are created as folders.
  * In each individual playlist folder, the media is copied and named by playlist position, song name, artist, etc., for example:  06-Redemption Song-Bob Marley & The Wailers-Legend.flac
  * Songs in a playlist multiple times or in multiple playlists are copied multiple times. This is because of the lack of actual support for playlists.
  * Also by popular demand, the app supports an option for setting the genre of the songs in a playlist folder to the name of the playlist.  This enables a workaround method of listening to playlists songs by selecting them in the genre listings instead of selecting them by folder.  This works around the display limitations of play by folder not showing all of the song information, and may also work better for art display.

  My intent for this project, in addition to the obvious one of make life easier with the music library management, was to use it as a testbed for different implementations as well.  I wanted to do largely the same small program in Swift, Objective C, and (to the extent I could) standard and portable as possible C++ (C++14 / 17 to be more specific).  I also wanted to make Windows and Linux versions with as much common code as possible, as interest and time permits.  That said, I wanted to go ahead and put this out there on the off chance it may help a few other people with the same library management goals as me.
  

![EXAMPLE: after copying some selected playlists](https://cloud.githubusercontent.com/assets/3465489/23572351/690eff4a-0023-11e7-9dcc-085622c36b3b.jpg "EXAMPLE: after copying some selected playlists")
