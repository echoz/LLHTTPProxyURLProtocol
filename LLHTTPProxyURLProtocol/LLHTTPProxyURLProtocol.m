//
//  LLHTTPProxyURLProtocol.m
//  HTTPProxyURLProtocol
//
//  Created by Jeremy Foo on 2/8/14.
//  Copyright (c) 2014 Jeremy Foo. All rights reserved.
//

#import "LLHTTPProxyURLProtocol.h"

#define HTTP_HEADER_MAX_LENGTH                                      16384
NSString *const LLHTTPProxyURLProtocolProxyServerKey                = @"co.lazylabs.LLHTTPProxyURLProtocol.proxy.address";

@interface LLHTTPProxyURLProtocol () <NSStreamDelegate>
@property (nonatomic, assign) NSUInteger authFailureCount;
@property (nonatomic, strong) NSURLAuthenticationChallenge *authChallenge;
@property (nonatomic, strong) NSURLCredential *internalHTTPProxyCredential;
@end

@implementation LLHTTPProxyURLProtocol
@synthesize HTTPResponseStream = _HTTPResponseStream;
@synthesize requestMessage = _requestMessage;

+(BOOL)canInitWithRequest:(NSURLRequest *)request {
    if (![request.URL.scheme hasPrefix:@"http"]) return NO;
    return ([[NSURLProtocol propertyForKey:LLHTTPProxyURLProtocolProxyServerKey inRequest:request] isKindOfClass:[NSURL class]]);
}
+(NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }

#pragma mark - Object Life Cycle

-(id)initWithRequest:(NSURLRequest *)request cachedResponse:(NSCachedURLResponse *)cachedResponse client:(id<NSURLProtocolClient>)client {
    if ((self = [super initWithRequest:request cachedResponse:cachedResponse client:client])) {
        _authFailureCount = 0;

        if ([request.proxyServerURL.scheme hasPrefix:@"http"])
            self.internalHTTPProxyCredential = [NSURLCredential credentialWithUser:request.proxyServerURL.user password:request.proxyServerURL.password persistence:NSURLCredentialPersistenceNone];

    }
    return self;
}

-(void)dealloc {
    [self stopLoading];
    if (_responseMessage) CFRelease(_responseMessage), _responseMessage = NULL;
    if (_requestMessage) CFRelease(_requestMessage), _requestMessage = NULL;
}

#pragma mark - Properties

-(CFHTTPMessageRef)requestMessage {
    if (_requestMessage == NULL) {
        CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)[self.request.URL absoluteString], NULL);
        _requestMessage = CFHTTPMessageCreateRequest(kCFAllocatorDefault, (__bridge CFStringRef)self.request.HTTPMethod, url, kCFHTTPVersion1_1);

        // build headers
        for (NSString *header in [self.request allHTTPHeaderFields])
            CFHTTPMessageSetHeaderFieldValue(self.requestMessage, (__bridge CFStringRef)header, (__bridge CFStringRef)([[self.request allHTTPHeaderFields] objectForKey:header]));
    }
    return _requestMessage;
}

-(NSInputStream *)HTTPResponseStream {
    if (!_HTTPResponseStream) {
        // create read stream for CFHTTPStream
        CFReadStreamRef requestReadStream = NULL;

        if (self.request.HTTPBodyStream) {
            requestReadStream = CFReadStreamCreateForStreamedHTTPRequest(kCFAllocatorDefault, self.requestMessage, (__bridge CFReadStreamRef)(self.request.HTTPBodyStream));
        } else {
            NSData *body = ([self.request.HTTPBody length] == 0) ? [NSData data] : self.request.HTTPBody;
            CFHTTPMessageSetBody(self.requestMessage, (__bridge CFDataRef)body);
            requestReadStream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, self.requestMessage);
        }

        CFReadStreamSetProperty(requestReadStream, kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanFalse);

        // proxy settings
        NSAssert1([[NSURLProtocol propertyForKey:LLHTTPProxyURLProtocolProxyServerKey inRequest:self.request] isKindOfClass:[NSURL class]], @"Proxy server specified must be in the form of an NSURL: %@", [NSURLProtocol propertyForKey:LLHTTPProxyURLProtocolProxyServerKey inRequest:self.request]);
        NSURL *proxyURL = [NSURLProtocol propertyForKey:LLHTTPProxyURLProtocolProxyServerKey inRequest:self.request];
        NSAssert1([proxyURL.scheme hasPrefix:@"socks"] || [proxyURL.scheme hasPrefix:@"http"], @"Proxy Servers supported only include socks, https and http: %@", proxyURL.scheme);

        NSDictionary *proxySettings = nil;
        if ([proxyURL.scheme hasPrefix:@"socks"]) {
            NSAssert1([proxyURL.scheme hasPrefix:@"socks5"] || [proxyURL.scheme hasPrefix:@"socks4"], @"Only SOCKS5 and SOCKS4 proxy servers are supported: %@", proxyURL.scheme);

            NSMutableDictionary *socksSettings = [NSMutableDictionary dictionaryWithDictionary:@{(NSString *)kCFStreamPropertySOCKSProxyHost: proxyURL.host, (NSString *)kCFStreamPropertySOCKSProxyPort: proxyURL.port}];
            if (proxyURL.user)      [socksSettings setObject:proxyURL.user forKey:(NSString *)kCFStreamPropertySOCKSUser];
            if (proxyURL.password)  [socksSettings setObject:proxyURL.password forKey:(NSString *)kCFStreamPropertySOCKSPassword];
            [socksSettings setObject:([proxyURL.scheme hasPrefix:@"socks5"]) ? (NSString *)kCFStreamSocketSOCKSVersion5 : (NSString *)kCFStreamSocketSOCKSVersion4
                              forKey:(NSString *)kCFStreamPropertySOCKSVersion];

            proxySettings = socksSettings;
        } else if ([proxyURL.scheme hasPrefix:@"https"]) {
            proxySettings = @{(NSString *)kCFStreamPropertyHTTPSProxyHost: proxyURL.host, (NSString *)kCFStreamPropertyHTTPSProxyPort: proxyURL.port};
        } else {
            proxySettings = @{(NSString *)kCFStreamPropertyHTTPProxyHost: proxyURL.host, (NSString *)kCFStreamPropertyHTTPProxyPort: proxyURL.port};
        }

        if (proxySettings) CFReadStreamSetProperty(requestReadStream, kCFStreamPropertyHTTPProxy, (__bridge CFTypeRef)(proxySettings));

        // set pipelining support
        CFReadStreamSetProperty(requestReadStream, kCFStreamPropertyHTTPAttemptPersistentConnection, (__bridge CFTypeRef)(@(self.request.HTTPShouldUsePipelining)));
        
        // set cellular access
        CFReadStreamSetProperty(requestReadStream, kCFStreamPropertyNoCellular, (__bridge CFTypeRef)(@(!self.request.allowsCellularAccess)));

        // set SSL preferences
        CFReadStreamSetProperty(requestReadStream, kCFStreamSSLValidatesCertificateChain, (__bridge CFTypeRef)@(self.request.validatesCertificateChain));
        if (self.request.certificateChain) CFReadStreamSetProperty(requestReadStream, kCFStreamSSLCertificates, (__bridge CFArrayRef)(self.request.certificateChain));

        // service type

        if (self.request.networkServiceType == NSURLNetworkServiceTypeVoIP) CFReadStreamSetProperty(requestReadStream, kCFStreamNetworkServiceType, kCFStreamNetworkServiceTypeVoIP);
        if (self.request.networkServiceType == NSURLNetworkServiceTypeVideo) CFReadStreamSetProperty(requestReadStream, kCFStreamNetworkServiceType, kCFStreamNetworkServiceTypeVideo);
        if (self.request.networkServiceType == NSURLNetworkServiceTypeVoice) CFReadStreamSetProperty(requestReadStream, kCFStreamNetworkServiceType, kCFStreamNetworkServiceTypeVoice);
        if (self.request.networkServiceType == NSURLNetworkServiceTypeBackground) CFReadStreamSetProperty(requestReadStream, kCFStreamNetworkServiceType, kCFStreamNetworkServiceTypeBackground);

        _HTTPResponseStream = (__bridge NSInputStream *)(requestReadStream);
    }
    return _HTTPResponseStream;
}

#pragma mark - Networking Event

-(void)startLoading {
    [self stopLoading];

    self.authChallenge = nil;
    if (_responseMessage) CFRelease(_responseMessage), _responseMessage = NULL;
    _HTTPURLResponse = nil;

    self.HTTPResponseStream.delegate = self;
    [self.HTTPResponseStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.HTTPResponseStream open];
}

-(void)stopLoading {
    if (!_HTTPResponseStream) return;

    self.HTTPResponseStream.delegate = nil;
    [self.HTTPResponseStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.HTTPResponseStream close], _HTTPResponseStream = nil;
}

#pragma mark - Authentication Delegate

-(void)_restartLoadingWithCredential:(NSURLCredential *)credential {
    CFHTTPMessageAddAuthentication(self.requestMessage, self.responseMessage, (__bridge CFStringRef)(credential.user), (__bridge CFStringRef)(credential.password), NULL, YES);
    [self startLoading];
}

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    if (self.authChallenge != challenge) return;
    [self _restartLoadingWithCredential:credential];
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    _HTTPResponseStream = nil;
    [self startLoading];
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    // return auth error
    [self stopLoading];
    [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUserCancelledAuthentication userInfo:nil]];
}

-(void)performDefaultHandlingForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    [self stopLoading];
    [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:kCFURLErrorUserAuthenticationRequired userInfo:nil]];
}

#pragma mark - Stream Handling

// https://github.com/graetzer/SGURLProtocol
- (NSURLCacheStoragePolicy)cachePolicyForRequest:(NSURLRequest *)request response:(NSHTTPURLResponse *)response {
    BOOL cacheable = NO;
    NSURLCacheStoragePolicy result = NSURLCacheStorageNotAllowed;

    switch (response.statusCode) {
        case 200:
        case 203:
        case 206:
        case 301:
        case 304:
        case 404:
        case 410:
            cacheable = YES;
    }

    // If the response might be cacheable, look at the "Cache-Control" header in
    // the response.
    if (cacheable) {
        NSString *responseHeader = [response.allHeaderFields[@"Cache-Control"] lowercaseString];
        if ( (responseHeader != nil) && [responseHeader rangeOfString:@"no-store"].location != NSNotFound) {
            cacheable = NO;
        }
    }

    // If we still think it might be cacheable, look at the "Cache-Control" header in
    // the request.
    if (cacheable) {
        NSString *requestHeader = [request.allHTTPHeaderFields[@"Cache-Control"] lowercaseString];
        if ( (requestHeader != nil)
            && ([requestHeader rangeOfString:@"no-store"].location != NSNotFound)
            && ([requestHeader rangeOfString:@"no-cache"].location != NSNotFound) ) {
            cacheable = NO;
        }
    }
    if (cacheable) {
        if ([[request.URL.scheme lowercaseString] isEqual:@"https"]) result = NSURLCacheStorageAllowedInMemoryOnly;
        else result = NSURLCacheStorageAllowed;
    }

    return result;
}

-(BOOL)parseHeaderStream:(NSInputStream *)theStream {
    // check response
    _responseMessage = (__bridge CFHTTPMessageRef)[theStream propertyForKey:(NSString *)kCFStreamPropertyHTTPResponseHeader];
    if (!self.responseMessage) return NO;
    if (!CFHTTPMessageIsHeaderComplete(self.responseMessage)) return NO;
    if (self.HTTPURLResponse) return YES;

    CFIndex httpStatusCode = CFHTTPMessageGetResponseStatusCode(self.responseMessage);
    CFStringRef httpVersion = CFHTTPMessageCopyVersion(self.responseMessage);
    CFDictionaryRef httpHeaders = CFHTTPMessageCopyAllHeaderFields(self.responseMessage);
    _HTTPURLResponse = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:httpStatusCode HTTPVersion:(__bridge NSString *)(httpVersion) headerFields:(__bridge NSDictionary *)(httpHeaders)];

    if (httpStatusCode == 304) {
        // there are cached stuff
        NSCachedURLResponse *cached = [[NSURLCache sharedURLCache] cachedResponseForRequest:self.request];
        if (cached) {
            [self.client URLProtocol:self cachedResponseIsValid:cached];
            [self.client URLProtocol:self didReceiveResponse:cached.response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            [self.client URLProtocol:self didLoadData:[cached data]];
            [self.client URLProtocolDidFinishLoading:self];// No http body expected
            [self stopLoading];
            return NO;
        }

        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                                           code:NSURLErrorCannotDecodeContentData
                                                                       userInfo:nil]];
        return NO;
    }

    // handle redirects
    if ((httpStatusCode >= 300) && (httpStatusCode <= 307)) {
        // redirect
        NSMutableURLRequest *newRequest = [self.request mutableCopy];
        newRequest.URL = [[NSURL URLWithString:[self.HTTPURLResponse.allHeaderFields valueForKey:@"Location"] relativeToURL:self.request.URL] absoluteURL];

        NSDictionary *newCookiesHeaderFields = [NSHTTPCookie requestHeaderFieldsWithCookies:[NSHTTPCookie cookiesWithResponseHeaderFields:self.HTTPURLResponse.allHeaderFields forURL:self.HTTPURLResponse.URL]];
        for (NSString *key in newCookiesHeaderFields)
            [newRequest setValue:[newCookiesHeaderFields objectForKey:key] forHTTPHeaderField:key];

        [self.client URLProtocol:self wasRedirectedToRequest:newRequest redirectResponse:self.HTTPURLResponse];
        [self stopLoading];
        return NO;
    }

    // authentication
    NSAssert(!self.authChallenge, @"There is already an authentication challenge happening!");

    if (httpStatusCode == 407) {
        // proxy auth
        NSURL *proxyURL = [NSURLProtocol propertyForKey:LLHTTPProxyURLProtocolProxyServerKey inRequest:self.request];
        if (self.internalHTTPProxyCredential) {
            NSURLCredential *credential = self.internalHTTPProxyCredential;
            self.internalHTTPProxyCredential = nil;
            [self _restartLoadingWithCredential:credential];
            return NO;
        }

        CFHTTPAuthenticationRef authentication = CFHTTPAuthenticationCreateFromResponse(kCFAllocatorDefault, self.responseMessage);
        NSString *proxyType = NSURLProtectionSpaceHTTPProxy;
        if ([proxyURL.scheme hasPrefix:@"socks"]) proxyType = NSURLProtectionSpaceSOCKSProxy;
        if ([proxyURL.scheme hasPrefix:@"https"]) proxyType = NSURLProtectionSpaceHTTPSProxy;

        NSURLProtectionSpace *protectionSpace = [[NSURLProtectionSpace alloc] initWithProxyHost:proxyURL.host
                                                                                           port:[proxyURL.port integerValue]
                                                                                           type:proxyType
                                                                                          realm:(__bridge NSString *)(CFHTTPAuthenticationCopyRealm(authentication))
                                                                           authenticationMethod:(__bridge NSString *)(CFHTTPAuthenticationCopyMethod(authentication))];

        self.authChallenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:protectionSpace
                                                                        proposedCredential:nil
                                                                      previousFailureCount:self.authFailureCount
                                                                           failureResponse:[self.HTTPURLResponse copy]
                                                                                     error:nil
                                                                                    sender:self];

        [self stopLoading];

        [self.client URLProtocol:self didReceiveAuthenticationChallenge:self.authChallenge];
        self.authFailureCount++;
        _HTTPURLResponse = nil;
        return NO;
    }

    if (httpStatusCode == 401) {
        // user auth
        CFHTTPAuthenticationRef authentication = CFHTTPAuthenticationCreateFromResponse(kCFAllocatorDefault, self.responseMessage);
        NSURLProtectionSpace *protectionSpace = [[NSURLProtectionSpace alloc] initWithHost:self.HTTPURLResponse.URL.host
                                                                                      port:[self.HTTPURLResponse.URL.port integerValue]
                                                                                  protocol:self.HTTPURLResponse.URL.scheme
                                                                                     realm:(__bridge NSString *)(CFHTTPAuthenticationCopyRealm(authentication))
                                                                      authenticationMethod:(__bridge NSString *)(CFHTTPAuthenticationCopyMethod(authentication))];

        self.authChallenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:protectionSpace
                                                                        proposedCredential:nil
                                                                      previousFailureCount:self.authFailureCount
                                                                           failureResponse:[self.HTTPURLResponse copy]
                                                                                     error:nil
                                                                                    sender:self];
        [self stopLoading];

        [self.client URLProtocol:self didReceiveAuthenticationChallenge:self.authChallenge];
        self.authFailureCount++;
        _HTTPURLResponse = nil;
        return NO;
    }

    NSURLCacheStoragePolicy policy = [self cachePolicyForRequest:self.request response:self.HTTPURLResponse];
    [self.client URLProtocol:self didReceiveResponse:self.HTTPURLResponse cacheStoragePolicy:policy];

    return YES;
}

-(void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    if (aStream != self.HTTPResponseStream) return;
    NSInputStream *theStream = (NSInputStream *)aStream;

    BOOL proceed = YES;
    if (!self.HTTPURLResponse)
        proceed = [self parseHeaderStream:theStream];

    switch (eventCode) {
        case NSStreamEventHasBytesAvailable: {
            while (theStream.hasBytesAvailable) {
                uint8_t buf[1024];
                NSInteger len = [theStream read:buf maxLength:1024];
                if (len == 0) continue;

                NSData *data = [NSData dataWithBytes:buf length:len];

                if (!proceed) continue;
                [self.client URLProtocol:self didLoadData:data];
            }
        }
            break;

        case NSStreamEventEndEncountered:
            if (!proceed) return;
            [self.client URLProtocolDidFinishLoading:self];
            break;

        case NSStreamEventErrorOccurred:
            if (!proceed) return;

            [self.client URLProtocol:self didFailWithError:aStream.streamError];
            [self stopLoading];
            break;

        default:
            break;
    }
}

@end

#pragma mark - Categories

@implementation NSURLRequest (LLHTTPProxyURLProtocol)
-(NSURL *)proxyServerURL { return [NSURLProtocol propertyForKey:LLHTTPProxyURLProtocolProxyServerKey inRequest:self]; }
-(BOOL)validatesCertificateChain { return ([NSURLProtocol propertyForKey:(NSString *)kCFStreamSSLValidatesCertificateChain inRequest:self]) ? [[NSURLProtocol propertyForKey:(NSString *)kCFStreamSSLValidatesCertificateChain inRequest:self] boolValue] : YES; }
-(NSArray *)certificateChain { return [NSURLProtocol propertyForKey:(NSString *)kCFStreamSSLCertificates inRequest:self]; }
@end

@implementation NSMutableURLRequest (LLHTTPProxyURLProtocol)
-(void)setValidatesCertificateChain:(BOOL)validatesCertificateChain {
    if (self.validatesCertificateChain == validatesCertificateChain) return;
    [NSURLProtocol setProperty:@(validatesCertificateChain) forKey:(NSString *)kCFStreamSSLValidatesCertificateChain inRequest:self];
}

-(void)setCertificateChain:(NSArray *)certificateChain {
    if (self.certificateChain == certificateChain) return;
    [NSURLProtocol setProperty:certificateChain forKey:(NSString *)kCFStreamSSLCertificates inRequest:self];
}

-(void)setProxyServerURL:(NSURL *)proxyServerURL {
    if (!proxyServerURL) {
        [NSURLProtocol removePropertyForKey:LLHTTPProxyURLProtocolProxyServerKey inRequest:self];
        return;
    }

    if ([self.proxyServerURL isEqual:proxyServerURL]) return;
    [NSURLProtocol setProperty:[proxyServerURL copy] forKey:LLHTTPProxyURLProtocolProxyServerKey inRequest:self];
}
@end