#include <stddef.h>
#include <stdint.h>

char *frankn_opaque_ios_client_start(const uint8_t *password, size_t password_len,
                                     const char *client_id, const char *host_id);
char *frankn_opaque_ios_client_finish(uint64_t handle, const uint8_t *response,
                                      size_t response_len);
void frankn_opaque_ios_client_cancel(uint64_t handle);
void frankn_opaque_ios_string_free(char *value);
