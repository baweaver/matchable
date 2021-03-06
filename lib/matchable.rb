# frozen_string_literal: true

require_relative "matchable/version"

# Interface for Pattern Matching hooks
#
# @author baweaver
# @since 0.1.0
#
module Matchable
  # Nicety wrapper to ensure unmatched methods give a clear response on what's
  # missing
  #
  # @author baweaver
  # @since 0.1.1
  #
  class UnmatchedName < StandardError
    def initialize(msg)
      @msg = <<~ERROR
        Some attributes are missing methods for the match. Ensure all attributes
        have a method of the same name, or an `attr_` method.

        Original Error: #{msg}
      ERROR

      super(@msg)
    end
  end

  DeconstructedBranch = Struct.new(:method_name, :code_branch, :guard_condition)

  # Constant to prepend methods and extensions to
  MODULE_NAME = "MatchableDeconstructors".freeze

  # Extend class methods for pattern matching hooks
  def self.included(klass) = klass.extend(ClassMethods)

  # Class method hooks for adding pattern matching interfaces
  #
  # @author baweaver
  # @since 0.1.0
  module ClassMethods
    # Hook for the `deconstruct` instance method which triggers its definition
    # based on a deconstruction method passed. If the method is not yet defined
    # by the class it will wait until such a method is added to execute.
    #
    # @param method_name [Symbol]
    #   Name of the method to bind to
    #
    # @return [Array[status, method_name]]
    def deconstruct(method_name)
      return if matchable_module.const_defined?("MATCHABLE_METHOD")

      # :new should mean :initialize if one wants to match against arguments
      # to :new
      method_name = :initialize if method_name == :new
      matchable_module.const_set("MATCHABLE_METHOD", method_name)

      # If this was called after the method was added, go ahead and attach,
      # otherwise we need some trickery to make sure the method is defined
      # first if they used this at the top of the class above its definition.
      if method_defined?(method_name)
        attach_deconstructor(method_name)
        return [true, method_name]
      end

      # Otherwise we set a flag, and hand it to `method_added` to clean up
      # after this method
      @_awaited_deconstruction_method = method_name
      [false, method_name]
    end

    # Method Added hook, will trigger only if `deconstruct` could not bind to
    # a method because it didn't exist yet.
    #
    # @param method_name [Symbol]
    #   Name of the method currently being defined
    #
    # @return [void]
    def method_added(method_name)
      return unless defined?(@_awaited_deconstruction_method)
      return unless @_awaited_deconstruction_method == method_name

      attach_deconstructor(method_name)
      remove_instance_variable(:@_awaited_deconstruction_method)

      # Return is irrelevant here, mask response from `remove_instance_variable`
      nil
    end

    # Hook for the `deconstruct_keys` method which triggers its defintion based
    # on the keys passed to this method.
    #
    # @param *keys [Array[Symbol]]
    #   Keys to deconstruct values from. Each must have an associated instance
    #   method to work, or this will fail.
    #
    # @return [void]
    def deconstruct_keys(*keys)
      # Return early if called more than once
      return if matchable_module.const_defined?('MATCHABLE_KEYS')

      # Ensure keys are symbols, then generate Ruby code for each
      # key assignment branch to be used below
      sym_keys = keys.map(&:to_sym)

      # Retain a reference to which keys we deconstruct from
      matchable_module.const_set('MATCHABLE_KEYS', sym_keys)

      # Lazy Hash mapping of all keys to all values wrapped in lazy
      # procs.
      #
      # see: #lazy_match_value
      matchable_module.const_set('MATCHABLE_LAZY_VALUES', lazy_match_values(sym_keys))

      # `public_send` can be slow, and `to_h` and `each_with_object` can also
      # be slow. This defines the direct method calls in-line to prevent
      # any performance penalties to generate optimal match code.
      #
      # This generates and adds a method to the prepended module. We add YARDoc
      # to this because the generated source can be seen and we want to be nice.
      #
      # We also intercept name errors to give more useful errors should it
      # be implemented incorrectly.
      matchable_module.class_eval <<~RUBY, __FILE__ , __LINE__ + 1
        # Pattern Matching hooks for hash-like matches.
        #
        # This method was generated by Matchable. Make sure all properties have
        # associated methods attached or this will raise an error.
        #
        # @param keys [Array[Symbol]]
        #   Keys to limit the deconstruction to. If keys are `nil` then return
        #   all possible keys instead.
        #
        # @return [Hash[Symbol, Any]]
        #   Deconstructed keys and values
        def deconstruct_keys(keys)
          # If `keys` is `nil` we want to return all possible keys. This
          # generates all of them as a direct Hash representation and
          # returns that, rather than guard all methods below on
          # `keys.nil? || ...`.
          if keys.nil?
            return {
              #{nil_guard_values(sym_keys)}
            }
          end

          # If keys are present, we want to iterate the keys to add requested
          # values. Before we iterate we also want to ensure only valid keys
          # are being passed through here.
          deconstructed_values = {}
          valid_keys           = MATCHABLE_KEYS & keys

          # This is where things get interesting. Each value is retrieved through
          # a lazy hash in which `method_name or `key` points to a proc:
          #
          #   key: -> o { o.key }
          #
          # The actual method is interpolated directly and `eval`'d to make this
          # faster than `public_send`.
          valid_keys.each do |key|
            deconstructed_values[key] = MATCHABLE_LAZY_VALUES[key].call(self)
          end

          # ...and once this is done, return back the deconstructed values.
          deconstructed_values
        # We rescue `NameError` here to return a more useful message and indicate
        # there are some missing methods for the match.
        rescue NameError => e
          raise Matchable::UnmatchedName, e
        end
      RUBY

      # To mask the return of the above class_eval
      nil
    end

    # Generates key-value pairs of `method_name` pointing to `method_name` for
    # the case where `keys` is `nil`, requiring all keys to be directly returned.
    #
    # @param method_names [Array[Symbol]]
    #   Names of the methods
    #
    # @return [String]
    #   Ruby code for all key-value pairs for method names
    def nil_guard_values(method_names)
      method_names
        .map { |method_name| "#{method_name}: #{method_name}" }
        .join(",\n")
    end

    # Generated Ruby Hash based on a mapping of valid keys to a lazy function
    # to retrieve them directly without the need for `public_send` or similar
    # methods. This code instead directly interpolates the method call and
    # evaluates that, but will not run the code until called as a proc in the
    # actual `deconstruct_keys` method.
    #
    # @param method_names [Array[Symbol]]
    #   Names of the methods
    #
    # @return [Hash[Symbol, Proc]]
    #   Mapping of deconstruction key to lazy retrieval function
    def lazy_match_values(method_names)
      method_names
        # Name of the method points to a lazy function to retrieve it
        .map { |method_name| "  #{method_name}: -> o { o.#{method_name} }," }
        # Join them into one String
        .join("\n")
        # Wrap them in Hash brackets
        .then { |kv_pairs| "{\n#{kv_pairs}\n}"}
        # ...and `eval` it to turn it into a Hash
        .then { |ruby_code| eval ruby_code }
    end

    # Attaches the deconstructor to the parent class. If the method is
    # initialize we want to deconstruct based on the parameters of class
    # instantiation rather than alias that method, as this is a common method
    # of deconstruction.
    #
    # @param method_name [Symbol]
    #   Method to deconstruct from
    #
    # @return [void]
    private def attach_deconstructor(method_name)
      i_method = instance_method(method_name)

      deconstruction_code =
        # If the method is `initialize` we want to treat it differently, as
        # it represents a unique destructuring based on the method's parameters.
        if method_name == :initialize
          # Example of parameters:
          #
          #   -> a, b = 2, *c, d:, e: 3, **f, &fn {}.parameters
          #   # => [
          #   #   [:req, :a], [:opt, :b], [:rest, :c], [:keyreq, :d], [:key, :e],
          #   #   [:keyrest, :f], [:block, :fn]
          #   # ]
          #
          # The `last` of each is the name of the param. This assumes a tied
          # method to each of these names, and will fail otherwise.
          param_names = i_method.parameters.map(&:last)

          # Take the literal names of those parameters and treat them like
          # method calls to have the entire thing inlined
          "[#{param_names.join(', ')}]"
        # Otherwise we just want the method name, don't do anything special to
        # this. If you have any other methods that might make sense here let me
        # know by filing an issue.
        else
          method_name
        end

      # Then we evaluate that in the context of our prepended module and away
      # we go with our new method. Added YARDoc because this will show up in the
      # actual code and we want to be nice.
      matchable_module.class_eval <<~RUBY, __FILE__ , __LINE__ + 1
        # Pattern Matching hook for array-like deconstruction methods.
        #
        # This method was generated by Matchable and based on the `#{method_name}`
        # method. Make sure all properties have associated methods attached or
        # this will raise an error.
        #
        # @return [Array]
        def deconstruct
          #{deconstruction_code}
        # We rescue `NameError` here to return a more useful message and indicate
        # there are some missing methods for the match.
        rescue NameError => e
          raise Matchable::UnmatchedName, e
        end
      RUBY

      # Return back nil because this value really should not be relied upon
      nil
    end

    # Prepended module to define methods against
    #
    # @return [Module]
    private def matchable_module
      if const_defined?(MODULE_NAME)
        const_get(MODULE_NAME)
      else
        const_set(MODULE_NAME, Module.new).tap(&method(:prepend))
      end
    end
  end
end
