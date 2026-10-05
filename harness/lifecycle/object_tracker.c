#include "object_tracker.h"
#include <stdio.h>
void object_create(uint64_t id,const char *type){printf("OBJ CREATE %llu %s\n",(unsigned long long)id,type);}
void object_ref(uint64_t id){printf("OBJ REF %llu\n",(unsigned long long)id);}
void object_unref(uint64_t id){printf("OBJ UNREF %llu\n",(unsigned long long)id);}
void object_destroy(uint64_t id){printf("OBJ DESTROY %llu\n",(unsigned long long)id);}
