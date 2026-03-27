#ifndef REMO_H
#define REMO_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Start the Remo TCP server on the given port.
void remo_start(uint16_t port);

/// Stop the Remo server.
void remo_stop(void);

/// Callback signature for capability handlers.
/// - context: opaque pointer (passed back unchanged)
/// - params_json: null-terminated JSON string
/// Returns: a null-terminated JSON string allocated with strdup().
typedef char* (*remo_capability_callback)(void* context, const char* params_json);

/// Register a capability handler.
/// - name: null-terminated capability name
/// - context: opaque pointer passed to callback
/// - callback: function pointer invoked when the capability is called
void remo_register_capability(const char* name,
                              void* context,
                              remo_capability_callback callback);

/// Unregister a capability by name.
/// Returns true if the capability was found and removed.
bool remo_unregister_capability(const char* name);

/// Free a Rust-allocated string.
void remo_free_string(char* ptr);

/// List registered capabilities as a JSON array string.
/// Caller must free with remo_free_string().
char* remo_list_capabilities(void);

/// Return the actual port the server is listening on.
/// Returns 0 if the server has not started.
uint16_t remo_get_port(void);

#ifdef __cplusplus
}
#endif

#endif /* REMO_H */
