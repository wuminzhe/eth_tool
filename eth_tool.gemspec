
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "eth_tool/version"

Gem::Specification.new do |spec|
  spec.name          = "eth_tool"
  spec.version       = EthTool::VERSION
  spec.authors       = ["Wu Minzhe"]
  spec.email         = ["wuminzhe@gmail.com"]

  spec.summary       = "my eth tool"
  spec.description   = "my eth tool"
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_dependency "bip44", "~> 0.2.14"
  spec.add_dependency "ethereum.rb", "~> 2.1.8"
  
  
end
