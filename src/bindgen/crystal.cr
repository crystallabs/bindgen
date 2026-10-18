require "./type_helper"
require "./crystal/*"

module Bindgen
  # Functionality specific to the Crystal language.  Used by processors and
  # generators.
  module Crystal
    # All Crystal keywords
    KEYWORDS = %w[
      def if else elsif end true false class module include
      extend while until nil do yield return unless next break
      begin lib fun struct union enum macro out require
      case when select then of abstract rescue ensure is_a? alias
      pointerof sizeof instance_sizeof as as? typeof
      super private protected asm uninitialized nil? in
      self
    ]

    # All (overridable) Crystal operators
    OPERATORS = %w[
      + &+ - &- * &* / // % ** &**
      == != < <= > >= <=> === =~ !~
      ~ & | ^ << >>
      [] []? []=
    ]
  end
end
