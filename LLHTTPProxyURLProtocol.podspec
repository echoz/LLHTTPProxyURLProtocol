Pod::Spec.new do |s|

  s.name         = "LLHTTPProxyURLProtocol"
  s.version      = "0.0.1"
  s.summary      = "NSURLProtocol that lets you send NSURLRequests over a HTTP/HTTPS/SOCKS proxy server"

  s.description  = <<-DESC
                   NSURLConnection is great but it doesn't allow you to send requests over a proxy server.
				   LLHTTPProxyURLProtocol is designed to be a transparent layer for NSURLConnection such
				   that you can specify a proxy server along with credentials and push the request through
				   that proxy server.
				   
				   It uses the lower level CFReadStreamRef APIs to achieve this magic.

				   Tested to support
                   * HTTP Proxies (with authentication)
				   
				   Theoratically supports
                   * Socks Proxies (with authentication)
                   * HTTPS Proxies
                   DESC

  s.homepage     = "https://github.com/echoz/LLHTTPProxyURLProtocol"

  s.license      = { :type => 'MIT' }
  s.author       = { "Jeremy Foo" => "jeremy@lazylabs.co" }

  s.ios.deployment_target = "5.0"
  s.osx.deployment_target = "10.7"

  s.source       = { :git => "http://github.com/echoz/LLHTTPProxyURLProtocol.git", :tag => "0.0.1" }
  
  s.source_files  = "LLHTTPProxyURLProtocol/*.{h,m}"

  s.requires_arc = true

end
