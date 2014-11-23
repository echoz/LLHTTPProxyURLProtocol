//
//  LLAppDelegate.m
//  HTTPProxyURLProtocol
//
//  Created by Jeremy Foo on 2/8/14.
//  Copyright (c) 2014 Jeremy Foo. All rights reserved.
//

#import "LLAppDelegate.h"
#import <AFNetworking/AFNetworking.h>
#import "LLHTTPProxyURLProtocol.h"

@implementation LLAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    [NSURLProtocol registerClass:[LLHTTPProxyURLProtocol class]];

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://whatismyipaddress.com"] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0f];
    request.validatesCertificateChain = NO;
    request.proxyServerURL = [NSURL URLWithString:@"http://user:password@proxy.server:port"];
    request.HTTPMethod = @"GET";

    AFHTTPRequestOperation *requestOperation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    [requestOperation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"Succes: (%@) -> %@", operation.response.allHeaderFields, [[NSString alloc] initWithData:responseObject encoding:NSASCIIStringEncoding]);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Failure: %@", error);
    }];

    [requestOperation start];
}

@end
