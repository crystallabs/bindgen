module Bindgen
  module CallBuilder
    # Builds a `Call` implementing a common method calling a `CrystalBinding`
    # call.
    class CrystalWrapper
      def initialize(@db : TypeDatabase)
      end

      # A constructor of a class wrapping a pointer binds the Crystal object
      # to the constructed one, see `ConstructorBody`, if *bind* is `true`:
      # not without the C++ glue defining `bindgen_set_crystal_object`.
      def build(method : Parser::Method, target : Call, bind = true)
        pass = Crystal::Pass.new(@db)

        block = !method.crystal_name.ends_with?('=') # A setter can't take a block
        arguments = pass.arguments_to_wrapper(method.arguments, method.out_arguments(@db), block: block)
        if method.any_constructor?
          body = ConstructorBody.new(@db, target, bind: bind && pointer_wrapper?(method.class_name))
        else
          body = MethodBody.new(@db, target)
        end

        Call.new(
          origin: method,
          name: method.crystal_name,
          arguments: arguments,
          result: pass.wrapper_result(method),
          body: body,
        )
      end

      abstract class Body < Call::HookableBody
        # Does the method forward to `#superclass` on an instance of a Crystal
        # subclass?  Set by `Processor::VirtualOverride` for the virtual
        # methods with a `Superclass` forwarder: a Crystal subclass, which the
        # `BindgenWrapper` annotation of the generated classes tells apart,
        # reaches the wrapper method by `super`, or by not overriding it, so
        # Crystal's dispatch ran its overrides already.  Calling the C++
        # implementation under the shadow class then, instead of the virtual
        # method, doesn't re-enter the override: `super` works.
        property super_forwarder = false

        def initialize(@db : TypeDatabase, @target : Call)
        end

        # The forwarding to `#superclass`, see `#super_forwarder`.  Only a
        # subclass of a class with a `Superclass` wrapper, whose wrapper has
        # the method (`superclass_ignore_methods` may leave it out), forwards.
        private def superclass_forwarding(call) : String
          args = call.arguments.map(&.name).join(", ")

          %[{% unless @type.annotation(BindgenWrapper) %}\n] \
          %[  {% if @type.has_method?("superclass") %}\n] \
          %[    if (_superclass_ = superclass).responds_to?(:#{call.name})\n] \
          %[      return _superclass_.#{call.name}(#{args})\n] \
          %[    end\n] \
          %[  {% end %}\n] \
          %[{% end %}\n]
        end

        # Generates the call itself.
        abstract def encapsulate(call, code)

        def encapsulate_into_variable(call, code)
          "result = " + encapsulate(call, code)
        end

        # Does the method return something: its result, or the values of its
        # out arguments as a `Call::TupleResult`?
        private def returns_value?(call) : Bool
          return false if call.origin.any_constructor?

          !call.result.type.pure_void? || call.result.is_a?(Call::TupleResult)
        end

        # Support for pre- and post hooks.  The locals of the out arguments of
        # the target, see `Call::OutArgument#prologue`, are declared first.
        private def encapsulate_and_hook(call, platform, code)
          pre = @pre_hook
          post = @post_hook

          String.build do |b|
            b << pre.to_code(call, platform) << "\n" if pre
            @target.arguments.each do |arg|
              b << arg.prologue << "\n" if arg.is_a?(Call::OutArgument)
            end

            if post && !returns_value?(call)
              # Nothing to return: The `Void` method returns `nil` after the hook.
              b << encapsulate(call, code) << "\n"
              b << post.to_code(call, platform)
            elsif post
              b << encapsulate_into_variable(call, code) << "\n"
              b << post.to_code(call, platform)
              b << "\nresult" unless call.origin.any_constructor?
            else
              b << encapsulate(call, code)
            end
          end
        end

        def to_code(call : Call, platform : Graph::Platform) : String
          method = Crystal::Method.new(@db)
          code = @target.body.to_code(@target, platform)
          code = encapsulate_and_hook(call, platform, code)
          code = superclass_forwarding(call) + code if @super_forwarder

          # Crystal doesn't like `#initialize` methods having an explicit return
          # type.
          result = call.result unless call.origin.any_constructor?

          head_line = method.prototype(
            name: call.name,
            arguments: call.arguments,
            result: result,
            static: call.origin.static?,
            abstract: call.origin.pure?,
            protected: call.origin.protected?,
            private: call.origin.private?,
            named_args: call.origin.aggregate_constructor?,
          )

          # The compiler copies a method expanding `@type`, like the forwarding
          # above, into a subclass once the method is called through the base
          # type.  The annotation tells `Processor::VirtualOverride`'s hook
          # such a copy from an override of the subclass.
          marker = "@[BindgenWrapper]\n" if @super_forwarder

          %[#{marker}#{head_line}\n] \
          %[  #{code}\n] \
          %[end\n]
        end
      end

      class MethodBody < Body
        # A `Call::TupleResult` of a `void` method runs the call as a statement
        # before the tuple of the out values.
        def encapsulate(call, code)
          result = call.result
          return result.apply_conversion(code) unless result.is_a?(Call::TupleResult)

          if result.inner
            result.literal(code)
          else
            "#{code}\n#{result.literal(nil)}"
          end
        end

        def encapsulate_into_variable(call, code)
          result = call.result
          if result.is_a?(Call::TupleResult) && result.inner.nil?
            "#{code}\nresult = #{result.literal(nil)}"
          else
            super
          end
        end
      end

      # Does the wrapper class of *class_name* hold a pointer to the object, a
      # `Reference` wrapping a class whose structure isn't copied?
      private def pointer_wrapper?(class_name : String) : Bool
        rules = @db[class_name]?
        !rules.nil? && rules.kind.class? && !rules.copy_structure?
      end

      # Body of an `#initialize`.  The constructed object remembers `self`,
      # see `BindgenHelper.set_crystal_object`, unless *bind* is `false`: for
      # the `unwrap:` initializer wrapping an existing object.
      class ConstructorBody < Body
        def initialize(db : TypeDatabase, target : Call, @bind = true)
          super(db, target)
        end

        def encapsulate_into_variable(call, code)
          encapsulate(call, code)
        end

        def encapsulate(call, code)
          bind = "\nBindgenHelper.set_crystal_object(result, self)" if @bind
          %[result = #{code}\n] \
          %[@unwrap = result#{bind}]
        end
      end
    end
  end
end
