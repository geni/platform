require "test_helper"

class PlatformTest < Platform::TestCase
  test "it has a version number" do
    assert Platform::VERSION
  end
end
