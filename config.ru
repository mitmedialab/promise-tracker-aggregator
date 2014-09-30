require 'bundler/setup'
Bundler.require(:default)
 
require File.dirname(__FILE__) + "/lib/api.rb"
 
map '/' do
  run PTApi
end