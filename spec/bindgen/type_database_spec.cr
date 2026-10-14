require "../spec_helper"

private def parse(*args)
  Bindgen::Parser::Type.parse(*args)
end

private def new_database
  Bindgen::TypeDatabase.new(Bindgen::TypeDatabase::Configuration.new, "boehmgc-cpp", with_builtins: false)
end

describe Bindgen::TypeDatabase do
  db = new_database
  db.add("CppType", cpp_type: "TheCppType", generate_wrapper: false)
  db.add("foo", crystal_type: "value")
  db.add("foo *", crystal_type: "pointer")
  db.add("bar", crystal_type: "bar-value")

  describe "type lookup" do
    context "type decay matching" do
      it "decays 'bar *' to 'bar'" do
        db[parse("bar *")].crystal_type.should eq("bar-value")
      end

      it "decays 'bar &' to 'bar'" do
        db[parse("bar *")].crystal_type.should eq("bar-value")
      end

      it "matches 'foo *' to 'foo *'" do
        db[parse("foo *")].crystal_type.should eq("pointer")
      end

      it "matches 'foo' to 'foo'" do
        db[parse("foo")].crystal_type.should eq("value")
      end
    end

    context "aliasing" do
      db.add_alias("Aliaser", alias_for: "Aliasee")
      db.add("Aliasee", crystal_type: "aliased-thing")

      it "detects recursive aliases" do
        expect_raises(Exception, /recursive type alias/i) do
          db.add_alias("Recursive", alias_for: "Recursive")
        end
        expect_raises(Exception, /recursive type alias/i) do
          db.add_alias("T", alias_for: "T *")
        end
        expect_raises(Exception, /recursive type alias/i) do
          db.add_alias("T", alias_for: "Temp<T>")
        end

        expect_raises(Exception, /recursive type alias/i) do
          db2 = new_database
          db2.add_alias("T", alias_for: "U")
          db2.add_alias("U", alias_for: "T")
        end
        expect_raises(Exception, /recursive type alias/i) do
          db2 = new_database
          db2.add_alias("T", alias_for: "U *")
          db2.add_alias("U", alias_for: "T *")
        end
      end

      it "finds aliased type-name" do
        db["Aliaser"].crystal_type.should eq("aliased-thing")
      end

      it "finds aliased type" do
        db[parse("Aliaser")].crystal_type.should eq("aliased-thing")
      end

      it "finds recursive aliased type" do
        db.add_alias("Aliaserer", alias_for: "Aliaser")
        db[parse("Aliaserer")].crystal_type.should eq("aliased-thing")

        db.add("temp<Aliasee>", crystal_type: "temp-aliasee")
        db[parse("temp<Aliaserer>")].crystal_type.should eq("temp-aliasee")
      end
    end
  end

  describe "#[]" do
    it "raises if type name not found" do
      expect_raises(KeyError) do
        db["DoesntExist"]
      end
    end

    it "raises if type not found" do
      expect_raises(KeyError) do
        db[parse("DoesntExist *")]
      end
    end
  end

  describe "#try_or" do
    context "the rule doesn't exist" do
      it "returns the default" do
        db.try_or("DoesntExist", "default", &.cpp_type).should eq("default")
      end

      it "supports false as default value" do
        db.try_or("", false, &.generate_wrapper?).should be_false
      end
    end

    context "the field is nil" do
      it "returns the default" do
        db.try_or("foo", "default", &.cpp_type).should eq("default")
      end
    end

    context "the rules exist and the field is set" do
      it "returns the field" do
        db.try_or("CppType", "default", &.cpp_type).should eq("TheCppType")
      end

      it "supports false as field value" do
        db.try_or("CppType", true, &.generate_wrapper?).should be_false
      end
    end
  end

  describe "#get_or_add" do
    it "returns the rules" do
      db.get_or_add("CppType").cpp_type.should eq("TheCppType")
    end

    it "creates and returns new rules" do
      db2 = new_database
      db2["NewRules"]?.should be_nil
      new_rules = db2.get_or_add("NewRules")
      db2["NewRules"]?.should be(new_rules)
    end
  end

  describe "#add_sparse_type" do
    config = Bindgen::TypeDatabase::Configuration.from_yaml(<<-YAML)
      Implicit: { sub_class: false }
      Explicit: { kind: Struct }
      YAML

    sparse = Bindgen::TypeDatabase.new(config, "boehmgc-cpp", with_builtins: false)
    sparse.add_sparse_type("Implicit", "Implicit", Bindgen::Parser::Type::Kind::Enum)
    sparse.add_sparse_type("Explicit", "Explicit", Bindgen::Parser::Type::Kind::Enum)
    sparse.add_sparse_type("New", "New", Bindgen::Parser::Type::Kind::Enum)

    it "sets the kind of a type configured without one" do
      sparse["Implicit"].kind.should eq(Bindgen::Parser::Type::Kind::Enum)
    end

    it "keeps an explicitly configured kind" do
      sparse["Explicit"].kind.should eq(Bindgen::Parser::Type::Kind::Struct)
    end

    it "sets the kind of a new type" do
      sparse["New"].kind.should eq(Bindgen::Parser::Type::Kind::Enum)
    end
  end

  describe "C arrays" do
    arrays = new_database
    arrays.add("Item", graph_node: Bindgen::Graph::Class.new(Bindgen::Parser::Class.new(name: "Item"), "Item"))
    arrays.add("Hidden", generate_wrapper: false)
    arrays.add("Color", kind: Bindgen::Parser::Type::Kind::Enum)
    arrays.add("Grid", copy_structure: true)

    builtin = Bindgen::Parser::Type.new(
      base_name: "int", full_name: "int [4]", const: false, reference: false,
      pointer: 1, builtin: true, extents: [4_u64],
    )

    describe "#c_array_supported?" do
      it "supports arrays of built-in types" do
        arrays.c_array_supported?(builtin).should be_true
      end

      it "supports arrays and references to arrays of other types by value" do
        %w[Item Color Grid].each do |name|
          arrays.c_array_supported?(parse("#{name} [3]")).should be_true
          arrays.c_array_supported?(parse("const #{name} (&)[3]")).should be_true
        end
      end

      it "doesn't support other arrays" do
        arrays.c_array_supported?(parse("Item []")).should be_false
        arrays.c_array_supported?(parse("Item *[3]")).should be_false
        arrays.c_array_supported?(parse("Item [3] *")).should be_false
        arrays.c_array_supported?(parse("Item [2][3]")).should be_false
        arrays.c_array_supported?(parse("Hidden [3]")).should be_false
        arrays.c_array_supported?(parse("Unknown [3]")).should be_false
      end
    end

    describe "#array_view?" do
      it "is true for arrays of wrapped classes" do
        arrays.array_view?(parse("Item [3]")).should be_true
        arrays.array_view?(parse("const Item [3]")).should be_true
      end

      it "is false for other arrays" do
        arrays.array_view?(builtin).should be_false
        arrays.array_view?(parse("Color [3]")).should be_false
        arrays.array_view?(parse("Grid [3]")).should be_false
        arrays.array_view?(parse("Item [2][3]")).should be_false
        arrays.array_view?(parse("Item (&)[3]")).should be_false
      end
    end
  end
end
