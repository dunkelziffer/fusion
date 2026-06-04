# frozen_string_literal: true

# Member access (o.name) and index access (a[i]).
RSpec.describe "value access" do
  describe "member access" do
    it "reads a present key" do
      expect_pipe
        .in("✅", '{"name":"bob"}')
        .code("(o => o.name)")
        .out("✅", '"bob"')
    end

    it "errors on a missing key" do
      expect_pipe
        .in("✅", '{"name":"bob"}')
        .code("(o => o.nope)")
        .out("❌", '{"kind":"missing_key","key":"nope"}')
    end
  end

  describe "index access" do
    it "reads a positive index" do
      expect_pipe
        .in("✅", "[10,20,30]")
        .code("(a => a[1])")
        .out("✅", "20")
    end

    it "reads a negative index from the end" do
      expect_pipe
        .in("✅", "[10,20,30]")
        .code("(a => a[-1])")
        .out("✅", "30")
    end

    it "errors when the index is out of range" do
      expect_pipe
        .in("✅", "[10,20,30]")
        .code("(a => a[9])")
        .out("❌", '{"kind":"index_out_of_range","index":9,"length":3}')
    end
  end
end
