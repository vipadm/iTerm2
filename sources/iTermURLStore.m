//
//  iTermURLStore.m
//  iTerm2
//
//  Created by George Nachman on 3/19/17.
//
//

#import "iTermURLStore.h"

#import "DebugLogging.h"

#import <Cocoa/Cocoa.h>

@implementation iTermURLStore {
    // { "url": NSURL.absoluteString, "params": NSString } -> @(NSInteger)
    NSMutableDictionary<NSDictionary *, NSNumber *> *_store;

    // @(unsigned int) -> { "url": NSURL, "params": NSString }
    NSMutableDictionary<NSNumber *, NSDictionary *> *_reverseStore;

    NSCountedSet<NSNumber *> *_referenceCounts;

    // Will never be zero.
    NSInteger _nextCode;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

+ (unsigned int)successor:(unsigned int)n {
    if (n == UINT_MAX - 1) {
        return 1;
    }
    return n + 1;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _store = [NSMutableDictionary dictionary];
        _reverseStore = [NSMutableDictionary dictionary];
        _referenceCounts = [NSCountedSet set];
        _nextCode = 1;
    }
    return self;
}

- (void)retainCode:(unsigned int)code {
    @synchronized (self) {
        _generation++;
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp invalidateRestorableState];
        });
        [_referenceCounts addObject:@(code)];
    }
}

- (void)releaseCode:(unsigned int)code {
    @synchronized (self) {
        _generation++;
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp invalidateRestorableState];
        });
        [_referenceCounts removeObject:@(code)];
        if (![_referenceCounts containsObject:@(code)]) {
            NSDictionary *dict = _reverseStore[@(code)];
            [_reverseStore removeObjectForKey:@(code)];
            NSString *url = [dict[@"url"] absoluteString];
            NSString *params = dict[@"params"];
            if (url) {
                [_store removeObjectForKey:@{ @"url": url, @"params": params }];
            }
        }
    }
}

- (unsigned int)codeForURL:(NSURL *)url withParams:(NSString *)params {
    @synchronized (self) {
        if (!url.absoluteString || !params) {
            DLog(@"codeForURL:%@ withParams:%@ returning 0 because of nil value", url.absoluteString, params);
            return 0;
        }
        NSDictionary *key = @{ @"url": url.absoluteString, @"params": params };
        NSNumber *number = _store[key];
        if (number) {
            return number.unsignedIntValue;
        }
        if (_reverseStore.count == USHRT_MAX - 1) {
            DLog(@"Ran out of URL storage. Refusing to allocate a code.");
            return 0;
        }
        // Advance _nextCode to the next unused code. This will not normally happen - only on wraparound.
        while (_reverseStore[@(_nextCode)]) {
            _nextCode = [iTermURLStore successor:_nextCode];
        }

        // Save it and advance.
        number = @(_nextCode);
        _nextCode = [iTermURLStore successor:_nextCode];

        // Record the code/URL+params relation.
        _store[key] = number;
        _reverseStore[number] = @{ @"url": url, @"params": params };

        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp invalidateRestorableState];
        });
        _generation++;
        return number.unsignedIntValue;
    }
}

- (NSURL *)urlForCode:(unsigned int)code {
    @synchronized (self) {
        if (code == 0) {
            // Safety valve in case something goes awry. There should never be an entry at 0.
            return nil;
        }
        return _reverseStore[@(code)][@"url"];
    }
}

- (NSString *)paramsForCode:(unsigned int)code {
    @synchronized (self) {
        if (code == 0) {
            // Safety valve in case something goes awry. There should never be an entry at 0.
            return nil;
        }
        return _reverseStore[@(code)][@"params"];
    }
}

- (NSString *)paramWithKey:(NSString *)key forCode:(unsigned int)code {
    NSString *params = [self paramsForCode:code];
    if (!params) {
        return nil;
    }
    return iTermURLStoreGetParamForKey(params, key);
}

static NSString *iTermURLStoreGetParamForKey(NSString *params, NSString *key) {
    NSArray<NSString *> *parts = [params componentsSeparatedByString:@":"];
    for (NSString *part in parts) {
        NSInteger i = [part rangeOfString:@"="].location;
        if (i != NSNotFound) {
            NSString *partKey = [part substringToIndex:i];
            if ([partKey isEqualToString:key]) {
                return [part substringFromIndex:i + 1];
            }
        }
    }
    return nil;
}

- (NSDictionary *)dictionaryValue {
    @synchronized (self) {
        NSError *error = nil;
        NSData *encodedRefcounts = [NSKeyedArchiver archivedDataWithRootObject:_referenceCounts
                                                         requiringSecureCoding:YES
                                                                         error:&error];
        if (error) {
            DLog(@"Encoding refcounts failed with error %@:\n%@", error, _referenceCounts);
            encodedRefcounts = [NSData data];
        }

        return @{ @"store": _store,
                  @"refcounts2": encodedRefcounts };
    }
}

- (void)loadFromDictionary:(NSDictionary *)dictionary {
    @synchronized (self) {
        NSDictionary *store = dictionary[@"store"];
        NSData *refcounts = dictionary[@"refcounts"];  // deprecated
        NSData *refcounts2 = dictionary[@"refcounts2"];

        if (!store || (!refcounts && !refcounts2)) {
            DLog(@"URLStore restoration dictionary missing value");
            DLog(@"store=%@", store);
            DLog(@"refcounts=%@", refcounts);
            DLog(@"refcounts2=%@", refcounts2);
            return;
        }
        [store enumerateKeysAndObjectsUsingBlock:^(NSDictionary * _Nonnull key, NSNumber * _Nonnull obj, BOOL * _Nonnull stop) {
            if (![key isKindOfClass:[NSDictionary class]] ||
                ![obj isKindOfClass:[NSNumber class]]) {
                ELog(@"Unexpected types when loading dictionary: %@ -> %@", key.class, obj.class);
                return;
            }
            NSURL *url = [NSURL URLWithString:key[@"url"]];
            if (url == nil) {
                XLog(@"Bogus key not a URL: %@", url);
                return;
            }
            self->_store[key] = obj;

            self->_reverseStore[obj] = @{ @"url": url, @"params": key[@"params"] ?: @"" };
            self->_nextCode = [iTermURLStore successor:MAX(obj.unsignedIntValue, self->_nextCode)];
        }];

        NSError *error = nil;
        _referenceCounts = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithArray:@[ [NSCountedSet class], [NSNumber class] ]]
                                                               fromData:refcounts2
                                                                  error:&error] ?: [[NSCountedSet alloc] init];
        if (error) {
            _referenceCounts = [self legacyDecodedRefcounts:dictionary];
            NSLog(@"Failed to decode refcounts from data %@", refcounts2);
            return;
        }
    }
}

- (NSCountedSet *)legacyDecodedRefcounts:(NSDictionary *)dictionary {
    NSData *refcounts = dictionary[@"refcounts"];
    if (!refcounts) {
        return [[NSCountedSet alloc] init];
    }
    // TODO: Remove this after the old format is no longer around. Probably safe to do around mid 2023.
    NSError *error = nil;
    NSKeyedUnarchiver *decoder = [[NSKeyedUnarchiver alloc] initForReadingFromData:refcounts error:&error];
    if (error) {
        NSLog(@"Failed to decode refcounts from data %@", refcounts);
        return [[NSCountedSet alloc] init];
    }
    return [[NSCountedSet alloc] initWithCoder:decoder] ?: [[NSCountedSet alloc] init];
}

@end
