# frozen_string_literal: true

# Member access (o.name) and index access (a[i]).
RSpec.describe "value access", mutant_expression: "Fusion::CLI*" do
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
        .out("❌", '{"kind":"access_error","origin":"code","file":"<inline>","operation":".nope","status":0,"input":{"name":"bob"},"message":"missing key"}')
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

    it "reads an object key" do
      expect_pipe
        .in("✅", '{"a":1,"b":2}')
        .code('(o => o["b"])')
        .out("✅", "2")
    end

    it "errors when the index is out of range" do
      expect_pipe
        .in("✅", "[10,20,30]")
        .code("(a => a[9])")
        .out("❌", '{"kind":"access_error","origin":"code","file":"<inline>","operation":"[]","status":0,"input":[[10,20,30],9],"message":"index out of range"}')
    end
  end

  describe "index write [=]" do
    it "replaces an array element by index" do
      expect_pipe
        .code("[10, 20, 30][1 = 99]")
        .out("✅", "[10,99,30]")
    end

    it "replaces an array element by negative index" do
      expect_pipe
        .code("[10, 20, 30][-1 = 99]")
        .out("✅", "[10,20,99]")
    end

    it "adds a new object key" do
      expect_pipe
        .code('{"a": 1}["b" = 2]')
        .out("✅", '{"a":1,"b":2}')
    end

    it "overwrites an existing object key" do
      expect_pipe
        .code('{"a": 1}["a" = 9]')
        .out("✅", '{"a":9}')
    end

    it "errors on an out-of-range array index" do
      expect_pipe
        .code("[1, 2][5 = 9]")
        .out("❌", '{"kind":"access_error","origin":"code","file":"<inline>","operation":"[=]","status":0,"input":[[1,2],5,9],"message":"index out of range"}')
    end

    it "errors on a non-collection target" do
      expect_pipe
        .code("5[0 = 1]")
        .out("❌", '{"kind":"argument_error","origin":"code","file":"<inline>","operation":"[=]","status":0,"input":[5,0,1],"expected":["[_ ? @Array, _ ? @Integer, _]","[_ ? @Object, _ ? @String, _]"]}')
    end
  end
end
