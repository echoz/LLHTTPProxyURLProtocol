//
//  LLHTTPProxyURLProtocol.h
//  HTTPProxyURLProtocol
//
//  Created by Jeremy Foo on 2/8/14.
//  Copyright (c) 2014 Jeremy Foo. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString *const LLHTTPProxyURLProtocolProxyServerKey;

// Supports socks proxies by using socks scheme
// socks4://user:pass@server:port
// socks5://user:pass@server:port
// http://user:pass@server:port
// https://user:pass@server:port

@interface LLHTTPProxyURLProtocol : NSURLProtocol <NSURLAuthenticationChallengeSender>
@property (nonatomic, strong, readonly) NSInputStream *HTTPResponseStream;
@property (nonatomic, strong, readonly) NSHTTPURLResponse *HTTPURLResponse;
@property (nonatomic, assign, readonly) CFHTTPMessageRef responseMessage;
@property (nonatomic, assign, readonly) CFHTTPMessageRef requestMessage;
@end

@interface NSURLRequest (LLHTTPProxyURLProtocol)
@property (nonatomic, readonly) BOOL validatesCertificateChain;
@property (nonatomic, readonly) NSArray *certificateChain;
@property (nonatomic, readonly) NSURL *proxyServerURL;
@end

@interface NSMutableURLRequest (LLHTTPProxyURLProtocol)
@property (nonatomic, assign) BOOL validatesCertificateChain;
@property (nonatomic, copy) NSArray *certificateChain;
@property (nonatomic, copy) NSURL *proxyServerURL;
@end