# frozen_string_literal: true

# Functions as values: closures and currying.
RSpec.describe "functions" do
  it "returns a function that captures its enclosing scope (closure)" do
    expect_pipe
      .in("✅", "10")
      .code("(n => (m => [n, m] | @add))")
      .out("✅", a_string_starting_with('"<function'))
  end

  it "curries: 10 | (n => (m => n+m)) then applied to 5" do
    expect_pipe
      .in("✅", "[10,5]")
      .code("(pair => pair[0] | (n => (m => [n,m] | @add)) | (g => pair[1] | g))")
      .out("✅", "15")
  end
end
