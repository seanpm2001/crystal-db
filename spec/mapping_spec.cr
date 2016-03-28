require "./spec_helper"
require "base64"

class SimpleMapping
  DB.mapping({
    c0: Int32,
    c1: String
  })
end

class MappingWithDefaults
  DB.mapping({
    c0: { type: Int32, default: 10 },
    c1: { type: String, default: "c" },
  })
end

class MappingWithNilables
  DB.mapping({
    c0: { type: Int32, nilable: true },
    c1: { type: String, nilable: true },
  })
end

class MappingWithKeys
  DB.mapping({
    foo: { type: Int32, key: "c0" },
    bar: { type: String, key: "c1" },
  })
end

class MappingWithConverter

  module Base64Converter
    def self.from_rs(rs)
      Base64.decode(rs.read(String))
    end
  end

  DB.mapping({
    c0: { type: Slice(UInt8), converter: MappingWithConverter::Base64Converter },
    c1: { type: String },
  })
end

macro from_dummy(query, type)
  with_dummy do |db|
    rs = db.query({{ query }})
    rs.move_next
    %obj = {{ type }}.new(rs)
    rs.close
    %obj
  end
end

macro expect_mapping(query, t, values)
  %obj = from_dummy({{ query }}, {{ t }})
  %obj.should be_a({{ t }})
  {% for key, value in values %}
    %obj.{{key.id}}.should eq({{value}})
  {% end %}
end

describe "DB.mapping" do

  it "should initialize a simple mapping" do
    expect_mapping("1,a", SimpleMapping, {c0: 1, c1: "a"})
  end

  it "should fail to initialize a simple mapping if types do not match" do
    expect_raises { from_dummy("b,a", SimpleMapping) }
  end

  it "should fail to initialize a simple mapping if there is a missing column" do
    expect_raises { from_dummy("1", SimpleMapping) }
  end

  it "should fail to initialize a simple mapping if there is an unexpected column" do
    expect_raises { from_dummy("1,a,b", SimpleMapping) }
  end

  it "should initialize a mapping with default values" do
    expect_mapping("1,a", MappingWithDefaults, {c0: 1, c1: "a"})
  end

  it "should initialize a mapping using default values if columns are missing" do
    expect_mapping("1", MappingWithDefaults, {c0: 1, c1: "c"})
  end

  it "should initialize a mapping with nils if columns are missing" do
    expect_mapping("1", MappingWithNilables, {c0: 1, c1: nil})
  end

  it "should initialize a mapping with different keys" do
    expect_mapping("1,a", MappingWithKeys, {foo: 1, bar: "a"})
  end

  it "should initialize a mapping with a value converter" do
    expect_mapping("Zm9v,a", MappingWithConverter, {c0: "foo".to_slice, c1: "a"})
  end

  it "should initialize multiple instances from a single resultset" do
    with_dummy do |db|
      db.query("1,a 2,b") do |rs|
        objs = SimpleMapping.from_rs(rs)
        objs.size.should eq(2)
        objs[0].c0.should eq(1)
        objs[0].c1.should eq("a")
        objs[1].c0.should eq(2)
        objs[1].c1.should eq("b")
      end
    end
  end

end
