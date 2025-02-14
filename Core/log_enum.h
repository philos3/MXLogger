//
//  logger_enum.h
//  Logger
//
//  Created by 董家祎 on 2022/3/11.
//

#ifndef log_enum_h
#define log_enum_h


static const char *level_names[]{"DEBUG","INFO","WARN","ERROR","FATAL"};
static const char * level_icons[]{"🟩","🟦","🟨","🟥","❌"};
namespace policy {
enum storage_policy: int {
    yyyy_MM = 0,
    yyyy_ww = 1,
    yyyy_MM_dd = 2,
    yyyy_MM_dd_HH = 3,
};

}

namespace level {
enum   level_enum : int {
    
    debug = 0,
    info = 1,
    warn = 2,
    error = 3,
    fatal = 4,
};



}

#endif /* log_enum_h */
