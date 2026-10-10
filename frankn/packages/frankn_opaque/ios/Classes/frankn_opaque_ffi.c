#include "frankn_opaque_ffi.h"

extern char *frankn_opaque_client_start(const uint8_t *, size_t, const char *, const char *);
extern char *frankn_opaque_client_finish(uint64_t, const uint8_t *, size_t);
extern void frankn_opaque_client_cancel(uint64_t);
extern void frankn_opaque_string_free(char *);

__attribute__((visibility("default")))
char *frankn_opaque_ios_client_start(const uint8_t *password, size_t password_len,
                                     const char *client_id, const char *host_id) {
  return frankn_opaque_client_start(password, password_len, client_id, host_id);
}

__attribute__((visibility("default")))
char *frankn_opaque_ios_client_finish(uint64_t handle, const uint8_t *response,
                                      size_t response_len) {
  return frankn_opaque_client_finish(handle, response, response_len);
}

__attribute__((visibility("default")))
void frankn_opaque_ios_client_cancel(uint64_t handle) {
  frankn_opaque_client_cancel(handle);
}

__attribute__((visibility("default")))
void frankn_opaque_ios_string_free(char *value) {
  frankn_opaque_string_free(value);
}
