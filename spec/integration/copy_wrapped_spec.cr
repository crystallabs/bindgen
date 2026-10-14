require "./spec_helper"

describe "wrapper classes of copied structures" do
  it "works" do
    build_and_run("copy_wrapped") do
      context "aggregate" do
        it "hosts the structure" do
          subject = Test::Pod.new(a: 1, b: 2)
          subject.to_unsafe.should be_a(Pointer(Test::Binding::Pod))

          # The structure is stored inside of the wrapper instance.
          offset = subject.to_unsafe.address - subject.object_id
          (0 <= offset < instance_sizeof(Test::Pod)).should be_true
        end

        it "can be constructed" do
          subject = Test::Pod.new(a: 1, b: 2)
          subject.to_unsafe.value.a.should eq(1)
          subject.to_unsafe.value.b.should eq(2)
        end

        it "has property methods" do
          subject = Test::Pod.new(a: 1, b: 2)
          subject.a.should eq(1)
          subject.b.should eq(2)

          subject.b = 5
          subject.b.should eq(5)
          subject.to_unsafe.value.b.should eq(5)
        end

        it "is passed to and returned from a function by value" do
          result = Test::Funcs.swapped(Test::Pod.new(a: 1, b: 2))
          result.should be_a(Test::Pod)
          result.a.should eq(2)
          result.b.should eq(1)
        end
      end

      context "structure with methods" do
        it "can be constructed" do
          subject = Test::Vec.new
          subject.x.should eq(0)
          subject.y.should eq(0)

          subject = Test::Vec.new(3, 4)
          subject.x.should eq(3)
          subject.y.should eq(4)
        end

        it "calls methods on the hosted structure" do
          subject = Test::Vec.new(3, 4)
          subject.sum.should eq(7)

          subject.scale(2)
          subject.x.should eq(6)
          subject.y.should eq(8)

          subject.y = 1
          subject.sum.should eq(7)
        end

        it "is passed by value" do
          result = Test::Vec.new(1, 2).plus(Test::Vec.new(10, 20))
          result.x.should eq(11)
          result.y.should eq(22)
        end

        it "is passed by reference" do
          result = Test::Vec.new(1, 2).plus_ref(Test::Vec.new(10, 20))
          result.x.should eq(11)
          result.y.should eq(22)

          target = Test::Vec.new(10, 20)
          Test::Vec.new(1, 2).add_to_ref(target)
          target.x.should eq(11)
          target.y.should eq(22)
        end

        it "is passed by pointer" do
          result = Test::Vec.new(1, 2).plus_ptr(Test::Vec.new(10, 20))
          result.x.should eq(11)
          result.y.should eq(22)

          target = Test::Vec.new(10, 20)
          Test::Vec.new(1, 2).add_to(target)
          target.x.should eq(11)
          target.y.should eq(22)
        end

        it "is returned from a static method" do
          result = Test::Vec.unit
          result.x.should eq(1)
          result.y.should eq(1)
        end
      end

      context "structure with copied members" do
        it "has property methods copying the member" do
          subject = Test::Segment.new(
            from: Test::Vec.new(1, 2),
            to: Test::Vec.new(10, 20),
          )

          subject.from.should be_a(Test::Vec)
          subject.from.x.should eq(1)
          subject.to.y.should eq(20)
          subject.delta.x.should eq(9)
          subject.delta.y.should eq(18)

          subject.to = Test::Vec.new(5, 5)
          subject.delta.x.should eq(4)
          subject.delta.y.should eq(3)

          # This changes a copy.
          subject.from.x = 100
          subject.from.x.should eq(1)
        end
      end

      context "used by another class" do
        it "is returned by value" do
          subject = Test::VecUser.new
          subject.vec.x.should eq(3)
          subject.vec.y.should eq(4)
          subject.pod.a.should eq(5)
          subject.pod.b.should eq(6)
        end

        it "is copied when returned by reference or pointer" do
          subject = Test::VecUser.new

          by_ref = subject.vec_ref
          by_ref.x.should eq(3)
          by_ref.x = 100

          by_ptr = subject.vec_ptr
          by_ptr.x.should eq(3)
          by_ptr.y = 100

          subject.vec.x.should eq(3)
          subject.vec.y.should eq(4)
        end

        it "is passed by value" do
          subject = Test::VecUser.new
          subject.vec = Test::Vec.new(7, 8)
          subject.vec.x.should eq(7)
          subject.vec.y.should eq(8)

          subject.pod_sum(Test::Pod.new(a: 20, b: 3)).should eq(23)
        end

        it "is passed by reference" do
          subject = Test::VecUser.new
          subject.pod = Test::Pod.new(a: 9, b: 10)
          subject.pod.a.should eq(9)
          subject.pod.b.should eq(10)
        end
      end
    end
  end
end
