#import "RMRemo.h"

#if TARGET_OS_IOS

@import CRemo;

#if DEBUG

/// Trampoline that bridges C callback → ObjC block.
static char *RMRemoTrampoline(void *context, const char *paramsJson) {
    RMRemoCapabilityHandler handler = (__bridge RMRemoCapabilityHandler)context;

    NSDictionary *params = @{};
    if (paramsJson) {
        NSData *data = [NSData dataWithBytes:paramsJson length:strlen(paramsJson)];
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([parsed isKindOfClass:[NSDictionary class]]) {
            params = parsed;
        }
    }

    NSDictionary *result = handler(params);

    NSData *resultData = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    if (!resultData) {
        return strdup("{\"error\":\"serialization failed\"}");
    }

    NSString *resultString = [[NSString alloc] initWithData:resultData encoding:NSUTF8StringEncoding];
    return strdup(resultString.UTF8String);
}

@implementation RMRemo

static dispatch_once_t _startOnce;

+ (uint16_t)defaultPort {
    return 9930;
}

+ (uint16_t)port {
    [self ensureStarted];
    return remo_get_port();
}

+ (void)ensureStarted {
    dispatch_once(&_startOnce, ^{
#if TARGET_OS_SIMULATOR
        remo_start(0);
#else
        remo_start(self.defaultPort);
#endif
    });
}

+ (void)startWithPort:(uint16_t)port {
    remo_start(port);
}

+ (void)start {
    [self startWithPort:self.defaultPort];
}

+ (void)stop {
    remo_stop();
}

+ (void)registerCapability:(NSString *)name handler:(RMRemoCapabilityHandler)handler {
    [self ensureStarted];

    // Prevent the block from being deallocated.
    RMRemoCapabilityHandler copied = [handler copy];
    void *context = (__bridge_retained void *)copied;

    remo_register_capability(name.UTF8String, context, RMRemoTrampoline);
}

+ (BOOL)unregisterCapability:(NSString *)name {
    return remo_unregister_capability(name.UTF8String);
}

+ (NSArray<NSString *> *)listCapabilities {
    [self ensureStarted];

    char *json = remo_list_capabilities();
    if (!json) return @[];

    NSData *data = [NSData dataWithBytes:json length:strlen(json)];
    remo_free_string(json);

    NSArray *arr = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([arr isKindOfClass:[NSArray class]]) {
        return arr;
    }
    return @[];
}

@end

#else

// Release build: no-op stubs.
@implementation RMRemo

+ (uint16_t)defaultPort { return 9930; }
+ (uint16_t)port { return 0; }
+ (void)ensureStarted {}
+ (void)startWithPort:(uint16_t)port {}
+ (void)start {}
+ (void)stop {}
+ (void)registerCapability:(NSString *)name handler:(RMRemoCapabilityHandler)handler {}
+ (BOOL)unregisterCapability:(NSString *)name { return NO; }
+ (NSArray<NSString *> *)listCapabilities { return @[]; }

@end

#endif // DEBUG

#else // not TARGET_OS_IOS

// macOS stub — RemoObjC is an iOS-only library; this stub satisfies the
// compiler when building for macOS (e.g. running `swift test`).
@implementation RMRemo

+ (uint16_t)defaultPort { return 9930; }
+ (uint16_t)port { return 0; }
+ (void)ensureStarted {}
+ (void)startWithPort:(uint16_t)port {}
+ (void)start {}
+ (void)stop {}
+ (void)registerCapability:(NSString *)name handler:(RMRemoCapabilityHandler)handler {}
+ (BOOL)unregisterCapability:(NSString *)name { return NO; }
+ (NSArray<NSString *> *)listCapabilities { return @[]; }

@end

#endif // TARGET_OS_IOS
