//
//  m3u_playlist.hpp
//  TeslaTunes
//
//  Created by Rob Arnold on 1/28/19.
//  Copyright © 2019 Loci Consulting. All rights reserved.
//

#ifndef m3u_playlist_hpp
#define m3u_playlist_hpp

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#include <stdio.h>
#include <string>
#include <vector>
#include <fstream>



/*****  File format for simple .m3u:

#EXTM3U

#EXTINF:240,The Sample Band - My 4 Minute Song
my_4_minute_song.m4a

#EXTINF:127,The Sample Band - My 127sec Song
my_127sec_song.m4a

<etc.>

*****/


class M3uPlaylist {
    std::vector<std::string> _entries;

public:
    void addEntry(long duration, NSString *artist, NSString *title, NSString *location){
        // todo, make location relative path
        NSString *entry = [NSString stringWithFormat: @"#EXTINF:%ld, %@ - %@\n%@\n", duration, artist, title, location];
        _entries.push_back([entry cStringUsingEncoding:(NSUTF8StringEncoding)]);
    }

    // save the playlist is .m3u format at the specified location
    bool save(NSURL *location){
        std::ofstream f(location.fileSystemRepresentation);
        f << "#EXTM3U\n";
        for (auto const &entry : _entries) {
            f << entry;
        }
        return true;
    }
};





#endif /* m3u_playlist_hpp */
