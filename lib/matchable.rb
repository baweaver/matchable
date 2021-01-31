# frozen_string_literal: true

require_relative "matchable/version"

# Interface for Pattern Matching hooks
#
# @author baweaver
# @since 0.0.1
#
module Matchable
  # Constant to prepend methods and extensions to
  MODULE_NAME = "MatchableDeconstructors".freeze

  # Extend class methods for pattern matching hooks
  def self.included(klass) = klass.extend(ClassMethods)

  # Class method hooks for adding pattern matching interfaces
  #
  # @author baweaver
  # @since 0.0.1
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
      return if deconstructable_module.const_defined?('DECONSTRUCTION_METHOD')

      # :new should mean :initialize if one wants to match against arguments
      # to :new
      method_name = :initialize if method_name == :new
      deconstructable_module.const_set('DECONSTRUCTION_METHOD', method_name)

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
      return if deconstructable_module.const_defined?('DECONSTRUCTION_KEYS')

      # Ensure keys are symbols, then generate Ruby code for each
      # key assignment branch to be used below
      sym_keys        = keys.map(&:to_sym)
      deconstructions = sym_keys.map { deconstructed_value(_1) }.join("\n\n")

      # Retain a reference to which keys we deconstruct from
      deconstructable_module.const_set('DECONSTRUCTION_KEYS', sym_keys)

      # `public_send` can be slow, and `to_h` and `each_with_object` can also
      # be slow. This defines the direct method calls in-line to prevent
      # any performance penalties to generate optimal match code.
      deconstructable_module.class_eval <<~RUBY, __FILE__ , __LINE__ + 1
        def deconstruct_keys(keys)
          deconstructed_values = {}

          #{deconstructions}

          deconstructed_values
        end
      RUBY

      # To mask the return of the above class_eval
      nil
    end

    # Generates Ruby code for `deconstruct_keys` branches which will
    # directly call the method rather than utilizing `public_send` or
    # similar methods.
    #
    # Note that in the case of `keys` being `nil` it is expected to return
    # all keys that are possible from a pattern match rather than nothing,
    # hence adding this guard in every case.
    #
    # @param method_name [Symbol]
    #   Name of the method to add a deconstructed key from
    #
    # @return [String]
    #   Evaluatable Ruby code for adding a deconstructed key to requested
    #   values.
    private def deconstructed_value(method_name)
      <<~RUBY
        if keys.nil? || keys.include?(:#{method_name})
          deconstructed_values[:#{method_name}] = #{method_name}
        end
      RUBY
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

      deconstruction_code = if method_name == :initialize
        param_names = i_method.parameters.map(&:last)

        "[#{param_names.join(', ')}]"
      else
        method_name
      end

      deconstructable_module.class_eval <<~RUBY, __FILE__ , __LINE__ + 1
        def deconstruct
          #{deconstruction_code}
        end
      RUBY

      nil
    end

    # Prepended module to define methods against
    #
    # @return [Module]
    private def deconstructable_module
      if const_defined?(MODULE_NAME)
        const_get(MODULE_NAME)
      else
        const_set(MODULE_NAME, Module.new).tap(&method(:prepend))
      end
    end
  end
end
