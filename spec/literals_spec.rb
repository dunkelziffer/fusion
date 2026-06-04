# frozen_string_literal: true

# Array/object literals, spreads, and null-as-ordinary-data.
RSpec.describe "literals and spreads" do
  it "treats null as ordinary data (binds like any value)" do
    expect_pipe
      .in("✅", "null")
      .code("(x => [x, x])")
      .out("✅", "[null,null]")
  end

  it "spreads into an array literal" do
    expect_pipe
      .in("✅", "[1,2]")
      .code("(x => [0, ...x, 9])")
      .out("✅", "[0,1,2,9]")
  end

  it "spreads into an object literal" do
    expect_pipe
      .in("✅", '{"b":2}')
      .code('(x => {"a":1, ...x})')
      .out("✅", '{"a":1,"b":2}')
  end
end
