require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../shared/join', __FILE__)
require 'uri'

describe "URI.join" do
  it_behaves_like :uri_join, :join, URI
end
