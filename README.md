# TeslaTunes
Copy your iTunes or other music library, automatically converting Apple Lossless to Flac, to a destination for use with your Tesla


[Website](https://teslatunes.loci.net) |
[Installation](#installation) |
[Credits, licensing, etc.](#credits) |
[Donations](#donations) |
[Contact](#contact)

This is a little MacOS utility I wrote for personal use to simplify a reoccurring need to get new music from my home music library into the external drive I use in my Model S. My library is mostly composed of Apple Lossless tracks, but also has a number of other formats as well such as mp3, aac (m4a), and a few wave files.  While it's easy enough to copy the whole library manually, there are a few issues that make that enough of a pain that I wanted something easier - thus this utility was created:

1.  Unfortunately the Model S doesn't (yet) handle the Apple Lossless format - though it does handle FLAC, another lossless audio format which Apple Lossless can be converted to.
2.  I don't want to convert all my Apple Lossless to FLAC in my home library, though I'd reconsider if Apple started directly supporting it.
3. While other programs exist that can copy or sync directories, none of them worked automatically while also handling automatic conversion of *just* files that need to be converted, while leaving others alone.
4.  The Tesla doesn't support playlists, and just making directories with songs as a workaround has issues.  The twiddling one has to do to get things *just so* is tiresome.

So I built this.  The app will scan a source and destination directory of your choosing (and remember it, so you don't have to choose it each time), and will copy or convert as appropriate all files in the source directory that don't exist in the destination directory (including in converted FLAC form, if the source is Apple Lossless).

* It won't copy files it doesn't think the Model S can play (though as noted will convert Apple Lossless to FLAC automatically).
  * **[Note]** Apple Music and older purchased files that are DRM protected will not play and are skipped.  iTunes Matched songs will work as long as the file can be found.
* It won't overwrite any files*, and it won't create extra copies of any files, including leaving around Apple Lossless copies at the destination.
* It won't leave partially copied or converted files laying around if you stop it partway through* (though no promises in the event of crashes, system hangs, etc.).
* It's vaguely fast... with qualifications.
  * It's multithreaded and once it gets to the actual Apple Lossless to FLAC bits, it's quite good at loading up the machine and doing them fast as possible.  The FLAC conversions use the Flac project libraries directly rather than calling out to another program.  It could be faster... but not a lot, I don't think.
  * Copies are also reasonable (and also multithreaded), if not fast - similar to what it'd be if you just dragged and dropped the files yourself.  It's mostly system time.  Not sure how to get them any faster.
  * Scanning for what to copy or convert in the first place is fairly fast, but limited to a single thread and in the event of m4a files, each has to be opened to see if it is actually an Apple Lossless file rather than a AAC file, since both use the MPEG4 audio file container.
* By popular demand, it handles playlists from iTunes, as best as we can given the Model S lacks actual playlist support
  * A folder named Playlists is created on the destination path.  Inside it, individual playlists are created as folders.
  * In each individual playlist folder, the media is copied and named by playlist position, song name, artist, etc., for example:  06-Redemption Song-Bob Marley & The Wailers-Legend.flac
  * Songs in a playlist multiple times or in multiple playlists are copied multiple times. This is because of the lack of actual support for playlists.
  * Also by popular demand, the app supports an option for setting the genre of the songs in a playlist folder to the name of the playlist.  This enables a workaround method of listening to playlists songs by selecting them in the genre listings instead of selecting them by folder.  This works around the display limitations of play by folder not showing all of the song information, and may also work better for art display.
  * [new] `.m3u` Playlist files will be created in each playlist folder, in order to help out people that use the same storage in other vehicles that *do* support `.m3u` files.

  *Note that the `.m3u` files will be written into each playlist directory and (due to laziness basically) will even be created on a scan step (sorry).  This is an exception to the general rule of not overwriting and not leaving files around if cancelled, just scanned, etc.

## Installation
Just [download the latest release zip file](https://github.com/tattwamasi/TeslaTunes/releases/latest) and unzip it.  Throw the app in applications, or it'll offer to do it for you on launch if it isn't already there (you want it in either your own Applications folder or the system one to avoid potential issues with Apple's increasing security precautions).

If you are a dev and want to look at the project yourself in order to change something or otherwise play around, please see the [Building](BUILDING.md) file.


## Credit
Thanks to the people that have taken the time to provide feedback on the Tesla and TMC forums, and especially to those who have provided feedback via the [Github Issues](https://github.com/tattwamasi/TeslaTunes/issues) mechanism.  Should anyone ever choose to make a donation in appreciation for the app, that gets a big thanks too even if anonymous.

Thanks to the 3rd party libraries and devs I've leveraged.  See the [License](LICENSE.md) for more details.

### Donations
  Should you wish to donate something to show your appreciation.... cool! It's appreciated.  Take your pick.

[![paypal](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.me/robcarnold)

[![Beerpay](https://beerpay.io/tattwamasi/TeslaTunes/badge.svg?style=flat)](https://beerpay.io/tattwamasi/TeslaTunes)

Or send XLM or any other asset with [Stellar](https://www.stellar.org) to `ra*keybase.io`

Or perhaps you prefer zcash to `t1Jo8emo8iZ31S6mSmnQyG1zLXoRTtWi18f`
or one of these other options:
[![Donate with Ethereum](https://en.cryptobadges.io/badge/small/0x949873323Ac758FF8b2F1e9A9b4928635114A1Ef)](https://en.cryptobadges.io/donate/0x949873323Ac758FF8b2F1e9A9b4928635114A1Ef)
[![Donate with Bitcoin](https://en.cryptobadges.io/badge/small/35KmT8jHKjUm5SqACp4MiRmVJi8GgT1yxJ)](https://en.cryptobadges.io/donate/35KmT8jHKjUm5SqACp4MiRmVJi8GgT1yxJ)
[![Donate with Litecoin](https://en.cryptobadges.io/badge/micro/LXK3P7hw8GmLdh46Swi31RrRNvUKRwyC1N)](https://en.cryptobadges.io/donate/LXK3P7hw8GmLdh46Swi31RrRNvUKRwyC1N)


### Contact

Please use the github Issues feature in general. Otherwise, feel free to use any method in my [Keybase profile](https://keybase.io/ra).

## Screenshot

![EXAMPLE: after copying some selected playlists](https://cloud.githubusercontent.com/assets/3465489/23572351/690eff4a-0023-11e7-9dcc-085622c36b3b.jpg "EXAMPLE: after copying some selected playlists")
