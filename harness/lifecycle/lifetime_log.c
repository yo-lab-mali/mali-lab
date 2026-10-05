#include "lifetime_log.h"
#include <stdio.h>
void lifetime_event(const char *e,uint64_t id){printf("LIFETIME %s %llu\n",e,(unsigned long long)id);}
