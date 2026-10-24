require "./spec_helper"

describe "namespaced class hierarchies" do
  it "works" do
    build_and_run("namespaces") do
      it "sets the base-classes correctly" do
        {{ Test::N::A.superclass == Reference }}.should be_true
        {{ Test::B.superclass == Test::N::A }}.should be_true
        {{ Test::N::C.superclass == Test::B }}.should be_true
        {{ Test::N::M::D.superclass == Test::N::C }}.should be_true
        {{ Test::N::Abstract.superclass == Test::N::M::D }}.should be_true
        {{ Test::E.superclass == Test::N::M::D }}.should be_true
        {{ Test::N::M::F.superclass == Test::E }}.should be_true
        {{ Test::N::G.superclass == Test::N::M::F }}.should be_true
        {{ Test::Concrete.superclass == Test::N::Abstract }}.should be_true
      end

      it "inherits methods across namespaces" do
        g = Test::N::G.new
        {g.a, g.b, g.c, g.d, g.e, g.f, g.g}.should eq({1, 2, 3, 4, 5, 6, 7})
      end

      it "nests a class under a wrapped class built after it" do
        Test::Host.new.kind.should eq(Test::Host::Kind::Other)
        Test::Host::Guest.new.value.should eq(3)
      end

      it "supports abstract classes" do
        {{ Test::N::Abstract.abstract? }}.should be_true
        concrete = Test::Concrete.new
        concrete.pure.should eq(8)
        concrete.a.should eq(1)
      end
    end
  end
end
