//
//  flac_utils.h
//  TeslaTunesCL
//
//  Created by Rob Arnold on 2/12/15.
//  Copyright (c) 2015 Loci Consulting. All rights reserved.
//

#ifndef TeslaTunesCL_flac_utils_h
#define TeslaTunesCL_flac_utils_h


#ifdef __cplusplus
extern "C" {
#endif
    
    BOOL ConvertM4AToFlac(const NSURL* a, const NSURL *f, volatile const BOOL *cancelFlag);
   

#ifdef __cplusplus
}
#endif
#endif
