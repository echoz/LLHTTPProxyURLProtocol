# LLHTTPProxyURLProtocol

This is a `NSURLProtocol` subclass that allows NSURLRequests to be sent over a specified proxy. Because it is a `NSURLProtocol`, regular libraries that make use of `NSURLConnection` for URL loading should be able to transparently use it.

It will take over URL loading for any `NSURLRequest` that has set the proxy server address property.

## Proxy Support
Currently it supports the following types of proxies (that are available in CFNetwork)

- Socks 4
- Socks 5
- HTTP
- HTTPS

Proxy auto configuration via a URL will also be eventually supported.

## Design Goals

- Allow transparent usage of NSURLConnection
- Support `http` and `https` URL loading
- Low memory usage (file streaming)
- Full support for `NSURLAuthenticationChallenge` type events

## Todo

- Figure out how to get `NSURLProtectionSpace` that is for SSL connections (It seems we need to go lower level and implement our own CFHTTPStream: https://developer.apple.com/library/ios/technotes/tn2232/_index.html#//apple_ref/doc/uid/DTS40012884-CH1-CFHTTPSTREAM)
