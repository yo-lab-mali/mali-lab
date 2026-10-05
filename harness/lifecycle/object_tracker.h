#ifndef OBJECT_TRACKER_H
#define OBJECT_TRACKER_H
#include <stdint.h>
void object_create(uint64_t id, const char *type);
void object_ref(uint64_t id);
void object_unref(uint64_t id);
void object_destroy(uint64_t id);
#endif
