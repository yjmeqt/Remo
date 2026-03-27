#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Callback block for capability handlers.
/// Receives a JSON dictionary, returns a JSON dictionary.
typedef NSDictionary<NSString *, id> *_Nonnull (^RMRemoCapabilityHandler)(NSDictionary<NSString *, id> *_Nonnull params);

/// Remo: remote control bridge for iOS apps (Objective-C interface).
///
/// Zero-config: the server starts automatically on first API access.
/// Simulator builds use a random port; device builds use port 9930.
///
/// In Release builds, all methods are no-ops.
///
/// @code
/// [RMRemo registerCapability:@"navigate" handler:^NSDictionary *(NSDictionary *params) {
///     NSString *route = params[@"route"] ?: @"/";
///     [[Navigator shared] push:route];
///     return @{@"status": @"ok"};
/// }];
/// @endcode
@interface RMRemo : NSObject

/// Default port the Remo server listens on (device builds).
@property (class, nonatomic, readonly) uint16_t defaultPort;

/// The actual port the server is listening on (0 if not started).
@property (class, nonatomic, readonly) uint16_t port;

/// Start the server on a specific port. Normally unnecessary — the server
/// auto-starts on first API access.
+ (void)startWithPort:(uint16_t)port;

/// Start the server on the default port.
+ (void)start;

/// Stop the server.
+ (void)stop;

/// Register a capability that can be invoked from macOS.
+ (void)registerCapability:(NSString *)name handler:(RMRemoCapabilityHandler)handler;

/// Unregister a capability by name.
/// Returns YES if the capability was found and removed.
+ (BOOL)unregisterCapability:(NSString *)name;

/// List all registered capability names.
+ (NSArray<NSString *> *)listCapabilities;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
